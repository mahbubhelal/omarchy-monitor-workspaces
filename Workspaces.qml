import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.risent.monitor-workspaces"

  readonly property string indicatorStyle: {
    var requested = String(setting("indicatorStyle", "Underline")).toLowerCase()
    var choices = ["underline", "typography", "dot", "grouped", "circle"]
    return choices.indexOf(requested) === -1 ? "underline" : requested
  }
  readonly property int baseWorkspaceCount: Math.max(1, Math.min(20,
    Number(setting("baseWorkspaceCount", 5)) || 5))
  readonly property int maxWorkspaceId: Math.max(baseWorkspaceCount, Math.min(99,
    Number(setting("maxWorkspaceId", 10)) || 10))
  readonly property int maxNameLength: Math.max(3, Math.min(40,
    Number(setting("maxNameLength", 12)) || 12))
  // "1:chrome, 2:code" -> { 1: "chrome", 2: "code" }
  readonly property var workspaceNames: {
    var names = {}
    var entries = String(setting("workspaceNames", "")).split(",")
    for (var i = 0; i < entries.length; i++) {
      var separator = entries[i].indexOf(":")
      if (separator === -1) continue
      var id = Number(entries[i].slice(0, separator).trim())
      var name = entries[i].slice(separator + 1).trim()
      if (name.length > maxNameLength) name = name.slice(0, maxNameLength - 1) + "…"
      if (id > 0 && name !== "") names[id] = name
    }
    return names
  }

  readonly property var barMonitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : null
  }

  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace
    ? Hyprland.focusedWorkspace.id : 0
  readonly property string focusedMonitorName: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.monitor
    ? String(Hyprland.focusedWorkspace.monitor.name || "") : ""

  // Workspace id -> monitor rule ("DP-3" or "desc:..."). Empty workspaces carry
  // no monitor of their own, so their group comes from the rules.
  property var workspaceRules: ({})

  Process {
    id: workspaceRulesProc
    running: true
    command: ["hyprctl", "-j", "workspacerules"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyWorkspaceRules(text)
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name || "") : ""
      // Quickshell 0.3.1 can leave monitor.activeWorkspace stale after a
      // workspace moves between monitors.
      if (name === "moveworkspacev2") Hyprland.refreshMonitors()
      // hyprmoncfg rewrites the workspace rules and reloads when the monitors change.
      if (name === "configreloaded" || name.indexOf("monitoradded") === 0
          || name.indexOf("monitorremoved") === 0) workspaceRulesProc.running = true
    }
  }

  function applyWorkspaceRules(json) {
    var rules = {}
    try {
      var parsed = JSON.parse(json)
      for (var i = 0; i < parsed.length; i++) {
        var id = Number(parsed[i].workspaceString)
        if (id > 0 && parsed[i].monitor) rules[id] = String(parsed[i].monitor)
      }
    } catch (error) {
      console.warn("monitor-workspaces: could not read workspace rules: " + error)
    }
    root.workspaceRules = rules
  }

  // The monitor a workspace belongs to: where it is now, else where its rule pins it.
  function homeMonitorName(id) {
    var current = workspaceMonitorName(id)
    if (current !== "") return current
    var rule = root.workspaceRules[id]
    if (!rule) return ""
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var description = String(monitors[i].description || "")
      if (rule === monitors[i].name
          || (rule.indexOf("desc:") === 0 && description.indexOf(rule.slice(5)) === 0))
        return String(monitors[i].name)
    }
    return ""
  }

  function shownWorkspaceIds() {
    var ids = []
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].activeWorkspace) ids.push(monitors[i].activeWorkspace.id)
    }
    return ids
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceMonitorName(id) {
    var workspace = workspaceById(id)
    return workspace && workspace.monitor ? String(workspace.monitor.name || "") : ""
  }

  function monitorWorkspaceId() {
    var active = root.barMonitor ? root.barMonitor.activeWorkspace : null
    return active ? active.id : -1
  }

  function workspaceIds() {
    var ids = []
    for (var id = 1; id <= root.baseWorkspaceCount; id++) ids.push(id)

    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var workspaceId = values[i].id
      if (workspaceId > 0 && workspaceId <= root.maxWorkspaceId
          && ids.indexOf(workspaceId) === -1) ids.push(workspaceId)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function startsMonitorGroup(index, id) {
    if (index <= 0) return false
    var ids = workspaceIds()
    var previousName = workspaceMonitorName(ids[index - 1])
    var currentName = workspaceMonitorName(id)
    return previousName !== "" && currentName !== "" && previousName !== currentName
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch "
      + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: workspaceButton

        required property int index
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool displayed: root.monitorWorkspaceId() === modelData
        readonly property bool onThisMonitor: workspace !== null
          && workspace.monitor !== null
          && root.barMonitor !== null
          && workspace.monitor.name === root.barMonitor.name
        // Some monitor is showing this workspace right now.
        readonly property bool shown: root.shownWorkspaceIds().indexOf(modelData) !== -1
        // It belongs to a monitor other than the focused one.
        readonly property bool faded: root.focusedMonitorName !== ""
          && root.homeMonitorName(modelData) !== ""
          && root.homeMonitorName(modelData) !== root.focusedMonitorName
        readonly property color baseForeground: root.bar ? root.bar.barForeground : Color.foreground
        // The theme's text colour with some of its red blended in, both from the active theme.
        readonly property color fadedForeground: Qt.tint(baseForeground,
          Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.6))

        readonly property string number: modelData === 10 ? "0" : String(modelData)
        // Names don't fit across a vertical bar, so it keeps the bare number.
        readonly property string workspaceName: root.vertical ? "" : (root.workspaceNames[modelData] || "")

        bar: root.bar
        text: workspaceName !== "" ? number + ": " + workspaceName : number
        foreground: displayed && root.indicatorStyle === "circle"
          ? Color.background
          : (displayed && root.indicatorStyle === "typography"
            ? Color.accent
            : (faded ? fadedForeground : baseForeground))
        fontSize: displayed && root.indicatorStyle === "typography"
          ? Style.font.body + 1 : Style.font.body
        opacity: shown || occupied ? 1 : 0.35
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : (workspaceName !== "" ? -1 : Style.space(20))
        fixedHeight: root.barSize
        tooltipText: workspace && workspace.monitor
          ? "Workspace " + modelData + " · " + workspace.monitor.name
          : "Workspace " + modelData
        onPressed: function() { root.focusWorkspace(modelData) }

        Rectangle {
          visible: root.indicatorStyle === "circle"
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(2), Style.space(18))
          height: Math.min(parent.height - Style.space(4), Style.space(18))
          radius: Math.min(width, height) / 2
          color: workspaceButton.displayed ? Color.accent : "transparent"
          border.width: workspaceButton.onThisMonitor && !workspaceButton.displayed ? 1 : 0
          border.color: Color.accent
          z: -1

          Behavior on color { ColorAnimation { duration: 140 } }
        }

        Rectangle {
          readonly property int inset: Style.space(2)

          visible: workspaceButton.shown
            && (root.indicatorStyle === "underline" || root.indicatorStyle === "grouped")
          color: workspaceButton.modelData === root.focusedWorkspaceId
            ? Color.accent : workspaceButton.activeColor
          radius: Math.min(width, height) / 2
          width: root.vertical ? Style.space(2) : Style.space(12)
          height: root.vertical ? Style.space(12) : Style.space(2)
          x: root.vertical
            ? (root.bar && root.bar.position === "left" ? parent.width - width - inset : inset)
            : Math.round((parent.width - width) / 2)
          y: root.vertical
            ? Math.round((parent.height - height) / 2)
            : (root.bar && root.bar.position === "bottom" ? inset : parent.height - height - inset)
        }

        Rectangle {
          readonly property int inset: Style.space(2)

          visible: workspaceButton.displayed && root.indicatorStyle === "dot"
          width: Style.space(3)
          height: width
          radius: width / 2
          color: Color.accent
          x: root.vertical
            ? (root.bar && root.bar.position === "left" ? parent.width - width - inset : inset)
            : Math.round((parent.width - width) / 2)
          y: root.vertical
            ? Math.round((parent.height - height) / 2)
            : (root.bar && root.bar.position === "bottom" ? inset : parent.height - height - inset)
        }

        Rectangle {
          visible: root.indicatorStyle === "grouped"
            && root.startsMonitorGroup(workspaceButton.index, workspaceButton.modelData)
          color: root.bar ? root.bar.barForeground : Color.foreground
          opacity: 0.28
          width: root.vertical ? Style.space(12) : 1
          height: root.vertical ? 1 : Style.space(12)
          x: root.vertical ? Math.round((parent.width - width) / 2) : -Style.space(1)
          y: root.vertical ? -Style.space(1) : Math.round((parent.height - height) / 2)
        }
      }
    }
  }
}

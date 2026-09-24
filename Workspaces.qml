import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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

  readonly property var barMonitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : null
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

        bar: root.bar
        text: modelData === 10 ? "0" : String(modelData)
        foreground: displayed && root.indicatorStyle === "circle"
          ? Color.background
          : (displayed && root.indicatorStyle === "typography"
            ? Color.accent
            : (root.bar ? root.bar.barForeground : Color.foreground))
        fontSize: displayed && root.indicatorStyle === "typography"
          ? Style.font.body + 1 : Style.font.body
        opacity: displayed || onThisMonitor ? 1 : (occupied ? 0.6 : 0.3)
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
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

          visible: workspaceButton.displayed
            && (root.indicatorStyle === "underline" || root.indicatorStyle === "grouped")
          color: Color.accent
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

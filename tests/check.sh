#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

omarchy plugin validate "$plugin_dir"
jq -e '
  .schemaVersion == 1
  and .id == "io.github.risent.monitor-workspaces"
  and (.kinds | index("bar-widget") != null)
  and .entryPoints.barWidget == "Workspaces.qml"
' "$plugin_dir/manifest.json" >/dev/null
qmllint -I /usr/share/omarchy/shell -I /usr/lib/qt6/qml "$plugin_dir/Workspaces.qml"

echo "All checks passed."

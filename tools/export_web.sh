#!/bin/sh
# Stamps the build time into the game, then exports the web build to docs/.
cd "$(dirname "$0")/.."
printf 'class_name BuildInfo\nextends RefCounted\n## Written by tools/export_web.sh at export time.\nconst STAMP := "%s"\n' "$(date -u '+%Y-%m-%d %H:%M')" > scripts/build_info.gd
/root/godot47/godot --headless --path . --import >/dev/null 2>&1
/root/godot47/godot --headless --path . --export-release "Web" docs/index.html

#!/usr/bin/env bash
# Builds the native library for Linux (the server) and Windows (mingw):
#   native/build.sh            both
#   native/build.sh linux      just one
set -euo pipefail
cd "$(dirname "$0")"
GODOT_CPP_COMMIT=27d9dd23c83871e0619fca5dc2cddfbfd69e926a # the 4.5 branch: runs on Godot 4.5 and later
if [ ! -d godot-cpp ]; then
	git clone -q --filter=blob:none https://github.com/godotengine/godot-cpp.git godot-cpp
fi
(cd godot-cpp && git fetch -q origin "$GODOT_CPP_COMMIT" && git checkout -q "$GODOT_CPP_COMMIT")
touch godot-cpp/.gdignore src/.gdignore # not Godot's to import
for p in ${1:-linux windows}; do
	scons -j"$(nproc)" platform="$p" target=template_release
done

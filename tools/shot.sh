#!/bin/bash
# Quick screenshots of the town from set viewpoints, for checking a change
# without playing. The first call starts the game in the background and
# loads the town (a minute or so); after that each picture takes seconds.
#
#   tools/shot.sh NAME:x,z,yaw,pitch[,lift] [more shots...]
#   tools/shot.sh --size=1920x1080 --low spawn:0,0,0,-12
#   tools/shot.sh --stop
#
# x, z are game metres (+x east, +z south; 0,0 is Great George and
# Richmond), yaw 0 looks north and 90 west, pitch is degrees up (negative
# looks down), lift is metres above the ground (default 1.7, eye height).
# A straight-down look from 80 m:  top:-300,-1700,0,-90,80
#
# Pictures go to /tmp/tca-shots/NAME.png (TCA_SHOT_DIR changes where), and
# the paths are printed when they're done.
#
# Options (they need a fresh start, which happens by itself when they
# change): --size=WxH (default 1280x720), --low (the Low graphics setting:
# a little quicker, plainer).
#
# The game keeps running between calls. It picks up map editor changes
# (data/edits.json) by itself; when a script, shader, scene or
# map_config.json is newer than the running game, it's restarted first.
#
# Runs on a desktop as it is. On a machine with no screen or graphics card
# (a cloud container) it draws in software with Mesa's lavapipe under
# Xvfb, if they're installed.

set -u
cd "$(dirname "$0")/.."
DIR="${TCA_SHOT_DIR:-/tmp/tca-shots}"
GODOT="${GODOT:-godot}"
SIZE=1280x720
LOW=""
SHOTS=()
STOP=""
for a in "$@"; do
	case "$a" in
		--size=*) SIZE="${a#--size=}" ;;
		--low) LOW="--graphics=low" ;;
		--stop) STOP=1 ;;
		-*) echo "shot.sh: unknown option $a" >&2; exit 2 ;;
		*) SHOTS+=("$a") ;;
	esac
done
mkdir -p "$DIR"

running() {
	[ -f "$DIR/server.pid" ] && kill -0 "$(cat "$DIR/server.pid")" 2>/dev/null
}

stop_server() {
	if running; then
		echo quit > "$DIR/stop.tmp" && mv "$DIR/stop.tmp" "$DIR/stop.req"
		for _ in $(seq 50); do running || break; sleep 0.2; done
		running && kill "$(cat "$DIR/server.pid")" 2>/dev/null
		# xvfb-run's own children.
		pkill -f "shot_server.gd -- --dir=$DIR" 2>/dev/null
	fi
	rm -f "$DIR/server.pid" "$DIR/server.ready" "$DIR/server.opts" "$DIR"/*.req
}

if [ -n "$STOP" ]; then
	stop_server
	echo "shot.sh: stopped"
	exit 0
fi
if [ ${#SHOTS[@]} -eq 0 ]; then
	sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
fi

OPTS="$SIZE $LOW"
if running; then
	# Restart if the options changed or the game's code is newer than it.
	if [ "$(cat "$DIR/server.opts" 2>/dev/null)" != "$OPTS" ] || \
		[ -n "$(find scripts shaders scenes data/map_config.json data/city/street_fit.json -newer "$DIR/server.ready" -type f 2>/dev/null | head -1)" ]; then
		echo "shot.sh: code or options changed, restarting the game"
		stop_server
	fi
fi

if ! running; then
	rm -f "$DIR/server.ready" "$DIR"/*.req "$DIR"/*.done
	echo "$OPTS" > "$DIR/server.opts"
	ARGS=(--path . --resolution "$SIZE" --script res://tools/shot_server.gd -- "--dir=$DIR" --no-auto-res $LOW)
	if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
		# No screen: software Vulkan under a virtual display.
		[ -f /opt/lavapipe/lvp_icd.json ] && export VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json
		export LP_PERF=no_rast_linear GALLIVM_PERF=no_aos_sampling
		W="${SIZE%x*}"; H="${SIZE#*x}"
		nohup xvfb-run -a -s "-screen 0 ${W}x${H}x24" "$GODOT" --rendering-driver vulkan "${ARGS[@]}" > "$DIR/server.log" 2>&1 &
	else
		nohup "$GODOT" "${ARGS[@]}" > "$DIR/server.log" 2>&1 &
	fi
	echo $! > "$DIR/server.pid"
	echo "shot.sh: starting the game (log: $DIR/server.log)"
	for _ in $(seq 1500); do
		[ -f "$DIR/server.ready" ] && break
		if ! running; then echo "shot.sh: the game stopped while starting; see $DIR/server.log" >&2; tail -20 "$DIR/server.log" >&2; exit 1; fi
		sleep 0.2
	done
	[ -f "$DIR/server.ready" ] || { echo "shot.sh: the game didn't get ready in 5 minutes" >&2; exit 1; }
	echo "shot.sh: game ready in $(( $(cat "$DIR/server.ready") / 1000 )) s"
fi

ID="$(date +%s%N)"
printf '%s\n' "${SHOTS[@]}" > "$DIR/$ID.tmp"
mv "$DIR/$ID.tmp" "$DIR/$ID.req"
while [ ! -f "$DIR/$ID.done" ]; do
	if ! running; then echo "shot.sh: the game stopped; see $DIR/server.log" >&2; tail -20 "$DIR/server.log" >&2; exit 1; fi
	sleep 0.2
done
OUT="$(cat "$DIR/$ID.done")"
rm -f "$DIR/$ID.done"
echo "$OUT"
grep -q '^ERROR' <<< "$OUT" && exit 1
exit 0

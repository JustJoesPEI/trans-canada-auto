class_name MapEditorServer
extends Node
## Serves the map editor (tools/map_editor.html) to a browser on this
## computer while the game runs from Godot, so F8 opens it already
## connected: it loads the map from the game, saves the edits straight into
## data/edits.json (which the game then picks up live), sets "Test here",
## and shows where the player is. Listens on 127.0.0.1 only, so nothing
## outside this computer can reach it, and it writes only those two files.
## Not started in exported copies (their map is packed inside them).

const FIRST_PORT := 8790
const EDITOR_PAGE := "/tools/map_editor.html"
const TEST_START := "res://data/test_start.json"
const TYPES := {"html": "text/html; charset=utf-8", "json": "application/json", "geojson": "application/json",
	"png": "image/png", "js": "text/javascript", "css": "text/css", "svg": "image/svg+xml"}

var world: WorldBuilder
var player: Node3D
var port := 0

var _server := TCPServer.new()
var _thread: Thread
var _running := false
var _mutex := Mutex.new()
var _player_info := {}


## Starts listening; false if it can't (an exported copy, or no free port).
func start() -> bool:
	if not OS.has_feature("editor"):
		return false
	for p in range(FIRST_PORT, FIRST_PORT + 10):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	if port == 0:
		push_warning("MapEditorServer: no free port for the map editor")
		return false
	_running = true
	_thread = Thread.new()
	_thread.start(_serve)
	print("Map editor: press F8 in the game, or open %s" % url())
	return true


func url() -> String:
	return "http://127.0.0.1:%d%s" % [port, EDITOR_PAGE]


## Opens the editor in the computer's web browser.
func open_in_browser() -> void:
	if port != 0:
		OS.shell_open(url())


func _process(_delta: float) -> void:
	if player == null or world == null or not world.is_built or world.data == null:
		return
	var p := player.global_position
	var fwd := -player.global_basis.z
	var ll := world.data.projection.to_lon_lat(Vector2(p.x, p.z))
	var info := {"x": snappedf(p.x, 0.1), "z": snappedf(p.z, 0.1), "lon": ll.x, "lat": ll.y,
		"direction": snappedf(fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0), 1.0)}
	_mutex.lock()
	_player_info = info
	_mutex.unlock()


func _exit_tree() -> void:
	_running = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_server.stop()


# --- the server thread -----------------------------------------------------------------------

func _serve() -> void:
	while _running:
		if _server.is_connection_available():
			var c := _server.take_connection()
			if c != null:
				_handle(c)
		else:
			OS.delay_msec(8)


func _handle(c: StreamPeerTCP) -> void:
	var buf := PackedByteArray()
	var header_end := -1
	var deadline := Time.get_ticks_msec() + 3000
	while header_end < 0 and Time.get_ticks_msec() < deadline:
		c.poll()
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return
		var n := c.get_available_bytes()
		if n > 0:
			buf.append_array(c.get_data(n)[1])
			header_end = _find_blank_line(buf)
		else:
			OS.delay_msec(2)
	if header_end < 0:
		c.disconnect_from_host()
		return
	var head := buf.slice(0, header_end).get_string_from_utf8()
	var lines := head.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		c.disconnect_from_host()
		return
	var method := first[0]
	var path := first[1].split("?")[0].uri_decode()
	var length := 0
	for l in lines:
		if l.to_lower().begins_with("content-length:"):
			length = l.substr(15).strip_edges().to_int()
	var body := buf.slice(header_end + 4)
	while body.size() < length and Time.get_ticks_msec() < deadline + 10000:
		c.poll()
		var n := c.get_available_bytes()
		if n > 0:
			body.append_array(c.get_data(n)[1])
		else:
			OS.delay_msec(2)
	_route(c, method, path, body)
	c.disconnect_from_host()


static func _find_blank_line(b: PackedByteArray) -> int:
	for i in range(b.size() - 3):
		if b[i] == 13 and b[i + 1] == 10 and b[i + 2] == 13 and b[i + 3] == 10:
			return i
	return -1


func _route(c: StreamPeerTCP, method: String, path: String, body: PackedByteArray) -> void:
	if method == "GET" and (path == "/" or path == "/editor"):
		_send(c, 302, "text/plain", "".to_utf8_buffer(), "Location: %s\r\n" % EDITOR_PAGE)
	elif method == "GET" and path == "/api/ping":
		_send_json(c, {"game": "Trans-Canada Auto", "map": str(world.data.config.get("map", {}).get("name", "")) if world != null and world.data != null else ""})
	elif method == "GET" and path == "/api/test_start":
		var t: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_START)) if FileAccess.file_exists(TEST_START) else {}
		_send_json(c, t if t is Dictionary else {})
	elif method == "GET" and path == "/api/player":
		_mutex.lock()
		var info := _player_info.duplicate()
		_mutex.unlock()
		_send_json(c, info)
	elif method == "POST" and path == "/api/save/edits":
		var target := "res://data/edits.json"
		if world != null and world.data != null:
			target = str(world.data.config.get("edits", target))
		_save_json(c, target, body)
	elif method == "POST" and path == "/api/save/test_start":
		_save_json(c, TEST_START, body)
	elif method == "POST" and path == "/api/clear/test_start":
		if FileAccess.file_exists(TEST_START):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_START))
		_send_json(c, {"ok": true})
	elif method == "GET" and (path.begins_with("/tools/") or path.begins_with("/data/")) and not path.contains(".."):
		var res := "res:/" + path
		if not FileAccess.file_exists(res):
			_send(c, 404, "text/plain", "Not found".to_utf8_buffer())
			return
		_send(c, 200, str(TYPES.get(path.get_extension().to_lower(), "application/octet-stream")), FileAccess.get_file_as_bytes(res))
	else:
		_send(c, 404, "text/plain", "Not found".to_utf8_buffer())


## Writes a JSON body to `target`, after checking it really is JSON.
func _save_json(c: StreamPeerTCP, target: String, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	if not (JSON.parse_string(text) is Dictionary):
		_send(c, 400, "text/plain", "Not a JSON object".to_utf8_buffer())
		return
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		_send(c, 500, "text/plain", ("Couldn't write " + target).to_utf8_buffer())
		return
	f.store_string(text)
	f.close()
	_send_json(c, {"ok": true, "file": target})


func _send_json(c: StreamPeerTCP, v: Variant) -> void:
	_send(c, 200, "application/json", JSON.stringify(v).to_utf8_buffer())


func _send(c: StreamPeerTCP, code: int, type: String, data: PackedByteArray, extra := "") -> void:
	var reason: String = {200: "OK", 302: "Found", 400: "Bad Request", 404: "Not Found", 500: "Server Error"}.get(code, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n%s\r\n" % [code, reason, type, data.size(), extra]
	c.put_data(head.to_utf8_buffer())
	if not data.is_empty():
		c.put_data(data)

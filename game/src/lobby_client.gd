class_name LobbyClient
extends Node
## Talks to the lobby's JSON API: what public games are running, make me a
## new one, is this code real.
##
## Deliberately has no UI in it and no opinion about what to do with an
## answer — lobby_screen.gd draws, this fetches. That split is what lets
## the URL building be unit-tested without a window.

signal rooms_listed(rooms: Array)
signal room_created(room: Dictionary)
signal lookup_finished(code: String, room: Dictionary)
signal failed(what: String, message: String)

## A room that no longer exists, or a code nobody ever had. Returned as an
## empty dictionary rather than an error, because "that game has finished"
## is a normal thing to tell somebody, not a fault.
const NOT_FOUND := {}

var _list_req: HTTPRequest
var _create_req: HTTPRequest
var _lookup_req: HTTPRequest

## Where the lobby's API lives. Derived from wherever the game socket
## points, so a LAN server, a dev box and battlebox.games all work with no
## build-time configuration — exactly as the socket URL already does.
static func api_base() -> String:
	return Net.lobby_base()

func _ready() -> void:
	_list_req = _make_request()
	_create_req = _make_request()
	_lookup_req = _make_request()

func _make_request() -> HTTPRequest:
	var request := HTTPRequest.new()
	# A lobby that is not answering must not leave the player looking at a
	# spinner: fail, and let the screen offer the house game instead.
	request.timeout = 8.0
	add_child(request)
	return request

## The public games, newest and busiest first.
func list_rooms() -> void:
	_fetch(_list_req, "%s/api/rooms" % api_base(), func(payload: Dictionary) -> void:
		var rooms: Array = payload.get("rooms", [])
		rooms_listed.emit(rooms), "list")

## Start a game. `public` decides whether strangers see it on the front
## page; either way the answer carries the code that gets people in.
##
## `settings` is what KIND of game — mode, world, size, round length, how
## many computer players (see game_setup.gd). It travels with the create
## rather than being applied once the creator has connected, because a
## world is generated at boot from its environment: sent this way the
## terrain IS the map that was asked for, and sent afterwards it is a
## reset performed on somebody who is already standing in it.
##
## Sent as given. Clamping it here would be a courtesy, not a defence —
## the lobby validates it again on arrival, because a POST is a POST.
func create_room(display_name: String, public: bool,
		settings: Dictionary = {}) -> void:
	var body := JSON.stringify({"name": display_name, "public": public,
		"settings": settings})
	var err := _create_req.request("%s/api/rooms" % api_base(),
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, body)
	if err != OK:
		failed.emit("create", "Could not reach the lobby")
		return
	_once(_create_req, func(code: int, payload: Dictionary) -> void:
		if code == 503:
			failed.emit("create", str(payload.get("error", "No free games right now")))
		elif code != 201 or not payload.has("code"):
			failed.emit("create", str(payload.get("error", "The game would not start")))
		else:
			room_created.emit(payload))

## Is this code a game that is running right now?
func look_up(code: String) -> void:
	var wanted := code.strip_edges().to_lower()
	_fetch(_lookup_req, "%s/api/rooms/%s" % [api_base(), wanted.uri_encode()],
		func(payload: Dictionary) -> void:
			lookup_finished.emit(wanted, payload), "lookup",
		func() -> void: lookup_finished.emit(wanted, NOT_FOUND))

func _fetch(request: HTTPRequest, url: String, on_ok: Callable, what: String,
		on_missing := Callable()) -> void:
	var err := request.request(url)
	if err != OK:
		failed.emit(what, "Could not reach the lobby")
		return
	_once(request, func(code: int, payload: Dictionary) -> void:
		if code == 404 and on_missing.is_valid():
			on_missing.call()
		elif code != 200:
			failed.emit(what, "The lobby said %d" % code)
		else:
			on_ok.call(payload))

## HTTPRequest keeps its signal connections between calls, so a handler
## left connected fires again on the NEXT request holding the previous
## call's closure. CONNECT_ONE_SHOT is what disconnects it — a lambda that
## disconnects itself cannot, because a GDScript closure captures by VALUE
## at creation, so the variable naming it is still null inside it.
func _once(request: HTTPRequest, handler: Callable) -> void:
	request.request_completed.connect(
		func(_result: int, code: int, _headers: PackedStringArray,
				body: PackedByteArray) -> void:
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			handler.call(code, parsed if parsed is Dictionary else {}),
		CONNECT_ONE_SHOT)

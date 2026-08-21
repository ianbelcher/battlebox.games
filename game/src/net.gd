extends Node
## Connection management. WebSocket transport (same server binary talks to
## every client; on a LAN the TCP-vs-UDP difference is negligible).

const DEFAULT_PORT := 9081

## The public world. One host serves the page, the downloads and the game
## socket, all on 443 — the websocket is proxied through the same origin
## as everything else (see nginx.conf), so there is only ever one name and
## one port to get wrong.
const PUBLIC_HOST := "battlebox.games"
const PUBLIC_SERVER_URL := "wss://battlebox.games/ws"


signal connected_to_server
signal connection_failed
signal server_disconnected

var is_server := false

func _ready() -> void:
	multiplayer.connected_to_server.connect(func() -> void: connected_to_server.emit())
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: server_disconnected.emit())

func start_server() -> Error:
	var port := EnvConfig.number("WORLD_PORT", DEFAULT_PORT)
	var peer := WebSocketMultiplayerPeer.new()
	# Chunk payloads are ~10-20 KiB compressed; the default 64 KiB inbound
	# buffer is fine, but give outbound plenty of headroom for join bursts
	# (a new machine asks for ~150 chunks at once).
	peer.outbound_buffer_size = 4 * 1024 * 1024
	peer.inbound_buffer_size = 256 * 1024
	var err := peer.create_server(port)
	if err != OK:
		push_error("Failed to listen on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("BattleBox server listening on ws://0.0.0.0:%d" % port)
	return OK

func connect_to(url: String) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	peer.outbound_buffer_size = 256 * 1024
	peer.inbound_buffer_size = 4 * 1024 * 1024
	var err := peer.create_client(url)
	if err != OK:
		push_error("Failed to start connection to %s: %s" % [url, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	return OK

## Drop the link on purpose — the world menu pointing this client at a
## different server. main.gd's reconnect loop dials the new address.
func disconnect_now() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	server_disconnected.emit()

func go_offline() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

## In a browser the address is NOT ours to choose: go back to whatever
## origin served the page, on /ws. Same scheme, host and port as the page.
##
## A page served over https cannot open a plain ws:// socket at all — the
## browser blocks it as mixed content, with no prompt and nothing to click,
## so the game would sit on "Finding the world…" forever. Deriving it from
## the page is also what makes a preview deployment or a LAN copy work with
## no rebuild: the build never names a host.
##
## Native clients have no page to inherit from, so they get the public
## world. WORLD_SERVER_URL overrides it for a LAN or dev server.
## The lobby's HTTP API for whichever server this client is pointed at.
##
## Derived from the socket URL rather than configured, so the browser
## build, a LAN box and battlebox.games all work with no build-time
## setting — the same reasoning as default_server_url() below, and the
## same failure if it were not: a preview deployment would talk to the
## live lobby and list games nobody there can join.
func lobby_base() -> String:
	if OS.has_feature("web"):
		var origin := str(JavaScriptBridge.eval("window.location.origin", true))
		if not origin.is_empty() and origin != "null":
			return origin
	# Same host and port as the game socket, always — because the lobby is
	# what SERVES that socket. It proxies /ws through to whichever room
	# was asked for, so if a client can reach the socket it can reach the
	# API, on battlebox.games and on a laptop alike.
	var url := default_server_url()
	var secure := url.begins_with("wss://")
	var host_port := url.replace("wss://", "").replace("ws://", "").split("/")[0]
	return "%s://%s" % ["https" if secure else "http", host_port]

## The game socket for one room. The room travels as a query parameter
## rather than a path segment so the whole thing still arrives at /ws, and
## nginx needs one location for the socket rather than one per room.
static func room_socket(base_url: String, code: String) -> String:
	var trimmed := code.strip_edges().to_lower()
	if trimmed.is_empty():
		return base_url
	var joiner := "&" if base_url.contains("?") else "?"
	return "%s%sroom=%s" % [base_url, joiner, trimmed.uri_encode()]

func default_server_url() -> String:
	if OS.has_feature("web"):
		var host := str(JavaScriptBridge.eval("window.location.host", true))
		if not host.is_empty():
			var secure := str(JavaScriptBridge.eval(
				"window.location.protocol", true)) == "https:"
			return "%s://%s/ws" % ["wss" if secure else "ws", host]
	return EnvConfig.text("WORLD_SERVER_URL", PUBLIC_SERVER_URL)

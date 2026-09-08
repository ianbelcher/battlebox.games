class_name ChunkFeed
extends RefCounted
## THE SERVER'S SIDE OF CHUNK STREAMING: what each client has asked for,
## sent a little at a time, and the slab made ready before anybody asks.
##
## Beside world.gd rather than in it, because world.gd is the wire
## protocol and is at the size ceiling the style test enforces. The one
## RPC involved (sv_request_chunks) stays there and hands its list here.

var world: Node = null
## peer -> Array[Vector2i], in the order asked.
var queues: Dictionary = {}

## BUDGETED IN TIME, NOT IN CHUNKS. It was six a frame per peer, and a
## chunk nobody had asked for yet was generated right there — so six of
## them was seventy milliseconds and the frame with them, for every frame
## of every client's first minute. The store now generates the slab ahead
## of time (warm) and keeps each chunk's wire form, so the usual cost is a
## dictionary hit and a send; the clock is for the chunk that was not
## ready, which still costs what it costs but no longer costs it six
## times in one frame.
const SEND_BUDGET_USEC := 3000
const SEND_PER_PEER := 12

func _init(p_world: Node) -> void:
	world = p_world

func enqueue(peer: int, list: Array) -> void:
	var queue: Array = queues.get(peer, [])
	for item in list:
		if item is Vector2i and queue.size() < 400:
			queue.append(item)
	queues[peer] = queue

## Sending is spread over frames so a join burst (~90 chunks) doesn't stall
## the server or overflow the socket buffer.
func drain() -> void:
	var stop := Time.get_ticks_usec() + SEND_BUDGET_USEC
	for peer: int in queues.keys():
		if not (peer in world.multiplayer.get_peers()):
			queues.erase(peer)
			continue
		var queue: Array = queues[peer]
		var batch: Array = []
		while batch.size() < SEND_PER_PEER and not queue.is_empty() \
				and Time.get_ticks_usec() < stop:
			var cpos: Vector2i = queue.pop_front()
			batch.append([cpos.x, cpos.y, world.store.get_chunk_compressed(cpos)])
		if batch.size() == 1:
			world.cl_chunk.rpc_id(peer, batch[0][0], batch[0][1], batch[0][2])
		elif not batch.is_empty():
			world.cl_chunk_batch.rpc_id(peer, batch)
		if queue.is_empty():
			queues.erase(peer)

## The terrain, made before anybody needs it. See ChunkStore.warm: a
## room with nobody in it spends real time on it and is done in seconds;
## a room with people in it takes a sliver a frame, which is still far
## less than the frame used to lose generating chunks for whoever walked
## somewhere new.
var _warm_left := -1

func warm() -> void:
	if _warm_left == 0:
		return
	var busy: bool = world.battle.people_present()
	_warm_left = world.store.warm(2500 if busy else 12000)
	if _warm_left == 0:
		print("World: %d chunks generated and packed ahead of time"
			% world.store.cached_count())

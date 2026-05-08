extends Node

var server = TCPServer.new()
var peer : StreamPeerTCP = null

func _ready():
	server.listen(6006)
	print("[voice] Listening on port 6006")

func _process(_delta):
	if peer == null or peer.get_status() == StreamPeerTCP.STATUS_NONE:
		if server.is_connection_available():
			peer = server.take_connection()
			print("[voice] Browser connected")

	if peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var available = peer.get_available_bytes()
		if available > 0:
			var data = peer.get_string(available)
			_on_data_received(data)

func _on_data_received(data: String):
	var parsed = JSON.parse_string(data)
	if parsed == null:
		return
	print("Received: ", parsed["phrase"])
	# GameManager.handle_voice_command(parsed["phrase"])  ← not ready yet

import socket
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import json

GODOT_HOST = "127.0.0.1"
GODOT_PORT = 6006

godot_sock = None

def connect_to_godot():
    global godot_sock
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((GODOT_HOST, GODOT_PORT))
    godot_sock = s
    print("[relay] Connected to Godot")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if parsed.path == "/phrase" and "text" in params:
            phrase  = params["text"][0]
            payload = json.dumps({"phrase": phrase}) + "\n"
            try:
                godot_sock.sendall(payload.encode("utf-8"))
                print(f"[relay] Sent to Godot: {phrase}")
            except Exception as e:
                print(f"[relay] Error sending: {e}")

        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

    def log_message(self, format, *args):
        pass  # suppress access logs

print("[relay] Connecting to Godot...")
connect_to_godot()
print("[relay] HTTP server on port 6007")
HTTPServer(("127.0.0.1", 6007), Handler).serve_forever()
# Answers one WebSocket client, then sends one binary message after the app has gone idle.
import base64, hashlib, socket, sys, time

port, size, idle = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
listener = socket.create_server(("127.0.0.1", port))
client, _ = listener.accept()
request = b""
while b"\r\n\r\n" not in request:
    request += client.recv(4096)
key = next(l.split(b":", 1)[1].strip() for l in request.split(b"\r\n") if l.lower().startswith(b"sec-websocket-key:"))
accept = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
time.sleep(idle)
client.sendall(bytes([0x82, 127]) + size.to_bytes(8, "big") + b"x" * size)
print(f"server sent {size} bytes", flush=True)
time.sleep(60)

"""Serve build/stadium/serve to Roblox Studio on 127.0.0.1:48901 (localhost only, nothing leaves the PC).

    python tools/stadium/serve.py build/stadium/serve
"""
import functools
import http.server
import socketserver
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/stadium/serve").resolve()
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", 48901), handler) as httpd:
    print(f"serving {root} on http://127.0.0.1:48901/", flush=True)
    httpd.serve_forever()

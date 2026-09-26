import json
import os
import socket
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


ALLOWED_ORIGINS = {
    "http://ops-atlas",
    "http://ops-atlas.tail5739b8.ts.net",
    "http://ops-atlas-aws:8080",
    "http://localhost:8083",
}


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/status":
            status = {
                "app": "Ops Atlas",
                "target": os.getenv("DEPLOYMENT_TARGET", "local-docker"),
                "version": os.getenv("APP_VERSION", "dev"),
                "hostname": socket.gethostname(),
                "time_utc": datetime.now(timezone.utc).isoformat(),
            }
            body = json.dumps(status).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            origin = self.headers.get("Origin")
            if origin in ALLOWED_ORIGINS:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")
            self.end_headers()
            self.wfile.write(body)
            return

        super().do_GET()


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print("Ops Atlas listening on port 8080", flush=True)
    server.serve_forever()

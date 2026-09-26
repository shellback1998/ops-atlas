import json
import os
import socket
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


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
            self.end_headers()
            self.wfile.write(body)
            return

        super().do_GET()


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print("Ops Atlas listening on port 8080", flush=True)
    server.serve_forever()

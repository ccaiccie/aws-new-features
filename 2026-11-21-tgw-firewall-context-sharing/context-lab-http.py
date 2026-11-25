"""Serve the same synthetic response on all three lab ports."""
import argparse
from contextlib import ExitStack
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"context-lab: probe reached the private server\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    args = parser.parse_args()
    with ExitStack() as stack:
        servers = [
            stack.enter_context(ThreadingHTTPServer((args.bind, port), Handler))
            for port in (8080, 8081, 8082)
        ]
        for server in servers[1:]:
            Thread(target=server.serve_forever, daemon=True).start()
        servers[0].serve_forever()


if __name__ == "__main__":
    main()

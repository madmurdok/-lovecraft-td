#!/usr/bin/env python3
"""Serves build/web on http://localhost:<port>/ (default 8060). Ctrl+C to stop.

Sends COOP/COEP headers (harmless for the single-threaded export, required if
thread support is ever turned on) and application/wasm for .wasm.
"""
import functools
import http.server
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "build" / "web"


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
    if not (ROOT / "index.html").exists():
        sys.exit(f"{ROOT}/index.html not found: run scripts/export-web.sh first")
    handler = functools.partial(Handler, directory=str(ROOT))
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as srv:
        print(f"Serving {ROOT} at http://localhost:{port}/", flush=True)
        try:
            srv.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()

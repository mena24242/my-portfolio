#!/usr/bin/env python3
"""
Portfolio server — serves the site AND persists dashboard edits.

Endpoints:
  GET  /api/ping   -> {"ok": true}
  GET  /api/load   -> current saved content (content.json) or {}
  POST /api/save   -> body: JSON content -> saves content.json and bakes
                      the content directly into index.html

This is what makes dashboard edits actually change the site file.
"""
import json
import os
import re
from http.server import SimpleHTTPRequestHandler, HTTPServer

PORT = 8080
DIR = os.path.dirname(os.path.abspath(__file__))
CONTENT_FILE = os.path.join(DIR, "content.json")
INDEX_FILE = os.path.join(DIR, "index.html")

BAKE_RE = re.compile(r"window\.__BAKED_CONTENT__\s*=\s*[^;]*;")


def bake(data):
    """Write the content into index.html in place of the marker line."""
    with open(INDEX_FILE, "r", encoding="utf-8") as f:
        html = f.read()
    # escape '<' so the JSON can never break out of the <script> tag
    baked = json.dumps(data, ensure_ascii=False).replace("<", "\\u003c")
    new_line = "window.__BAKED_CONTENT__ = " + baked + ";"
    if BAKE_RE.search(html):
        html = BAKE_RE.sub(new_line, html, count=1)
    else:
        html = html.replace("const STORE_KEY", new_line + "\nconst STORE_KEY", 1)
    with open(INDEX_FILE, "w", encoding="utf-8") as f:
        f.write(html)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIR, **kwargs)

    def end_headers(self):
        # avoid stale browser cache after edits
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/ping":
            self._json({"ok": True})
            return
        if self.path == "/api/load":
            if os.path.exists(CONTENT_FILE):
                try:
                    with open(CONTENT_FILE, "r", encoding="utf-8") as f:
                        self._json(json.load(f))
                    return
                except Exception:
                    pass
            self._json({})
            return
        super().do_GET()

    def do_POST(self):
        if self.path == "/api/save":
            try:
                length = int(self.headers.get("Content-Length", 0) or 0)
                raw = self.rfile.read(length) if length else b""
                data = json.loads(raw.decode("utf-8"))
                with open(CONTENT_FILE, "w", encoding="utf-8") as f:
                    json.dump(data, f, ensure_ascii=False)
                bake(data)
                self._json({"ok": True})
            except Exception as e:
                self._json({"ok": False, "error": str(e)}, 500)
            return
        self._json({"ok": False, "error": "not found"}, 404)


def main():
    print("Portfolio server running on http://0.0.0.0:%d" % PORT)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()

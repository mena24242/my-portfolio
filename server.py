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

MARKER = "window.__BAKED_CONTENT__"


def find_baked(html):
    """Locate the baked JSON object.

    Scan braces instead of using a regex: project code stored inside the JSON
    contains ';' characters, and a regex stopping at the first one truncates the
    content and leaves dead junk behind on the same line.
    """
    i = html.find(MARKER)
    if i < 0:
        return None
    s = html.find("{", i)
    if s < 0:
        return None
    depth = 0
    in_str = False
    quote = ""
    esc = False
    for k in range(s, len(html)):
        c = html[k]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == quote:
                in_str = False
            continue
        if c in ('"', "'"):
            in_str = True
            quote = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return (i, s, k + 1)
    return None


def bake_into(html, line):
    spot = find_baked(html)
    if not spot:
        return html.replace("const STORE_KEY", line + "\nconst STORE_KEY", 1)
    start, _open, end = spot
    after = end + 1 if end < len(html) and html[end] == ";" else end
    nl = html.find("\n", after)
    rest = html[after:] if nl == -1 else html[after:nl]
    if rest.strip():                     # drop leftover junk sitting on that line
        after = len(html) if nl == -1 else nl
    return html[:start] + line + html[after:]


def bake(data):
    """Write the content into index.html in place of the marker line."""
    with open(INDEX_FILE, "r", encoding="utf-8") as f:
        html = f.read()
    baked = json.dumps(data, ensure_ascii=False).replace("<", "\\u003c")
    new_line = "window.__BAKED_CONTENT__ = " + baked + ";"
    html = bake_into(html, new_line)
    with open(INDEX_FILE, "w", encoding="utf-8") as f:
        f.write(html)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIR, **kwargs)

    def end_headers(self):
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

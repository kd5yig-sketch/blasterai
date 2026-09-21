#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Serve a Markdown file as a styled page, re-rendered on every request.

    python3 tools/preview/serve_doc.py docs/porting.md [--port 8765]

Why this exists: reviewing a long document in a terminal is miserable, and
committing a doc to see it rendered on GitHub is a slow loop. This renders on
GET, so editing the file and hitting refresh is the whole cycle. It is a review
aid and is never part of a build.
"""

import argparse
import html
import http.server
import pathlib
import sys

import markdown

CSS = """
:root { --ink:#16202b; --muted:#5b6672; --rule:#e3e8ee; --accent:#2a9d8f; --bg:#fff; --code-bg:#f4f6f8 }
@media (prefers-color-scheme: dark) {
  :root { --ink:#e7eef7; --muted:#9aa7b4; --rule:#2a3540; --accent:#4fd1c5; --bg:#11181f; --code-bg:#1b242d }
}
* { box-sizing:border-box }
body { margin:0; background:var(--bg); color:var(--ink);
       font:16px/1.65 -apple-system,BlinkMacSystemFont,"Inter",system-ui,sans-serif }
main { max-width:760px; margin:0 auto; padding:3rem 24px 6rem }
h1 { font-size:2.1rem; line-height:1.2; margin:0 0 .6rem }
h2 { font-size:1.45rem; margin:2.6rem 0 .8rem; padding-top:1.4rem; border-top:1px solid var(--rule) }
h3 { font-size:1.12rem; margin:1.8rem 0 .5rem }
a { color:var(--accent) }
code { background:var(--code-bg); padding:.12em .35em; border-radius:4px; font-size:.9em }
pre { background:var(--code-bg); padding:1rem; border-radius:8px; overflow-x:auto }
pre code { background:none; padding:0 }
blockquote { margin:1.4rem 0; padding:.6rem 1.1rem; border-left:3px solid var(--accent);
             background:var(--code-bg); border-radius:0 6px 6px 0 }
table { width:100%; border-collapse:collapse; margin:1.4rem 0; font-size:.95rem }
th, td { text-align:left; padding:.55rem .7rem; border-bottom:1px solid var(--rule); vertical-align:top }
th { font-weight:650 }
hr { border:0; border-top:1px solid var(--rule); margin:2.4rem 0 }
.meta { color:var(--muted); font-size:.85rem; margin-bottom:2.4rem }
"""

PAGE = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><style>{css}</style></head>
<body><main><p class="meta">{path} &mdash; rendered live, refresh to pick up edits</p>
{body}</main></body></html>"""


def build_handler(doc: pathlib.Path):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if not doc.exists():
                self.send_error(404, f"{doc} does not exist yet")
                return
            body = markdown.markdown(
                doc.read_text(),
                extensions=["extra", "toc", "sane_lists", "admonition"],
            )
            page = PAGE.format(
                title=html.escape(doc.name),
                css=CSS,
                path=html.escape(str(doc)),
                body=body,
            )
            raw = page.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)

        def log_message(self, *args):
            pass                      # the terminal is for the agent, not access logs

    return Handler


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("doc", type=pathlib.Path)
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    srv = http.server.HTTPServer(("127.0.0.1", a.port), build_handler(a.doc))
    print(f"serving {a.doc} at http://localhost:{a.port}/", flush=True)
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())

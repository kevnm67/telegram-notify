#!/usr/bin/env python3
"""Minimal Telegram Bot API double for integration tests.

Accepts POST /bot<token>/sendMessage, appends the decoded form body as JSON
to the file named by MOCK_TELEGRAM_LOG (default /tmp/telegram-mock.jsonl) and
answers {"ok": true}. Everything else gets a 404.
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

LOG_PATH = os.environ.get("MOCK_TELEGRAM_LOG", "/tmp/telegram-mock.jsonl")
PORT = int(os.environ.get("MOCK_TELEGRAM_PORT", "8089"))


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 - http.server API
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        method = self.path.rsplit("/", 1)[-1]
        if not (
            self.path.startswith("/bot") and method in ("sendMessage", "sendDocument")
        ):
            self._reply(404, {"ok": False, "description": "Not Found"})
            return
        if method == "sendDocument":
            # multipart upload: record the method and the filename only
            fname = ""
            for line in body.splitlines():
                if "filename=" in line:
                    fname = line.split("filename=")[-1].strip().strip('"')
            fields = {"method": "sendDocument", "filename": fname, "bytes": len(body)}
        else:
            fields = {
                k: v[0] for k, v in parse_qs(body, keep_blank_values=True).items()
            }
            fields["method"] = "sendMessage"
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(fields) + "\n")
        self._reply(200, {"ok": True, "result": {"message_id": 1}})

    def _reply(self, code, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):  # keep CI logs quiet
        sys.stderr.write("[mock-telegram] %s\n" % (fmt % args))


if __name__ == "__main__":
    open(LOG_PATH, "a", encoding="utf-8").close()
    print(f"[mock-telegram] listening on :{PORT}, logging to {LOG_PATH}", flush=True)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

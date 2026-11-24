# Tiny OpenAI-compatible stub for tests (no real key needed). Streams SSE when asked.
import json, socket, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPLY = '{"title":"Stub document","description":"A test document.","tags":["test","stub"]}'

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"): return self._json(200, {"data": [{"id": "stub-model", "object": "model"}]})
        self._json(200, {"ok": True})
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0); req = json.loads(self.rfile.read(n) or b"{}")
        auth = self.headers.get("Authorization", "")
        print("POST", self.path, "auth" if auth.startswith("Bearer ") else "NOAUTH", "stream" if req.get("stream") else "", flush=True)
        prompt = json.dumps(req.get("messages", [])).lower()
        text = REPLY if (req.get("response_format") or "json" in prompt) else "Hello from the stub model."
        if req.get("stream"):
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
            for part in [text[:10], text[10:]]:
                ch = {"id": "c1", "object": "chat.completion.chunk", "created": int(time.time()), "model": "stub-model",
                      "choices": [{"index": 0, "delta": {"role": "assistant", "content": part}, "finish_reason": None}]}
                self.wfile.write(f"data: {json.dumps(ch)}\n\n".encode()); self.wfile.flush()
            end = {"id": "c1", "object": "chat.completion.chunk", "created": int(time.time()), "model": "stub-model",
                   "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
            self.wfile.write(f"data: {json.dumps(end)}\n\ndata: [DONE]\n\n".encode()); return
        self._json(200, {"id": "c1", "object": "chat.completion", "created": int(time.time()), "model": "stub-model",
                         "choices": [{"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}],
                         "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20}})

class S(ThreadingHTTPServer):
    address_family = socket.AF_INET6
    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0); super().server_bind()

import os
S(("::", int(os.environ.get("PORT", "8000"))), H).serve_forever()

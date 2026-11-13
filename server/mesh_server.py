#!/usr/bin/env python3
"""AuctionMesh central price server (Python standard library only).

Stores the latest price per (realm, item key) with the same last-writer-wins
rule the addon uses, so the server and every client always agree.

Endpoints (all need header  X-Mesh-Token: <token>):
  POST /v1/push   body: "<realm>\\n<key:price:qty:time;...>"   (gzip allowed)
                  -> {"accepted": n, "serverTime": t}
  GET  /v1/pull?realm=<realm>&since=<time>
                  -> "key:price:qty:time;..."  (gzip if the client accepts it)
  GET  /v1/health

Run:  MESH_TOKEN=secret python3 server/mesh_server.py --port 8787 --db mesh.sqlite
Put it behind HTTPS (Caddy/nginx) if it is reachable from the internet.
"""
from __future__ import annotations

import argparse
import gzip
import hmac
import json
import os
import re
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

MAX_AGE = 72 * 3600
MAX_BODY = 32 * 1024 * 1024
REC = re.compile(rb"(-?\d+):(\d+):(\d+):(\d+)")

SCHEMA = """
CREATE TABLE IF NOT EXISTS prices (
    realm TEXT NOT NULL, key INTEGER NOT NULL,
    p INTEGER NOT NULL, q INTEGER NOT NULL, t INTEGER NOT NULL,
    PRIMARY KEY (realm, key)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS prices_realm_t ON prices(realm, t);
"""

# Same conflict rule as AuctionMesh/Store.lua: newer t wins; equal t -> lower
# price wins; equal t and price -> larger quantity wins.
UPSERT = """
INSERT INTO prices(realm, key, p, q, t) VALUES (?, ?, ?, ?, ?)
ON CONFLICT(realm, key) DO UPDATE SET p = excluded.p, q = excluded.q, t = excluded.t
WHERE excluded.t > prices.t
   OR (excluded.t = prices.t AND (excluded.p < prices.p
       OR (excluded.p = prices.p AND excluded.q > prices.q)))
"""


class Store:
    def __init__(self, path: str):
        self.path = path
        self.local = threading.local()
        self.write_lock = threading.Lock()
        with self.conn() as c:
            c.executescript(SCHEMA)

    def conn(self) -> sqlite3.Connection:
        c = getattr(self.local, "c", None)
        if c is None:
            c = sqlite3.connect(self.path, timeout=30, isolation_level=None)
            c.execute("PRAGMA journal_mode=WAL")
            c.execute("PRAGMA synchronous=NORMAL")
            c.execute("PRAGMA temp_store=MEMORY")
            self.local.c = c
        return c

    def push(self, realm: str, payload: bytes) -> int:
        now = int(time.time())
        rows = []
        for m in REC.finditer(payload):
            k, p, q, t = (int(x) for x in m.groups())
            if k != 0 and 0 < p < 10**13 and 0 <= q < 10**7 and now - MAX_AGE <= t <= now + 300:
                rows.append((realm, k, p, q, t))
        if rows:
            c = self.conn()
            with self.write_lock:
                c.execute("BEGIN")
                c.executemany(UPSERT, rows)
                c.execute("COMMIT")
        return len(rows)

    def pull(self, realm: str, since: int) -> bytes:
        since = max(since, int(time.time()) - MAX_AGE)
        cur = self.conn().execute(
            "SELECT key, p, q, t FROM prices WHERE realm = ? AND t > ?", (realm, since))
        return ";".join(f"{k}:{p}:{q}:{t}" for k, p, q, t in cur).encode()

    def prune(self) -> None:
        c = self.conn()
        with self.write_lock:
            c.execute("DELETE FROM prices WHERE t < ?", (int(time.time()) - MAX_AGE,))


def make_handler(store: Store, token: str):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):  # keep the console quiet
            pass

        def _authed(self) -> bool:
            if hmac.compare_digest(self.headers.get("X-Mesh-Token", ""), token):
                return True
            self._send(401, b"unauthorized", "text/plain")
            return False

        def _send(self, code: int, body: bytes, ctype: str) -> None:
            if len(body) > 1024 and "gzip" in self.headers.get("Accept-Encoding", ""):
                body = gzip.compress(body, 5)
                self.send_response(code)
                self.send_header("Content-Encoding", "gzip")
            else:
                self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            url = urlparse(self.path)
            if url.path == "/v1/health":
                return self._send(200, b'{"ok":true}', "application/json")
            if not self._authed():
                return
            if url.path == "/v1/pull":
                qs = parse_qs(url.query)
                realm = qs.get("realm", [""])[0]
                since = int(qs.get("since", ["0"])[0] or 0)
                if not realm:
                    return self._send(400, b"realm required", "text/plain")
                return self._send(200, store.pull(realm, since), "text/plain")
            self._send(404, b"not found", "text/plain")

        def do_POST(self):
            if urlparse(self.path).path != "/v1/push":
                return self._send(404, b"not found", "text/plain")
            if not self._authed():
                return
            n = int(self.headers.get("Content-Length", "0"))
            if n <= 0 or n > MAX_BODY:
                return self._send(413, b"bad length", "text/plain")
            body = self.rfile.read(n)
            if self.headers.get("Content-Encoding") == "gzip":
                body = gzip.decompress(body)
            realm, _, payload = body.partition(b"\n")
            realm = realm.decode("utf-8", "replace").strip()
            if not realm:
                return self._send(400, b"realm required", "text/plain")
            accepted = store.push(realm, payload)
            out = json.dumps({"accepted": accepted, "serverTime": int(time.time())}).encode()
            self._send(200, out, "application/json")

    return Handler


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--db", default="mesh.sqlite")
    args = ap.parse_args()
    token = os.environ.get("MESH_TOKEN")
    if not token:
        raise SystemExit("Set MESH_TOKEN to a shared secret first.")
    store = Store(args.db)

    def pruner():
        while True:
            time.sleep(3600)
            store.prune()

    threading.Thread(target=pruner, daemon=True).start()
    srv = ThreadingHTTPServer((args.host, args.port), make_handler(store, token))
    print(f"AuctionMesh server on {args.host}:{args.port} (db={args.db})")
    srv.serve_forever()


if __name__ == "__main__":
    main()

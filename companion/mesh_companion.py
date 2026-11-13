#!/usr/bin/env python3
"""AuctionMesh companion: bridges the in-game mesh and the central server.

WoW addons cannot make network calls. They can only write SavedVariables
(flushed on /reload, logout or exit) and read their own files at load time.
This tool:
  1. watches  WTF/Account/<ACCOUNT>/SavedVariables/AuctionMesh.lua
  2. uploads new prices the addon exported for each realm  -> POST /v1/push
  3. downloads everything the server has newer than last time -> GET /v1/pull
  4. writes  Interface/AddOns/AuctionMesh/Seed.lua, which the addon merges
     on the next login or /reload

Usage:
  python3 mesh_companion.py --wow "C:/Program Files (x86)/World of Warcraft/_forever_" \\
      --account MYACCOUNT --server https://mesh.example.com --token secret [--watch]
"""
from __future__ import annotations

import argparse
import gzip
import json
import re
import time
import urllib.request
from pathlib import Path

EXPORT_BLOCK = re.compile(r'\["export"\]\s*=\s*\{(.*?)\n\s*\}', re.S)
EXPORT_ENTRY = re.compile(r'\["((?:[^"\\]|\\.)*)"\]\s*=\s*"([-0-9:;]*)"')
SEED_ENTRY = re.compile(r'\["((?:[^"\\]|\\.)*)"\]\s*=\s*(\d+)')
SEED_REALM = re.compile(r'\["((?:[^"\\]|\\.)*)"\]\s*=\s*"([-0-9:;]*)"')


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def read_exports(saved: Path) -> dict[str, str]:
    if not saved.exists():
        return {}
    text = saved.read_text(encoding="utf-8", errors="replace")
    m = EXPORT_BLOCK.search(text)
    if not m:
        return {}
    return {realm: data for realm, data in EXPORT_ENTRY.findall(m.group(1)) if data}


def read_seed_acks(seed: Path) -> dict[str, int]:
    if not seed.exists():
        return {}
    text = seed.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"ack\s*=\s*\{(.*?)\}", text, re.S)
    return {r: int(t) for r, t in SEED_ENTRY.findall(m.group(1))} if m else {}


def request(server: str, token: str, path: str, body: bytes | None = None) -> bytes:
    headers = {"X-Mesh-Token": token, "Accept-Encoding": "gzip"}
    if body is not None:
        body = gzip.compress(body, 5)
        headers["Content-Encoding"] = "gzip"
        headers["Content-Type"] = "text/plain"
    req = urllib.request.Request(server.rstrip("/") + path, data=body, headers=headers,
                                 method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
        if r.headers.get("Content-Encoding") == "gzip":
            data = gzip.decompress(data)
        return data


def write_seed(seed: Path, acks: dict[str, int], realms: dict[str, str]) -> None:
    lines = ["-- Written by mesh_companion.py. Do not edit.", "AuctionMesh_Seed = {", "  ack = {"]
    lines += [f"    [{lua_str(r)}] = {t}," for r, t in sorted(acks.items())]
    lines += ["  },", "  realms = {"]
    lines += [f"    [{lua_str(r)}] = {lua_str(d)}," for r, d in sorted(realms.items())]
    lines += ["  },", "}", ""]
    tmp = seed.with_suffix(".tmp")
    tmp.write_text("\n".join(lines), encoding="utf-8")
    tmp.replace(seed)


def sync_once(saved: Path, seed: Path, server: str, token: str, realms_extra: list[str]) -> None:
    exports = read_exports(saved)
    acks = read_seed_acks(seed)
    realms = set(exports) | set(acks) | set(realms_extra)
    pulled: dict[str, str] = {}
    for realm in sorted(realms):
        data = exports.get(realm, "")
        if data:
            res = json.loads(request(server, token, "/v1/push", (realm + "\n" + data).encode()))
            print(f"[{realm}] uploaded {res['accepted']} prices")
        # Pull the full fresh window (server keeps 72h); the addon dedupes on merge.
        body = request(server, token, f"/v1/pull?realm={urllib.request.quote(realm)}&since=0")
        pulled[realm] = body.decode()
        acks[realm] = int(time.time())
        n = pulled[realm].count(";") + 1 if pulled[realm] else 0
        print(f"[{realm}] downloaded {n} prices -> Seed.lua")
    if realms:
        write_seed(seed, acks, pulled)


def main() -> None:
    ap = argparse.ArgumentParser(description="AuctionMesh companion")
    ap.add_argument("--wow", required=True, help="WoW install folder for this game version (contains WTF and Interface)")
    ap.add_argument("--account", required=True, help="Folder name under WTF/Account")
    ap.add_argument("--server", required=True)
    ap.add_argument("--token", required=True)
    ap.add_argument("--realm", action="append", default=[], help="Also pull this realm even before first export")
    ap.add_argument("--watch", action="store_true", help="Keep running; sync whenever SavedVariables change")
    ap.add_argument("--interval", type=float, default=60, help="Seconds between refreshes in watch mode")
    a = ap.parse_args()

    root = Path(a.wow)
    saved = root / "WTF" / "Account" / a.account / "SavedVariables" / "AuctionMesh.lua"
    seed = root / "Interface" / "AddOns" / "AuctionMesh" / "Seed.lua"
    if not seed.parent.exists():
        raise SystemExit(f"Addon folder not found: {seed.parent}")

    last_mtime, last_run = 0.0, 0.0
    while True:
        mtime = saved.stat().st_mtime if saved.exists() else 0.0
        if mtime != last_mtime or time.time() - last_run >= a.interval:
            try:
                sync_once(saved, seed, a.server, a.token, a.realm)
            except Exception as e:  # keep watching through network hiccups
                print("sync failed:", e)
            last_mtime, last_run = mtime, time.time()
        if not a.watch:
            break
        time.sleep(2)


if __name__ == "__main__":
    main()

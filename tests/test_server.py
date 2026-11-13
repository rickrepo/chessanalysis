"""Round trip: addon export -> companion -> server -> Seed.lua -> loadable by Lua.
Run: python3 tests/test_server.py"""
import subprocess, sys, tempfile, threading, time
from http.server import ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "server"), str(ROOT / "companion")]
import mesh_server, mesh_companion  # noqa: E402

now = int(time.time())
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    store = mesh_server.Store(str(d / "mesh.sqlite"))
    srv = ThreadingHTTPServer(("127.0.0.1", 0), mesh_server.make_handler(store, "tok"))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_address[1]}"

    wow = d / "wow"
    sv = wow / "WTF/Account/ACC/SavedVariables/AuctionMesh.lua"
    seed = wow / "Interface/AddOns/AuctionMesh/Seed.lua"
    sv.parent.mkdir(parents=True); seed.parent.mkdir(parents=True)

    # Two players on the same realm export overlapping data.
    sv.write_text(f'AuctionMeshDB = {{\n["export"] = {{\n["Stormrage"] = "2589:1500:200:{now-60};-1234:990000:1:{now-30}",\n}},\n}}\n')
    mesh_companion.sync_once(sv, seed, url, "tok", [])
    # second player: newer price for 2589, older (losing) price for -1234, old junk record
    sv.write_text(f'AuctionMeshDB = {{\n["export"] = {{\n["Stormrage"] = "2589:1400:180:{now-10};-1234:5:1:{now-500};7:1:1:{now-999999}",\n}},\n}}\n')
    mesh_companion.sync_once(sv, seed, url, "tok", [])

    pulled = store.pull("Stormrage", 0).decode()
    recs = {int(r.split(":")[0]): r for r in pulled.split(";")}
    assert recs[2589] == f"2589:1400:180:{now-10}", recs        # newer wins
    assert recs[-1234] == f"-1234:990000:1:{now-30}", recs      # older loses
    assert 7 not in recs, recs                                  # expired rejected

    lua = f'dofile("{seed}"); local s = AuctionMesh_Seed.realms.Stormrage; local n = 0 ' \
          'for k,p,q,t in s:gmatch("(%-?%d+):(%d+):(%d+):(%d+)") do n = n + 1 end ' \
          'assert(n == 2, n); assert(AuctionMesh_Seed.ack.Stormrage > 0); print("seed ok", n)'
    out = subprocess.run(["lua5.1", "-e", lua], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    print(out.stdout.strip())

    import urllib.request, urllib.error
    try:
        urllib.request.urlopen(url + "/v1/pull?realm=Stormrage")
        raise AssertionError("expected 401")
    except urllib.error.HTTPError as e:
        assert e.code == 401
    srv.shutdown()
print("server/companion round trip: all checks passed")

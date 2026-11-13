# AuctionMesh

AuctionMesh is a WoW Forever addon (Midnight retail client, interface 16001) that lets a group of friends share auction house prices in real time and split the scanning work between them. It also includes a simple **sniper** that lists only the deals you can afford right now.

## The sniper (start here)

Open the auction house and the **Snipes** window appears next to it. Each row is one deal:

```
[icon] Linen Cloth     VENDOR 12x @3c > 5c   +24c   [Buy]
[icon] Copper Ore      FLIP   40x @20c > 79c  +22s   [Buy]
[icon] Peacebloom      FLIP    8x @15c > 60c   +2s   [Check]
```

* **VENDOR** means the item is listed for less than a vendor pays for it. Buy it, sell it to any NPC, and keep the difference. It's risk-free, has no 5% AH cut, and works on a brand-new realm with no price history. These deals are always listed first.
* **FLIP** means the cheapest listings are far below what the item really sells for. The resale price is the **lower** of two numbers: (a) the price once the cheap outliers are bought out, and (b) the item's moving average. On a new realm prices fall fast, so the lower number is the safer bet. Profit counts the 5% AH cut and a 1c undercut. The default bar is 30% profit.
* **Budget-aware:** only items you can afford with the gold in your bag are shown. The buy amount is capped at your gold, and the budget updates as you earn. That works fine starting from 32s.
* **Check** searches that item's listings to confirm the deal and work out exactly how many to buy. The sniper also checks affordable profession goods in the background, starting with the items that have the most listed (those resell fastest). Every price it confirms is shared with your friends, so they don't check the same items again.
* **Buy** works differently by item type. For stackable goods, **Buy** asks the server for the real total, then you click **Confirm**. If the price rose more than 2% in the meantime, the purchase is cancelled automatically. For gear, one click buys one listing.
* After you buy something, its tooltip says "sell to a vendor" or "post at X each".

Settings: `/amesh margin 30` (flip profit %), `/amesh minprofit 20` (minimum copper per deal), `/amesh snipe` (toggle the window).

Profession goods (trade goods, reagents, recipes, profession items) are the swarm's default focus, because that's where the money is on a new realm.

## What WoW lets addons do

| Question | Answer |
|---|---|
| Can an addon make HTTP or API calls to a server? | **No.** Addon Lua has no sockets and no HTTP. That's why there's a companion app (below). |
| Can addons talk to each other in game? | **Yes**, with hidden addon messages (`C_ChatInfo.SendAddonMessage`). Players never see them in chat. |
| With no limits? | **No.** Each message is at most 255 bytes, and the client throttles each prefix to a burst of about 10 messages, then about 1 per second. Sending too much can also disconnect you. |
| Is a chat channel the best route? | **Yes.** On a private custom channel, one send reaches every member at once. Whispers would need one send per friend. AuctionMesh joins a password-protected channel and hides it from your chat windows. Guild is the fallback. |
| How do we avoid the 15-minute full scan? | **Swarm scanning** (below). Normal category searches, split across everyone. |

Since bandwidth is the scarce resource, the protocol is built to save bytes:

* **Compact binary-in-text encoding.** About 16 to 20 price records fit in one 255-byte message (item, copper price, quantity and timestamp each take a few characters).
* **Only new information is sent.** A price is broadcast only if it's new, it changed, its quantity moved more than 25%, or our copy is more than 30 minutes old. If a friend already broadcast the same data, yours is dropped.
* **Priority lanes on two prefixes.** Control messages go first, then live prices, then bulk catch-up. Each prefix has its own throttle budget, so catch-up never delays live prices.
* **Hash-based catch-up.** When you log in, you send 32 bucket hashes in one message. Only friends whose buckets differ answer, and they split the differing buckets between them. Each one streams only the records newer than your last logout.

## Swarm scanning (the speed feature)

`/amesh swarm` while the AH is open:

1. The AH is split into about 100 work units, one per item class or subclass (Herbs, Ore, Cloth, Potions, Plate…).
2. Each friend claims the **stalest unclaimed** unit and browses it. One `SendBrowseQuery` returns the lowest price and listed quantity of every item in that category. When it's finished, the friend marks it done and the prices go out over the mesh.
3. Every player has their **own** query throttle, so the swarm scales with the number of people. Faster players automatically claim more units.
4. Units that anyone scanned in the last 5 minutes are skipped. When everything is fresh, the swarm waits, so you get a continuous rolling scan instead of one big scan every 15 minutes.
5. `/amesh focus herbs ore` gives you your own categories, which you'll always claim first. Shortcuts: `herbs ore cloth leather cooking elemental enchanting inscription jewelcrafting parts consumables armor weapons gems recipes pets`, or raw `classID[:subClassID]`.

Simulated speedup (100 categories, 1 query per second per player, 1 to 3 pages each): **1 player 212 s → 4 players 53 s → 8 players 29 s**, with no duplicated queries.

The optional `/amesh scan` (the 15-minute `ReplicateItems` full scan) is still available. When anyone runs one, it's announced to the group, so nobody else has to.

Passive capture is always on: every browse page, commodity search and item search you do by hand is shared too.

## The central database (companion app)

Because addons can't reach the internet, the central database is synced from **outside** the game:

```
 in game  ──(hidden addon channel, real time)──  in game
    │ SavedVariables (on /reload or logout)            ▲ Seed.lua (read at login or /reload)
    ▼                                                 │
 companion/mesh_companion.py  ──HTTPS──  server/mesh_server.py (SQLite)
```

Run the server once (Python 3.9+, no dependencies):

```bash
MESH_TOKEN=pick-a-secret python3 server/mesh_server.py --port 8787 --db mesh.sqlite
```

Each player runs the companion next to the game:

```bash
python3 companion/mesh_companion.py --wow "C:/Program Files (x86)/World of Warcraft/_forever_" --account YOURACCOUNT --server https://your-server:8787 --token pick-a-secret --watch
```

The server and every client use the same conflict rule: the newer timestamp wins; on equal timestamps, the lower price wins. That way everyone ends up with the same table. Put the server behind HTTPS if it's reachable from the internet.

## Install & use

1. Copy the `AuctionMesh` folder into `World of Warcraft/_forever_/Interface/AddOns/`. The folder name may differ on your install; it's the one Auctioneer lives in.
2. Everyone in the group runs the same command once: `/amesh channel <SecretName> <password>`. Or use `/amesh guild` to go over guild chat instead.
3. At the AH, run `/amesh swarm`. Price lines show up in item tooltips. `/amesh` on its own shows status and statistics.

Commands: `/amesh snipe | margin <pct> | minprofit <copper> | swarm | focus <types> | step | channel <name> [pw] | guild | scan [force] | sync | price <itemID|link>`

## Tests

```bash
lua5.1 tests/sim.lua          # protocol simulator + deal math (35 checks)
python3 tests/test_server.py  # companion ↔ server ↔ Seed.lua round trip
```

## Known limits / to verify in game

* **Not yet run in the real client.** The protocol logic is tested offline against stubbed WoW APIs. The AH calls follow the retail `C_AuctionHouse` API, which Auctioneer's Forever build also uses.
* If the client blocks automatic `SendBrowseQuery` (an `ADDON_ACTION_BLOCKED` message appears), the swarm switches to manual mode. Bind a key to `/amesh step`; each press scans one step.
* While the swarm runs, it uses the AH browse list, so don't browse by hand at the same time.
* The sniper never buys by itself. Every purchase is your click, which the game requires anyway. Check the numbers on expensive buys. The deposit to relist isn't included in profit; it's small and refunded on sale for most goods.
* Prices are stored per item ID, so different item levels of the same gear collapse into the cheapest one. Battle pets are stored per species.
* Midnight blocks addon messages in some instanced or combat situations. Sends are paused in combat and retried automatically.
* Anyone on the channel can send data, so only share the channel password with people you trust.

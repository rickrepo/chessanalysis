# AuctionMesh

AuctionMesh is a WoW Forever addon (Midnight retail client, interface 16001) that lets a group of friends share auction house prices in real time and split the scanning work between them. It also includes a simple **sniper** that lists only the deals you can afford right now.

## How to use it

Open the auction house. One window opens next to it and price scanning starts by itself. The window has two tabs.

```
 AuctionMesh                                   Gold: 32s00c
 [ BUY (2) ] [ SELL (3) ]
 Scanning prices: 34 of 100 categories done. Press Buy. What you see is exactly what you get.
 ---------------------------------------------------------------------------
 Copper Ore                                                          [ Buy ]
   SAFE  Buy 12 for 36c  >  vendor pays 60c  >  +24c
 Linen Cloth                                                         [ Buy ]
   FLIP  Buy 6 for 1s20c  >  resell at 77c each  >  +3s12c (not guaranteed)
```

### Where the panel lives

With the auction house open, the panel is **inside the auction house window**: it covers the content area, is exactly that window's size, and opens, moves and closes with it. An **AuctionMesh** tab under the window switches between the game's own screens and the panel; clicking any of the game's tabs also switches back. At a vendor or mailbox it appears as a compact separate window. `/amesh dock off` makes it a separate window everywhere.

### The look

The panel is assembled from the game's own interface pieces, so it takes on the game's look instead of bringing its own:

* the auction house's own background art, list stripes and row highlight;
* the game's tab style for BUY / PORTFOLIO / HISTORY, and a real tab after the auction house's own tabs for switching to AuctionMesh;
* the game's inset frame around the list and its gold column headings;
* the game's coin icons for every price;
* one line per row. The longer explanation ("Buy 6 for …, relist at …") is in the tooltip when you hover a row.

Each piece is checked before use. If this client doesn't have one, a plain fallback is drawn in its place.

### The layout

The window is laid out like a trading screen. The top strip shows **BALANCE**, **IN POSITIONS** (gold tied up in items you hold) and **OPEN P/L** (expected profit on them). Both tabs use the same columns:

```
 ITEM            BUY          MARKET   SPREAD   VOLUME    PROFIT
 Light Leather   4 @ 10c      30c      +190%    2857/h    +68c   [ Buy ]
   FLIP  Buy 4 for 40c, relist at 29c (750 listed at 30c+, sells in ~1 min)

 ITEM            QTY          COST     MARKET   STATUS    P / L
 Wool Cloth      1            34c      1s60c    READY     +1s18c [ Post ]
```

* **SPREAD** is the gap between what you pay and what you sell for.
* **VOLUME** is units sold per hour, measured by watching the listing. Vendor deals say "instant".
* On the PORTFOLIO tab, a `*` after MARKET means the price is the plan from when you bought; it becomes the live price once checked.

### Listed auctions and banked profit

* An auction you post stays on the PORTFOLIO tab as **LISTED** with its quantity, cost, your price and expected profit. It shows **UNDERCUT** when the latest sweep saw someone cheaper, and **SOLD?** when it is no longer among your auctions (collect the gold from the mailbox).
* **BANKED** in the top strip is profit actually made: vendor sales, plus auction sales once you collect the gold (sale price minus the auction house cut minus what you paid).

### HISTORY tab

Everything that happened to your gold and items, newest first: "Bought: 7 x … for 1s40c", "Collected from mailbox: 7 x … is now in your bags", "Posted 1x Wool Cloth at 1s60c", "Sold: …", and purchases that were cancelled. When the addon takes a purchase out of your mailbox it also says so in chat and at the top of the window.

### BUY tab

Only deals that were just checked against the live listings appear here, with the exact quantity and the exact total you'll pay. Nothing is shown from an estimate.

* **SAFE** means the item is listed for less than an NPC vendor pays. Buy it, sell it to any vendor, and keep the difference. This is guaranteed profit, with no AH cut and no deposit.
* **FLIP** means a few units are listed far below the real market. It has good odds but is not guaranteed, because someone still has to buy from you. A flip is only shown when **all** of these hold:
  1. It's a stackable good. Gear is never flipped, because item levels make prices incomparable.
  2. There's a real market price: at least 10 units, at 2 or more prices, within 25% of each other. One lonely expensive listing doesn't count.
  3. You buy **every** cheap unit, so none are left to undercut you. One exception for a small purse: if the whole cheap pile is at most 10% of the real market, you may buy the part you can afford (the row says how many cheap ones are left).
  4. The cheap units are at most half the size of the real market.
  5. It uses at most half your gold (all of it while you have under 1 gold).
  6. Profit is at least 20% after the 5% AH cut (`/amesh margin 30` changes it). The posting fee is kept aside, not subtracted, because it comes back on sale.
  10. **Volume.** The item must have been seen selling. The watch list re-reads each listing about once a minute; units that disappear from the cheap end between two readings were bought by someone. A flip is offered only when, at that measured rate, what you buy would sell within 60 minutes. Until an item has been watched for about two minutes it shows "measuring how fast it sells"; if nothing sold, "not a popular item".
  9. Never goods that NPC vendors sell in unlimited supply (food, drink, thread, dyes, vials…), because their price can't hold above the vendor's.
  7. If there's market-price history (readings at least 30 minutes apart), the resale price can't exceed its average.
  8. If real sales are on record, the resale price can't exceed what buyers actually paid.
* **Buy** asks the server for the real total; then you press **Confirm**. If the total is even 1c above what was checked, the purchase is cancelled and the deal is re-checked.
* A purchase is recorded only after the server confirms it or the gold has left your bags. Chat says **Purchase confirmed** or **Purchase NOT completed**.
* The **Mode** button at the bottom switches between **Vendor only** (every deal is guaranteed) and **Vendor + Flips**. `/amesh vendor` does the same. In vendor-only mode no flip checks are made, so more of the search budget goes to vendor deals.

### How it looks for deals (the radar)

The auction house offers two kinds of search, and they cost the same one request each:

* a **category search** returns the lowest price and total quantity of *every item in the category*;
* an **item search** returns the full listing of *one item*.

AuctionMesh uses the cheap, wide one as its radar and spends the narrow one only where it pays:

1. **Sweep.** Every 45 seconds it re-reads the crafting-material categories. That's about a dozen requests for every crafting material on the auction house.
2. **Trigger.** A full item search is queued only when the sweep shows something: the lowest price is at or under vendor price, is 20% or more under the known market price, or fell 15% or more since the last sweep.
3. **Confirm.** One item search loads the full listing and the deal rules decide.
4. **Volume for free.** A drop in an item's listed quantity between two sweeps means units were bought, so every material's trading volume is measured without extra requests.
5. **Routine.** Each of the 50 watched staples also gets one full look every 5 minutes to keep its market price current.

Compared with re-reading 50 items one by one, this covers every crafting material and uses fewer requests. It should also spot a new cheap listing within one sweep instead of one round. With friends on the same channel the sweep is shared: each category is read by one of you.

The game's full-download scan (`/amesh scan`, one request for the entire auction house, allowed once per 15 minutes) is still available.

### Where the prices come from

The game's addon API has no realm-wide sales history. It offers two real sources, and AuctionMesh uses only those:

* **The complete live listing of an item.** Before judging a deal or pricing a post, the item is searched and every page of its listing is loaded. The "market price" is read from that full listing (rule 2 above). Price history is built only from these readings, at most one per 30 minutes, never from the single lowest price seen while browsing.
* **Real sales.** When sale gold is taken from your mailbox, the sale invoice says what the buyer actually paid. That is recorded, shown in chat ("Sold: 6 x Linen Cloth at 77c each"), and shared with your friends. When a recent sale is on record, a flip's resale price can't exceed what buyers actually paid, and the deal row says "(buyers paid 77c)".

Item tooltips show all three: cheapest listing, market price from the full listing, and what buyers paid.

### PORTFOLIO tab (selling)

Everything you bought is listed here, with what you paid, what it sells for, the profit per item, and the one thing to do with it:

```
 Copper Ore x12        In your mailbox
   Paid 3c  >  Sell 5c  >  +2c each
 Linen Cloth x6        Ready to post                               [ Post ]
   Paid 20c  >  Sell 77c  >  +52c each
 Holding: paid 1s56c  >  expect back 4s92c  =  +3s36c            [Post next]
```

| It says | What happens |
|---|---|
| **In your mailbox** | Open any mailbox. AH purchases and sale gold are collected automatically, and the inbox is checked against your bags. |
| **Sell to any vendor** | Talk to any vendor. Nothing is sold by itself: press **Sell all to vendor** (it shows the total you'll receive) or **Sell** on a single row. Only the units you bought are sold, never copies you already owned. |
| **Ready to post** | Press **Post** (or **Post next**). The price is 1 step under the cheapest other seller, and never below what you paid plus the deposit plus the 5% cut. It posts everything of that item in one click. |
| **Waiting: market is below your cost** | Nothing is posted, because that would lose money. It re-checks every 10 minutes. |

The game requires one click or key press per auction. For speed, make a macro `/click AuctionMeshPostButton` and tap it. An item only leaves the list once your bags show it really went. Right-click a row to remove it. Drag an item from your bags onto the window to add it by hand.

AuctionMesh only works while its own panel is open. When you switch to the game's own auction screens it sends nothing at all, so it never changes what those screens show. Moving the mouse over the auction house window doesn't pause anything; it only waits briefly while your mouse is on a Buy or Post button, and for 8 seconds after you use one of the game's own auction buttons.

Non-stackable items (gear, recipes) are never offered as deals. They are only priced for selling.

The server has the final word on a purchase. If its quote is higher than the listing showed, nothing is bought, and the window says so. When the quote shows the cheap listings can't be bought by you (for example your own auctions), that deal is removed and doesn't come back. Your own auctions are also read from the server's "my auctions" list and never counted as deals.

The top line of the window shows the result of your last click for 10 seconds, so a click always gets a visible answer.

**The posting fee.** The game takes a fee when you list an item and gives it back when the item sells; you lose it only if the auction expires or you cancel. So AuctionMesh keeps the fee aside (it never lets you spend gold you need for posting) but doesn't subtract it from profit. It asks the game for the fee on 1 unit and on 100 units of each item, which also reveals any minimum fee per posting. `Deals.cfg.depositIsCost = true` in `Deals.lua` switches to counting the fee as lost. The first sale you collect writes an `INVOICE` line to the log showing whether the fee came back.

**Clicks are never thrown away.** If the auction house is busy when you press Buy, the click is held and sent the moment the server is free. Background work also stops while your mouse is on a Buy or Post button. Items waiting on the SELL tab are priced before anything else is checked.

### If something goes wrong

* Press **Log** (or type `/amesh log`), then Ctrl+A, Ctrl+C, and paste it to Claude. It records every auction house call, every error, and every decision (which listings a deal was based on, quotes, purchases, posts).
* `/amesh restore` rebuilds the SELL list from your purchase log.
* All requests go through one queue, so your clicks go first and background scanning slows down automatically after an "Internal auction error".

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

Scanning starts automatically when the AH opens (`/amesh swarm` turns it off or on):

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
3. Open the AH. The window opens and scanning starts by itself. Price lines also show up in item tooltips.

Commands: `/amesh` (open/close the window) `| flips on/off | auto on/off | margin <pct> | log | restore | track <item> [cost] | status | channel <name> [pw] | guild | swarm | focus <types> | scan`

## Tests

```bash
lua5.1 tests/ui_smoke.lua      # whole addon against a fake game client: scan, buy, mail, vendor, post
lua5.1 tests/deals_test.lua    # deal rules, posting prices, price history
lua5.1 tests/purchase_test.lua # purchase confirmation + mailbox check
lua5.1 tests/seller_test.lua   # posting / vendor safety
lua5.1 tests/sim.lua           # multi-player network simulator
python3 tests/test_server.py  # companion ↔ server ↔ Seed.lua round trip
```

## Known limits / to verify in game

* **Not yet run in the real client.** The protocol logic is tested offline against stubbed WoW APIs. The AH calls follow the retail `C_AuctionHouse` API, which Auctioneer's Forever build also uses.
* If the client blocks automatic `SendBrowseQuery` (an `ADDON_ACTION_BLOCKED` message appears), the swarm switches to manual mode. Bind a key to `/amesh step`; each press scans one step.
* While the swarm runs, it uses the AH browse list, so don't browse by hand at the same time.
* The sniper never buys by itself. Every purchase is your click, which the game requires anyway. Check the numbers on expensive buys.
* **Deposits** are counted as a cost, since you lose them if an item doesn't sell. The amount comes from the game's own deposit calculation where that's available. Otherwise it's estimated at 15% of the vendor price, then replaced with the real figure after your first post of that item. Until an item's details have loaded, it's never treated as an AH flip.
* Prices are stored per item ID, so different item levels of the same gear collapse into the cheapest one. Battle pets are stored per species.
* Midnight blocks addon messages in some instanced or combat situations. Sends are paused in combat and retried automatically.
* Anyone on the channel can send data, so only share the channel password with people you trust.

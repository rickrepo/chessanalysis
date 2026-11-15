# AuctionMesh

AuctionMesh is a WoW Forever addon (Midnight retail client, interface 16001) for sniping and flipping on the auction house: a radar that reads prices about once a second, a **snipe box** that buys a deal the moment it appears, and a ledger of what you bought, what it sold for and what to do with each item. It works alone: nothing is sent to other players.

## How to use it

Open the auction house. The panel opens inside the auction house window and price reading starts by itself. It has four tabs and a bar at the top right.

```
 [ Trades ] [ Bags ] [ Picks ] [ Setup ]           [#########------]
                                    Tuned: 1.6 requests a second, 94% in use
 MONEY
 Gold on this character now                               42g 58s 88c
 Sold: waiting in the mailbox now                        + 1g 33s 67c
 Sold: still on its way                      + 8g 55s 62c  next 16 min
 Listed: if it sells at the listed prices                + 6g 46s 21c
 Bought, not listed yet: at the live price               + 3g 58s 66c
 ---------------------------------------------------------------------
 Total when it has all sold                               62g 53s 04c
 Not counted: 2 held items that cost 53s 50c (tab Bags).

 NEXT  Press Buy on Copper Ore: pay 36c, make +24c (guaranteed: sell to a vendor).

 DEALS TO BUY NOW (2)     BUY        MARKET   SPREAD   VOLUME    PROFIT
 Copper Ore               12 @ 3c    5c       +67%     instant   +24c    [ Buy ]
 Linen Cloth              6 @ 20c    78c      +285%    40/h      +3s 18c [ Buy ]
 STUCK LISTINGS (1)       QTY        COST     MARKET   STATUS    P / L
 Wool Cloth x5            5          34c      1s 60c   UNDERCUT  +5s 90c
```

* **Trades** is the money and the market: what you have, deals you can buy right now, and your own auctions.
* **Bags** is what you hold and the one thing to do with each item: post it or sell it to a vendor (whichever pays more), collect it from the mailbox, or wait.
* **Picks** says which item, if any, is worth a stake-out, from deals the radar has already seen.
* **Setup** has a control for every setting, in five short groups. No chat commands are needed.
* The mouse wheel scrolls a list that is longer than the panel.

### Where the panel lives

With the auction house open, the panel is **inside the auction house window**: it covers the content area, is exactly that window's size, and opens, moves and closes with it. An **AuctionMesh** tab under the window switches between the game's own screens and the panel; clicking any of the game's tabs also switches back. At a vendor or mailbox it appears as a compact separate window. The **The panel** button on the Setup tab makes it a separate window everywhere.

### NEXT: one instruction

One line always says the most profitable thing to do right now, with the gold it makes:

```
NEXT  Press Buy on Heavy Leather: pay 2s40c, make +4s80c (resale, sells in ~12 min).
NEXT  Visit a mailbox: 1 purchase(s) to collect.
NEXT  Open Bags and press Post: 2 item(s) to list for +3s18c.
NEXT  Visit any vendor: 1 item(s) to sell for +24c profit.
```

The line at the bottom of the Trades tab shows the profit on the deals on screen, the profit banked so far, and this session's rate per hour.

### The look

A flat dark panel with thin one-pixel outlines, after a layout picked by the user:

* three tabs, **Trades | Bags | Setup**; the selected one has a teal outline;
* grey small-caps headings over a thin rule, instead of framed boxes;
* label on the left, amount on the right, and a ruled total line;
* money is plain text, `42g 58s 88c`, in the colour of its line: white = gold you hold, green = sold and in the mailbox, teal = sold and on its way, orange = depends on a sale;
* one line per row. The longer explanation ("Buy 6 for …, relist at …") is in the tooltip when you hover a row.

Only the **AuctionMesh** tab under the auction house window uses the game's own tab style, so it sits naturally next to the game's tabs.

### MONEY: what you really have

The top of the **Trades** tab answers one question: how much gold does this become once everything has sold?

* **Sold: waiting in the mailbox now** and **Sold: still on its way** are read from the sale invoices in your mailbox, so they are real sales. The game holds sale gold back for a while and the invoice says until when; "next 16 min" is the next arrival. These two lines are as of your last mailbox visit.
* **Listed** is your live auctions at their listed prices, after the 5% cut.
* **Bought, not listed yet** is what is in your bags or mailbox waiting to be sold, at the live price (the vendor price for vendor deals).
* **Not counted:** items held because the price fell below what you paid, and auctions that are no longer listed but have no sale invoice yet. Such an auction either sold or expired; a mailbox visit tells which, and until then the addon does not call it sold.

### The bar: what the engine is doing

The bar at the top right is on every tab.

| Bar | Text | Meaning |
|---|---|---|
| orange, filling up | `Measuring the server's limit: 14 of 20 requests` | First minutes on a realm: timing how fast the server answers |
| orange, filling up | `Trying a shorter pause (0.00s): 12 of 30 requests` | An experiment is running; it is kept only if all 30 requests succeed |
| orange, full | `Radar share 30% > 35%` | The split of requests was just changed |
| teal | `Tuned: 1.6 requests a second, 94% in use` | Nothing being tried; the bar is how much of the request budget is in use |
| empty | `Paused while you click` / `Idle: the auction house is closed` | Nothing is being sent |

### The ledger: the drawer on the right

A slim **DETAILS** handle sits on the panel's right edge. Clicking it slides a second panel out to the right (click again to hide it). The mouse wheel scrolls it. It is a ledger: one line per purchase, and nothing else.

```
 LEDGER
 Paid for everything bought                             - 2s 76c
 Came back from what sold                               + 4s 99c
 Sold, gold on its way                                  + 3s 80c
 ----------------------------------------------------------------
 You are up                                               6s 03c
 1 purchase not sold yet: 1s 20c still to come back
 WHAT YOU BOUGHT, NEWEST FIRST (4)
 Test Ore x5  at 40c                 SOLD, gold coming  + 1s 80c
 Linen Cloth x6  at 20c                   NOT SOLD  down 1s 20c
 Linen Cloth x6  at 20c                          SOLD  + 3s 19c
 Copper Ore x12  at 3c                             SOLD  + 24c
```

| The right-hand side says | Meaning |
|---|---|
| green `SOLD  + 3s 19c` | Sold. The profit really made: what the buyer paid, minus the cut, minus what you paid (red if it was a loss) |
| orange `SOLD, gold coming  + 1s 80c` | It sold on the auction house and the gold is on its way (the hour's wait). The profit that is coming |
| red `NOT SOLD  down 1s 20c` | Not sold yet. You are down what you paid for it until it sells |
| red `3 NOT SOLD  down 60c` | Part of it sold; 3 units have not |
| grey `not found, not counted` | The units were not found in your bags, mailbox or auctions |

* **You are up / down** is everything that came back (plus sold gold on its way) minus everything paid.
* The drawer has two views, **Ledger | Market**. Market starts with the **prime items** (see Laser focus below), then the biggest 24-hour price moves and what sells fastest.
* **Click any item row** in the main panel and the drawer shows that item alone: cheapest listing and its age, market price, 24h change, units sold per hour, what buyers really paid, vendor price, why the last check was or wasn't a deal, then each of your trades in it in full, with one recommendation (`DO`, `WAIT` or `CHECK`) for what you still hold. **Ledger** goes back.
* **Stop tracking this item** is a button at the bottom of that one-item view, and asks for a second click. (A right-click on a row used to remove it, which was too easy to do by accident; a right-click now does the same as a left-click.)

The addon never cancels an auction by itself. An undercut auction has a **Cancel** button on its row; the cancel happens on your second click (see "Undercut and expired auctions").

### Setup: five short groups

Nothing has to be typed in chat. The Setup tab has a control for everything that can be changed, each showing its current value, and nothing else:

| Group | Control | What it does |
|---|---|---|
| DEALS | Smallest profit worth showing | Two boxes, silver and copper. Smaller deals are hidden |
| | Profit a flip must leave after the auction house cut | A percentage box. Auto-adjust nudges it from how trades turn out |
| | Show | Vendor deals + flips, or vendor deals only (every deal guaranteed) |
| | Money in unsold auctions, at most | 30%, 50%, 70% or 100% of what you own |
| BUYING | Buy with | Mouse wheel, a key you tap, a key you hold down, or clicks only (see Sniping) |
| | Key | Click it, then press the key to buy with |
| WATCHING | Radar reads | Crafting materials only, all money-makers, or the whole auction house. Materials are read about every second in all three |
| | Look for flips only on | Laser focus: off, prime items (picked from measured activity), or my own list |
| CLAUDE | Import | A box and **Apply**: paste a settings code (or the whole message it came in) and everything in it is set |
| | Send to Claude | **Snapshot** (any time), **Daily report** (once a day), **Log** (when something looks wrong; the log window also has last session's log) |
| ADDON | The panel | Inside the auction house window or a window of its own; opens by itself on or off |
| | Auto-adjust | One switch for the pace, the split of requests, the profit bar, the smallest profit and the radar's quiet time. **Forget what was learned** needs a second click |

Under the controls are three lines: the last thing auto-adjust changed (and when), the server's measured request limit, and what one radar read costs. The heading shows the installed version, e.g. `SETTINGS (AuctionMesh version 3.31.0)`, and the line under it shows what your last click did. Hovering a button explains it.

To track an item you bought some other way, drag it from your bags onto the panel.

### Laser focus: only where money moves fast

The addon counts what it sees, per item, and keeps the counts between sessions: how many units really sell an hour (see below), how much gold that is, how often the cheapest listing is 20% or more under the market, how many deals were confirmed, and how long deals lasted before someone else took them.

An item is **prime** when all of these hold:

* it has been watched for at least 10 minutes and is measured to sell **30 or more an hour**;
* it has a market price from a full listing;
* you can afford it;
* vendors don't sell it, and an auction of it hasn't just expired on you.

Prime items are ranked by gold traded per hour x (how often it dips + 2%) x (1 + deals found). The drawer's **Market** view lists them with the reason, and clicking any item shows whether it is prime and, if not, why.

The **Laser focus** button on the Setup tab has three positions:

| Position | What the addon does |
|---|---|
| Off | Watches the 50 most-listed materials, each fully checked every 5 minutes (as before) |
| Prime items | Looks for flips only on the 12 best prime items, each fully checked every **30 seconds**. With fewer than 3 prime items measured it says so and keeps watching everything |
| My own list | The same, on items you chose: click an item, then **Add to my focus list** in the drawer; or paste a focus code |

Vendor-price deals are shown whatever the focus, because they are guaranteed. Everything the radar reads is still counted, so the prime list keeps improving while you are focused.

**How "sold an hour" is measured.** Commodities are always bought cheapest first, so a sale eats a listing from the bottom. Between two full readings of an item, units missing from the cheapest price levels count as sold; counting stops at the first level that is intact. Units that vanish higher up while cheaper stock remains are cancelled auctions and are not counted, and a cheapest level that vanishes while the same amount reappears lower is treated as cancelled-and-relisted. This under-counts rather than over-counts.

The radar's quantity drops (units leaving the whole listing) are kept separately as **churn** and shown in the report only. The first real report showed why: churn said 15,000 Heavy Leather "sold" an hour, because it includes every cancelled and re-posted auction.

### Snapshot: what is happening right now, in one paste

A **Snapshot** button sits on the panel's header, on every tab. It opens one short block of text (about 50 lines): click in the box, Ctrl+A, Ctrl+C, and paste it to Claude. It is the quick one; the daily report below is the long one.

| Section | What it holds |
|---|---|
| MONEY | Gold in hand; sale gold waiting in the mailbox; every sold auction with the gold due and when; every unsold auction with your price, your cost, its age and the cheapest other listing; everything bought and not listed; the total; gold at the start of the day and profit banked |
| MAILBOX | What it held when it was last read (items, sale gold, sales still to be paid) and how long ago that was. The mailbox can only be read while it is open |
| SETTINGS | Smallest profit, flip margin, flips on or off, what the radar reads, laser focus, the unsold-auctions limit, how you buy, whether one-click buying works, auto-adjust |
| SNIPING | Got / missed / gone this session; how often the snipe box was armed and how many purchases the wheel started; deals hidden by the smallest-profit setting; muted items; the last 20 outcomes, each with **how long after the deal appeared your input came** and whether it was the wheel or a click |
| WHY CHECKS WERE NOT DEALS | The eight most common reasons today |
| LAST PURCHASES | The last 12, each with what became of it |
| ENGINE | Minutes working, how often the radar read, the server's request limit, checks, deals, purchases |

### Import: paste what Claude sent

The Snapshot ends with your **settings code**, one line that holds every setting that decides what is shown as a deal:

```
AMS1:min=100;margin=25;flips=1;scope=mats;focus=prime;list=2589,2592;tied=50;spend=35;small=15;buy=wheel;tune=1;itemmin=4306:300;ignore=2287
```

Claude reads it in your Snapshot and sends back a changed one. On the Setup tab, paste it into **Import** (the whole message can be pasted; the code is found in it) and press **Apply**. The panel and chat then say exactly what changed, for example `Imported 3 changes: smallest profit 1s 0c > 75c; watch list: added Wool Cloth; Silk Cloth: smallest profit 3s 0c.`

| In the code | Sets |
|---|---|
| `min=75` | Smallest profit worth showing a deal for, in copper |
| `margin=22` | Profit a flip must leave after the cut, in percent |
| `flips=1` / `flips=0` | Flips on, or vendor deals only |
| `scope=mats` / `money` / `all` | What the radar reads |
| `focus=off` / `prime` / `list` | Laser focus |
| `list=2589,2592` | Your own watch list, replaced by these items |
| `watch=+2592,-4306` | Adds items to your watch list, or takes them off, leaving the rest as it is |
| `itemmin=4306:300` | A smallest profit for one item only (`4306:0` clears it) |
| `ignore=+2287,-2589` | Items never to show deals for; `-` takes one off the list |
| `tied=50`, `spend=35`, `small=15` | The capital limits, in percent: unsold auctions, one flip, the always-allowed small flip |
| `every=60` | With laser focus on, how often each focus item's full listing is re-read, in seconds (20 to 300). Each re-read is one request the radar does not get; flips straight from the radar need a listing read in the last two minutes |
| `stake=2838` / `stake=0` | Sets a stake-out on one item, or ends it |
| `buy=wheel` / `key` / `hold` / `click` | How you buy (the older `wheel=1` / `wheel=0` still work) |
| `key=F` | The key for `buy=key`; modifiers as `SHIFT-F`, `CTRL-F`, `ALT-F` |
| `tune=1` / `tune=0` | Auto-adjust on or off |

* A code need not carry everything: `AMS1:min=60;watch=+2592` changes those two things and nothing else.
* With laser focus on **prime items**, your own watch list is watched as well, on top of what the addon picked.
* Anything in a code that is not understood is left alone and named.
* A focus code (`AMF1:`) pasted into the same box still works.

### Auto-adjust: settings that follow what really happens

The **Auto-adjust** switch on the Setup tab covers the request pace, the flip profit bar, and two more things. Every change is written down with its reason: on the first rows under the settings, in chat, and in the Snapshot.

| What adjusts | Rule |
|---|---|
| Smallest profit | Looked at after every 10 minutes of use. At most one deal shown and three or more hidden by the minimum: 25% lower. Fifteen or more deals shown: 25% higher. Never under 20c, never over 2% of everything you own (at least 1s) |
| The radar's quiet time when a deal appears | 6 seconds until your inputs have been timed. Then the median of your last inputs plus one second, between 2 and 6. While the wheel is rolling in the snipe box: 1 second |

A setting you change yourself, or import, is left alone for 30 minutes. With the switch off nothing changes by itself.

### The daily report, and focus codes

**Daily report** on the Setup tab opens one block of text. Select all, copy, and paste it to Claude once a day. It is about 5 to 20 thousand characters and contains:

* settings and the current focus;
* each of the last 7 days: minutes the addon was working, radar reads, checks, deals found and their profit, purchases, deals that vanished before a buy, failed buys;
* your last 30 trades from purchase to sale, with profit and hours to sell;
* the last 40 deals seen and what became of each (bought, gone after N seconds, failed);
* why checks were not deals, counted;
* reads, dips and deals by hour of the day;
* the market table: for the 40 items with the most gold traded per hour, and any item with a dip or a deal, the prices, vendor price, units sold per hour, 6h and 24h change, dips, deals, and prime or the reason it is not;
* what the request engine has learned.

It holds no character name. All money in it is in copper.

From that, Claude can send back a **focus code**, for example `AMF1:2589,2592,c7.5,m25,p150`. Paste it into the Focus code box and press **Apply**. A number is an item to focus on, `c7.5` is a category (its prime items are included), `m25` sets the flip profit to 25% and `p150` sets the smallest deal to 1s 50c. Applying a code switches laser focus to that list.

### What the first real report changed (version 3.13)

| The report showed | What was changed |
|---|---|
| One request returns the whole materials class (395 items) | Recorded as fact; the radar is nearly free |
| The radar came round every 8s and under half the request budget was used, while deals lasted 7 to 36 seconds | A radar read that costs 1 or 2 requests is read on its own clock, back to back |
| "Sells an hour" was wildly inflated (cancelled auctions counted as sales) | Sales are measured from the cheap end of full listings only; the old figures were discarded |
| 66 under-market alerts gave 3 deals | The alert bar is now the deal rule's own bar (77% of market at a 20% margin, was a fixed 80%) |
| 404 routine checks gave 1 deal | Items actually seen under market are checked first |
| A 1c gap on a 4c item counted as a dip | A dip must also be at least 3c |
| 12 guaranteed vendor deals hidden by the 50c minimum | While you hold under 5 silver, vendor profits from a tenth of your gold (at least 10c) are shown |
| "Cancel and repost" was advised with 54c against a 1s fee | The advice checks the fee against your gold |
| A vendor sale made by hand was reported as "not found" | Selling a tracked item to a vendor yourself is recorded and banked |

The report itself (now v2) adds: your auctions with the cheapest listing now, requests used and radar interval, churn next to real sales, gold at the day's start, and how close failed checks were to being deals.

### Sniping: from "a deal appeared" to "it's yours"

Real reports show deals on this realm lasting 1 to 3 seconds, a few lasting 10 to 45. Everything between a deal appearing and your purchase landing is built for speed.

| Step | What the addon does |
|---|---|
| A deal is confirmed | If the first page of the listing already proves the deal, it acts on it at once instead of fetching the rest |
| The same instant | The panel redraws immediately, a sound plays, and the radar goes **silent for 6 seconds** so the auction house is free for your click |
| Your first click | Asks the server for the price, **inside that click**. If the auction house is busy the game queues it itself |
| The price arrives (about 0.15s later) | If it is what the deal showed or less, the addon **sends the purchase itself**: one click buys. Whether this game accepts a purchase that does not come from a click is not known; it is tried once, and if the game blocks it the addon switches it off and says so |
| If that is blocked: your next input | Buys. The server needs two steps (ask the price, then buy) and the game wants a real input for each |

**The big Buy button** on the Trades tab never moves and always acts on the best deal. Click it repeatedly: the first click asks for the price, clicks while the price is on its way are ignored, and the first input after it arrives buys. It never buys twice.

**The snipe box.** The big button is a box you can sit in. Put the mouse in it and keep rolling the wheel:

| The box shows | Meaning |
|---|---|
| grey `SNIPE BOX, not armed: put the mouse here and keep rolling the wheel` | No deal, and the wheel is not rolling |
| green `ARMED  the next deal is bought the moment it appears  radar only: nothing else is being sent` | The addon sees your wheel (a notch in the last 0.7 seconds). Keep rolling; it goes back to "not armed" when the wheel stops |
| the deal, then `BUYING...`, then `GOT IT` or `MISSED` | The first notch after a deal appeared asked the price; the purchase followed by itself (or with the next notch) |
| grey `Watching. No deal right now.` | Idle. The box shows nothing but sniping; chores such as "visit a mailbox" are on the Bags tab, whose label counts them |
| orange `4 deals hidden by your 90s 00c minimum profit (best: + 11s 22c)` | Deals exist but your own minimum is hiding them. Lower it on the Setup tab |

Because you are already rolling when the deal appears, there is no reaction time: the purchase starts within a few hundredths of a second of the deal being found. Nothing is bought while there is no deal, the box never buys the same deal twice, and the price check still applies (a deal that got dearer is not bought). Rolling inside the box never scrolls the list.

The mouse resting in the box pauses nothing. It used to: the radar stood still whenever the mouse was on the Buy button, so parking the mouse there while waiting for a deal meant no deal could appear. A row's Buy or Post button still gives a short quiet moment, for at most 3 seconds.

**Snipe mode: every request goes to the radar.** While you are rolling in the box (and for 3 seconds after), the addon sends nothing but radar reads and the checks its alerts ask for: no routine item checks, no side classes, no housekeeping. A routine check costs one request, and a deal that appears during it is seen 0.65 seconds late.

**Flips straight from the radar.** Vendor deals were already shown without an item check. Flips now are too: when an item's cheapest price falls and N units appeared since the radar's last read, and that item's full listing was read in the last two minutes, the deal rules run on "N units at the new price, on top of that listing" and the deal is shown at once. That removes the item check that used to sit between the radar and the deal (0.65 seconds, plus half a second before your click's own request may go). Your click asks the server what N units cost and buys only if that is N x the price seen. Only the new units are offered this way; anything else gets the normal check.

| From the radar seeing a listing to the purchase being sent | Before | Now, rolling in the box |
|---|---|---|
| Item check | about 0.65s | none (vendor deals and flips on recently read items) |
| Wait before your request may be sent | about 0.5s | none (nothing was sent in between) |
| Your reaction | 1 to 10 seconds in the logs | the next wheel notch |
| Price request, then purchase | about 0.15s + 0.5s | the same: the game's own two steps |

**Stake-out: one item, watched by asking its price.** With the wheel rolling and a reaction time of zero, a real session still lost 12 of 23 deals: the game makes every request wait about half a second for the one before it, and the normal path has three or four of them (radar read, item check, price request, purchase). For one item that keeps being listed cheap, the first links can go:

1. Click the item's row, then **Stake out this item** at the bottom of the drawer.
2. Roll the wheel in the snipe box. Every notch the auction house allows asks the server what one unit of that item costs now. The box shows `STAKE-OUT  Heavy Stone: buys at 2s 36c or less  last price 3s 00c  asked 15, bought 0`.
3. When the answer is at or under the buying price, the purchase follows at once.

| | |
|---|---|
| The buying price | Not typed in and not a guess: the dearest price that is still a deal by your normal rules (flip margin, capital limits, and the smallest profit judged on a lot of up to eight units), worked out from the item's full listing. The listing is re-read once a minute while the stake-out runs |
| More than one unit | After a purchase the next request asks for two, then four, up to eight, and buys them only if every one is at the price just paid. Any other answer puts it back to one, so a dear unit is never bought along with cheap ones |
| What it costs | The radar is off while you roll: every request is a price request for that one item. Stop rolling and the radar is back within 3 seconds |
| Ending it | **Stop the stake-out** in the same place, or `stake=0` in a settings code. `stake=2838` in a code sets it |
| When it will not run | `STAKE-OUT WAITING` with the reason: the listing has not been read yet, or no price would be a deal right now (for example your money is in unsold auctions) |

This has not run in the real game yet. What it saves is the radar read and the item check: about half a second against a deal shown straight from the radar, about a second and a half against one that needed an item check.

**Picks: which item is worth a stake-out.** The **Picks** tab answers that, so no item has to be chosen by feel. It reads the record of deals the radar has already seen (the last 400, with what became of each) and shows:

| Column | Meaning |
|---|---|
| DEALS | Deals seen on the item in the last 24 hours |
| YOU GOT | How many you bought |
| MISSED | How many you went for and lost to someone faster, and what they were worth. Only these count for the recommendation: speed is what a stake-out adds |
| GONE | How many left before any input, and how long they lasted. Being at the snipe box wins these, not a stake-out |
| BUYS AT | The most a stake-out would pay per unit now, from the item's listing as last read |
| CHEAPEST | The radar's last read of the item |

The line at the top says what to do with your inputs right now:

* `Try a stake-out on Silk Cloth.` when what you missed on that item is worth more than everything the radar caught for you on all other items in the same time. That second figure is what a stake-out gives up, because the radar is off while it runs. Both figures are shown.
* `Keep the radar. No single item is worth a stake-out.` otherwise, with the item you lost most on and the two figures.
* `Not enough has been seen yet` with fewer than five deals on record.

**Stake out** on a row sets the stake-out in one click and takes you to the snipe box; the same button then reads **Stop**. The tab's label reads `Picks (1)` when there is a recommendation and no stake-out is set. With a stake-out set, the tab shows what it buys at, how often the price has been asked and how many units it has bought on that item so far (kept across sessions), and says so when the record no longer favours it.

It costs nothing in speed. Nothing on the tab sends a request to the auction house: it is arithmetic on what is already in memory. It is worked out again at most every 30 seconds, and never while inputs are arriving in the snipe box, while a deal is on screen or during a purchase; the last figures are shown until then. The one request a stake-out needs (reading the item's listing) is sent when you press **Stake out**, as before.

**Four ways to buy** (Setup tab, **Buy with**; one click changes it). Clicking the box works in all of them.

| Buy with | How |
|---|---|
| **Mouse wheel** (the default) | Put the mouse in the snipe box and roll. While a deal is up the wheel buys anywhere on screen, and goes back to scrolling the moment there is none. Confirmed in the real game |
| **A key: tap it** | Press **Key** on the Setup tab, then the key you want (a modifier can be held with it; mouse side buttons work; Esc cancels). While the Trades tab is open, that key presses the snipe box wherever the mouse is; on other tabs and with the panel closed the key does what it always did. Tap it repeatedly, like rolling the wheel |
| **A key: hold it down** | Click the snipe box once, then hold any letter key down. The game repeats a held letter many times a second, and every repeat is one input. While the box has the keyboard, keys do not reach the game (you cannot walk or chat); Esc gives it back |
| **Clicks only** | Neither the wheel nor a key buys; only clicks on the box |

* Tapping or holding with no deal on screen arms the box exactly as rolling does: snipe mode, radar only, and the first input after a deal appears buys it.
* The key modes have not run in the real game yet. A key bound through the game is a real input, so tapping should behave like the wheel. Holding is less certain: the game may not accept a repeated character as an input for buying. If it refuses one, the addon drops that mode, falls back to one that works and says so on the panel.
* The Snapshot's settings line and the settings code say which one is in use (`buy=wheel`, `buy=key;key=F`, `buy=hold`, `buy=click`).
* The game's own Key Bindings screen (Options, Keybindings, AddOns) also lists **AuctionMesh: Buy the best deal**, for a permanent binding.

What the seventh real log showed (version 3.28):

| The log showed | Change |
|---|---|
| 16 Silk Cloth appeared at 99c, under vendor price. The item's total quantity went down in the same second (other units were bought), so the addon could not count the new ones and fell back to an item check: 1.1 seconds before the price request went out | When the price falls under vendor price and the count is not clear, the deal is shown at once for four units; the server's price for them decides, and what is left is found straight after |
| "Price is falling fast: not buying into a drop" refused 140 checks in one day, whatever the discount | A falling price is priced in instead: the resale is planned at the price the market is heading for, and the usual margin decides. 7 Wool Cloth at 34c under a 1s 34c market is still a flip in a market falling 20%; a listing 25% under is not |
| With the wider radar setting, three of the four extra categories held nothing, and each was read every 30 seconds | A category with nothing in it is looked at every 10 minutes |
| A stake-out would have judged the smallest profit on one unit, which a cheap material never clears | It is judged on a lot of up to eight |

What the sixth real log showed (version 3.26), with the wheel in use (reaction time 0.0 seconds, 11 got and 12 missed):

| The log showed | Change |
|---|---|
| **The wheel works.** 27 purchases were started by the wheel, the first within 20 milliseconds of a deal being found | Confirmed in the real game |
| After a purchase the server refused (someone else got the units between the price and the buy), the game's error message for it was read as "the server is refusing requests". The radar stopped for 5 seconds, twice, and the pause between all requests went from 0 to 0.5 seconds: the radar then read every 1.13 seconds instead of every 0.70 | An error in the seconds after a purchase belongs to that purchase. No stop, no longer pause. The pause that had been learned this way is reset once |
| 9 Heavy Stone were on offer at 2s 25c under a market of 3s 24c. The addon priced yours 1c under them, at 2s 24c; they sold at once, about a silver each under the market | A few cheap units under the market are deals, not the market: rows 10% or more under the wall that hold no more than a tenth of its depth are skipped when pricing, so those would have been posted at 3s 23c |
| The engine bar ran over the Snapshot button and the Setup tab; Setup labels ran under their controls | The bar sits between the tabs and the Snapshot button and shrinks to the room there is (hidden if there is none). Every label and row is cut off with "..." rather than overlapping. The drawer opens on the left when there is no room on the right |

What is left of a miss now is the game's own timing: from the radar seeing a listing, the price request can go half a second later, and the purchase half a second after the price. Someone whose radar read lands a moment earlier gets there first.

What the fifth real log showed (version 3.21):

| The log showed | Change |
|---|---|
| **One click buys.** The game accepted the purchase the addon sent by itself after the price came back (16 Silk Cloth, bought with one click) | Confirmed in the real game; nothing to change |
| Silk Cloth clicked 6 and 10 seconds after it appeared; twice the listing had also changed in other ways, so no exact count of leftover units fitted the quote and the deal was dropped as MISSED with about 10 and about 6 cheap units still there | The quote still says roughly how many are left. The deal is offered again for about that many; the server's quote for that smaller request decides, and each further miss halves it. A wrong estimate costs one request and never buys a dear unit |
| Three misses in a row muted Silk Cloth for 10 minutes: the item that paid best | Five misses in a row, 3 minutes |
| The total read 92s when 77s was right | See "Why the total can differ from your gold": sale gold collected at the mailbox could stay counted as "waiting" |
| For several minutes every deal was refused as "under your 90s minimum" | The box now says when your own minimum is hiding deals |

What the fourth real log changed (version 3.19):

| The log showed | Change |
|---|---|
| 24 Wool Cloth at 1s; a quote for 16 came back as 6 at 1s plus 10 dearer. The deal was dropped as missed | The quote says how many cheap units are left. The deal is offered again at once for those: `6 of 16 still there` |
| Silk Cloth at 1s was missed four times in a row | After 3 misses in a row on one item, that item is muted for 10 minutes: someone faster is on it, and each try costs requests and your attention |
| Crafting materials were read every 6 seconds with the radar idle half the time (scope set to the wider one) | Materials are always read back to back, about every 0.65 seconds. The other classes are side reads |
| A vendor-price alert waited 3 seconds because the game refreshed its own list of your auctions | That pause is 1 second, not 2 |
| Six flips in four minutes were skipped as "money tied up", among them 45 Wool Cloth at 32c under a 1s 68c market. All of that money had already sold | Sold gold on its way no longer counts against the limit (see Capital) |

What the third real log changed (version 3.17), all aimed at the seconds before your click:

| The log showed | Change |
|---|---|
| The radar read every 3 seconds, so a deal was 1.5 seconds old on average before it was seen | One request reads everything, so the radar now reads back to back, about every 0.65 seconds |
| Alerts waited 3 to 5 seconds behind a radar read, a housekeeping query and a re-check | An alert is always checked next; nothing else gets a turn while one is waiting |
| Every vendor deal cost a 0.65 second item check before it was shown | When a price falls under vendor price and N units appeared since the last radar read, the deal is shown for N units at once. Your first click asks the server what N units cost; Buy is only offered if that is exactly N x the price seen |
| "Not buyable" appeared again, for units another buyer was taking | That guess is gone. Your own auctions are known from the server's list. After a miss the same units are ignored for 4 seconds (the listing goes on showing sold units for a moment); a repeat miss at the same price waits four times longer each time, up to 10 minutes |
| The game's list of sold auctions gives the amount paid and the time until pay-out | "Sold: still on its way" uses those figures directly, so the total matches the game's Auctions tab |

What the second real report corrected:

* **Clicks were being lost.** When the auction house was busy the addon held your click and sent it a moment later. The game blocks that, so the click did nothing. Clicks now always go out at once.
* **The radar was switching itself off.** Any action the game blocked, including one of those held clicks, turned the radar off for the rest of the session. Now only three blocked radar reads in a row can do that.
* **"Not buyable (your own auctions?)" was usually wrong.** It was shown whenever the server's price skipped the cheap units, which is also exactly what happens when someone else buys them first. The item was then ignored for 30 minutes. Now it is reported as MISSED, the item is read again, and it is only called not buyable if the cheap units are still listed after the server refused to sell them.
* **Old category lists were read as new.** The game re-sends its last category list after every item search; reading that as a fresh radar read produced alerts for prices long gone.

**You always know how it ended.** Every deal you went for, or that left before you could, ends in one of three messages:

* **GOT IT** 12 x Copper Ore for 36c (green, with a coin sound). Shown only when the server confirmed the purchase or the gold left your bags.
* **MISSED** someone was faster, nothing spent (red, with a different sound). You clicked, but it was gone.
* **GONE** someone else bought it N seconds after it appeared (orange). It left before you clicked.

The message is on the big button for 6 seconds, flashes in large text in the middle of your screen, and then stays on the line under the button with its age until the next outcome. That line also keeps a count for the session: "3 got, 1 missed, 2 gone before a click".

### Nothing is shared

Since version 3.29 the addon has no communication code. It sends no addon messages, joins no chat channel and sends nothing to a guild; there is nothing to switch off. An install that had joined a channel for the old sharing feature leaves it once, ten seconds after the first login with this version, and says so in chat.

### Moving the panel

Inside the auction house the panel is part of that window and cannot be dragged on its own (the addon does not move the game's windows). The **Pop out** button at the top right turns it into a separate window; drag it by its background, by an item row or by the drawer, and its position is remembered. **Dock** puts it back.

### Capital: an hour between a sale and your gold

The auction house pays out an hour after an auction sells. Gold spent on a flip is therefore out of reach for at least an hour, while gold spent on a vendor deal is back as soon as you reach a vendor. With a small purse that difference decides everything: a real 50 silver purse went all in on two flips, had nothing left for the vendor deals that followed, and after an hour was a few silver up.

So the addon treats your gold as the scarce thing:

| Rule | What it does |
|---|---|
| One flip takes at most 35% of the gold in hand | 50s in hand: a 20s pile of Earthroot is bought for 17s 50c, not all of it |
| Big flips stop when 50% of all your money is in auctions that have **not sold** | The Trades tab says `Big flips paused: 36s 48c of your 58s 03c is in auctions that have not sold (limit 50%).` |
| Gold from auctions that have sold does not count against that limit | It is certain and arrives within the hour. (It used to count, which skipped good flips while you were simply waiting to be paid) |
| A small flip is always allowed: up to 15% of the gold in hand | 7s 39c in hand: a 62c Heavy Stone worth + 2s is still bought |
| Vendor deals are never limited | Their gold is back in minutes, with no cut and no fee |
| Under 5 silver in all, neither limit applies | There is nothing to split |

* **Flips may tie up** on the Setup tab changes the 50%: click for 30%, 50%, 70% or 100%.
* Every deal says when its gold comes back: `gold back at the next vendor`, or `gold back in about 1h 05m` (time to sell plus the hour).
* When a pay-out is due, the next step shown is `Collect 36s 54c at a mailbox: sale gold has arrived.`
* For a flip in your bags that a vendor would also pay more than cost for, the recommendation gives both: post it (more, an hour later) or sell it to a vendor now (less, at once).

### Why the total can differ from your gold

**A double count that is fixed (3.21).** Sale gold that had paid out was counted as "Sold: waiting in the mailbox now" until the mailbox was read again at the end of collecting. Walking away from the mailbox before that reading finished left the gold counted twice: as gold in hand and as still waiting (a real total read 92s when 77s was right). Now any gold that arrives while the mailbox is open comes off "waiting" at once, and the mailbox is read before anything is taken.

Gold spent on a flip is not gone, it is somewhere else until the sale pays out. The MONEY section's total counts all of it:

* gold on the character;
* **sold, waiting to be paid:** read from the auction house's own list of your auctions (the same list the game's Auctions tab shows as gold coming in) and from mailbox invoices;
* **listed:** at your listed prices, after the cut. An auction the auction house no longer shows is still counted here until the mailbox shows whether it sold or came back;
* **bought, not listed yet.**

A purchase that cannot be found in your bags or mailbox is kept on the list and looked for again at the next mailbox visit; it is only dropped if it is still missing more than five minutes later.

### The cut and the posting fee

* **The 5% auction house cut is taken off every profit figure**: deals, the MONEY section, the drawer, recommendations.
* **The posting fee** is kept aside when a deal is judged (you must be able to pay it, so it is never spent on buying), but it is not subtracted from profit, because it normally comes back when the auction sells.
* **Whether it really comes back on this realm is checked on your first sale.** The sale invoice says how much fee was returned. If none was, chat says so, and from then on the fee is taken off every profit figure and a flip has to clear it.
* **An auction that runs out loses its fee.** That loss is taken off banked profit and shown on the trade in the drawer.
* The MONEY section's last line shows the fees currently paid on your auctions and which of the three states applies (confirmed / does not come back / not confirmed yet).

### The columns

```
 DEALS TO BUY NOW (1)   BUY          MARKET   SPREAD   VOLUME    PROFIT
 Light Leather          4 @ 10c      30c      +190%    2857/h    +68c   [ Buy ]

 TO POST AT THE AUCTION HOUSE (1)  QTY   COST     MARKET   STATUS    P / L
 Wool Cloth                        1     34c      1s 60c   READY     +1s 18c [ Post ]
```

* **SPREAD** is the gap between what you pay and what you sell for.
* **VOLUME** is units sold per hour, measured by watching the listing. Vendor deals say "instant".
* On the Bags tab, a `*` after MARKET means the price is the plan from when you bought; it becomes the live price once checked.

### Your auctions and banked profit

* An auction you post is shown on the Trades tab under **LISTED** with its quantity, cost, your price and expected profit. It moves under **STUCK LISTINGS** when the latest radar read saw someone cheaper, and under **ENDED, CHECK A MAILBOX** when it is no longer among your auctions. An auction that has **sold** is listed under **SOLD, GOLD ON ITS WAY** with `Sold: gold arrives in 16 min` (it used to be shown as stuck and undercut while its gold was on the way, because the cheaper listings the radar saw were other people's).
* **Banked so far** (bottom of the Trades tab) is profit actually made: vendor sales, plus auction sales once you collect the gold (sale price minus the auction house cut minus what you paid).

### Undercut and expired auctions

**Undercut: cancel and post again.** An auction under **STUCK LISTINGS** (someone lists cheaper than you) has a **Cancel** button on its row while the auction house is open.

| Step | What happens |
|---|---|
| First click | Nothing is cancelled. The row says what it costs: `Click again to cancel 5 at 1s 60c each. The posting fee of 10c is not returned.` The button reads **Sure?** for 5 seconds, then goes back to **Cancel** |
| Second click | The auction is cancelled at the auction house; the row says `Cancelling...` |
| The auction house confirms | The units are among your holdings again at what they cost you, shown on the Bags tab as **In your mailbox**. The lost posting fee is taken off your banked profit |
| At a mailbox | The addon takes them out |
| Back at the auction house | The Bags tab has them **Ready to post**, one step under the cheapest seller now. Press **Post** (or **Post next**) |

* Two clicks because rows move when a deal appears and a cancel cannot be taken back; both clicks are on the same button, so a double-click does it.
* With several auctions of one item, each pair of clicks cancels one, dearest first.
* The drawer's recommendation still says whether cancelling pays: it compares the profit left after posting again (and paying the fee again) with your smallest profit. The button is there either way.
* The button appears once the auction house has listed your auctions, a second or two after you open it. A cancel is not scored as a flip that failed to sell.

**Expired: it comes back ready to post.** An auction that ran out arrives in the mailbox. At a mailbox the addon recognises it, takes it out, and puts it on the Bags tab with what it cost you; at the auction house it is priced live and **Post** lists it again.

* It is recognised from the mail itself: an item you have listed, in a mail with no invoice. Something you bought arrives with an invoice and is never mistaken for it.
* This works when you visit the mailbox before the auction house in a new session, when you already hold more of the same item (the returned units are added, cost averaged), and when only one of several auctions of the item ran out.
* If you take the mail out yourself before the addon does, it is still recognised and tracked.
* The posting fee of an auction that did not sell is booked as lost, and the item is not flipped again for 12 hours (it can still be posted).
* Posting again is always your click: nothing is listed by itself.

### Deals (Trades tab)

Only deals that were just checked against the live listings appear here, with the exact quantity and the exact total you'll pay. Nothing is shown from an estimate.

* **SAFE** means the item is listed for less than an NPC vendor pays. Buy it, sell it to any vendor, and keep the difference. This is guaranteed profit, with no AH cut and no deposit.
* **FLIP** means a few units are listed far below the real market. It has good odds but is not guaranteed, because someone still has to buy from you. A flip is only shown when **all** of these hold:
  1. It's a stackable good. Gear is never flipped, because item levels make prices incomparable.
  2. There's a real market price: at least 10 units, at 2 or more prices, within 25% of each other. One lonely expensive listing doesn't count.
  3. You buy **every** cheap unit, so none are left to undercut you. One exception for a small purse: if the whole cheap pile is at most 10% of the real market, you may buy the part you can afford (the row says how many cheap ones are left).
  4. The cheap units are at most half the size of the real market.
  5. It uses at most half your gold (all of it while you have under 1 gold).
  6. Profit is at least 20% after the 5% AH cut (the Setup tab's flip profit box changes it). The posting fee is kept aside, not subtracted, because it comes back on sale.
  10. **Volume.** The item must have been seen selling. The watch list re-reads each listing about once a minute; units that disappear from the cheap end between two readings were bought by someone. A flip is offered only when, at that measured rate, what you buy would sell within 60 minutes. Until an item has been watched for about two minutes it shows "measuring how fast it sells"; if nothing sold, "not a popular item".
  9. Never goods that NPC vendors sell in unlimited supply (food, drink, thread, dyes, vials…), because their price can't hold above the vendor's.
  7. If there's market-price history (readings at least 30 minutes apart), the resale price can't exceed its average.
  8. If real sales are on record, the resale price can't exceed what buyers actually paid.
* **Buy** is one click when the price could be locked in ahead (see Sniping below), otherwise two. If the server's total is even 1c above what was checked, nothing is bought and the deal is removed.
* A purchase is recorded only after the server confirms it or the gold has left your bags. Chat says **Purchase confirmed** or **Purchase NOT completed**.
* The **What to look for** button on the Setup tab switches between **Vendor only** (every deal is guaranteed) and **Vendor + Flips**. In vendor-only mode no flip checks are made, so more of the search budget goes to vendor deals.

### The request limit, and how the addon spends it

Measured from real logs of this client:

* The auction house takes **one request at a time**. The server answers in about 0.15s, then the client stays locked for about 0.5s more. Floor: one request per ~0.62s, about **1.6 requests a second**, whatever the request is (category sweep, item search, next page, price quote, post).
* A search for an item whose details aren't loaded is **never transmitted**. Waiting for its answer wastes the queue.

What the addon does with that:

| Rule | Why |
|---|---|
| The next request is sent from the game's "ready" event, in the same frame | A polling timer left about 18% of the budget idle |
| No extra spacing of its own unless the server refuses requests | The client's lock is the limit; more spacing only wastes budget. A pause is added only when learned to be needed (see below) |
| The sweep asks for the whole materials class in one request | Measured in the game: 395 items came back in one request |
| The sweep interval is computed from the sweep's measured cost and the learned split (30% of the budget to start with) | 6 requests per sweep at 30% gives a radar every 13s; never more often than every 3s |
| The rest goes to confirmations, best first: vendor-price hits, then the biggest price gap weighted by how often that kind of alert was real | Each confirmation costs one request, so the most valuable one goes first |
| Items whose details aren't loaded are skipped at no cost and retried in a few seconds | Avoids the dead wait described above |
| A request the client did not transmit is dropped after 0.4s | It used to block the queue for 6s |

### The request engine learns

The server's limit can't be beaten, so the addon learns how to spend it. Everything below is measured on your realm, remembered between sessions, and shown on the **Setup** tab.

| What is learned | How | What it changes |
|---|---|---|
| The limit, per scenario | Seconds from "sent" to "server ready", kept separately for each kind of request (category read, next page, item check, more results) and for each hour of the day | The radar interval is planned with what a request costs at this hour |
| The safe pace | Requests go out the moment the server is ready. Two refusals within 50 requests add a short pause (0.10s, then 0.25s, 0.5s, 1s) | Fewer refused requests, each of which costs a 5 second stop |
| A faster pace | After 300 clean requests a shorter pause is **tried** for 30 requests. It is kept if none fails. If one fails, the next try waits twice as long | The pause never stays longer than it has to |
| Where requests pay | Every item check is scored by what asked for it: vendor-price alert, under-market alert, price-drop alert, watch list | Alerts of a kind that keeps being real are checked first |
| The split | Once a minute. Alerts waited more than 4s for a check: 5 points move from radar to checks. Nothing waited and the checks were routine: 5 points move to the radar. Radar share stays between 15% and 70% | A calm market gets a fresher radar; a busy one gets faster confirmations |
| Waste | Requests the client never sent, and answers that never came | An answer is given up after 4 times the measured cost instead of a fixed 3s |

These are fixed, bounded rules fed by measurements, not a neural network. The **Auto-adjust** button on the Setup tab freezes the pace, the split and the profit bar where they are (measuring continues); **Forget what was learned** clears it all and needs a second click.

What one radar read really costs (items returned, requests used, largest page) is also measured and shown in the radar line: "Radar: 212 items in 5 requests, re-read every 11s. limit 1.6/s."

### How it looks for deals (the radar)

The auction house offers two kinds of search, and they cost the same one request each:

* a **category search** returns the lowest price and total quantity of *every item in the category*;
* an **item search** returns the full listing of *one item*.

AuctionMesh uses the cheap, wide one as its radar and spends the narrow one only where it pays:

1. **Sweep.** It re-reads the whole crafting-materials class back to back: one request, about every 0.65 seconds. This is so whatever **What the radar reads** is set to; the other classes of a wider setting are side reads, each every 30 seconds (slower for the whole auction house, so that they never take more than a quarter of the requests).
2. **Trigger.** A full item search is queued only when the sweep shows something: the lowest price is at or under vendor price, is 20% or more under the known market price, or fell 15% or more since the last sweep.
3. **Confirm.** One item search loads the full listing and the deal rules decide.
4. **Volume for free.** A drop in an item's listed quantity between two sweeps means units were bought, so every material's trading volume is measured without extra requests.
5. **Routine.** Each of the 50 watched staples also gets one full look every 5 minutes to keep its market price current.

Compared with re-reading 50 items one by one, this covers every crafting material and uses fewer requests. It should also spot a new cheap listing within one sweep instead of one round.

The game's full-download scan (one request for the entire auction house, allowed once per 15 minutes) is not used.

### Learning from results

The addon predicts a resale price for every flip. It checks every prediction against what happened and adjusts the rules from your own results.

**What counts as a result**

* **Sold:** when you collect the sale gold, the invoice says what the buyer really paid. That is compared with the price planned at purchase.
* **Expired:** an auction that comes back unsold in the mail. The addon recognises it, puts it back on the Bags tab with what it cost you (so it can be reposted without selling at a loss), and counts the failure.

**What is adjusted** (all bounded; nothing changes before 5 results)

| Learned | Effect | Limits |
|---|---|---|
| **Price factor:** average of real sale price / planned price | If sales come in at 93% of plan, every future plan is multiplied by 0.93 | Never above 100%, never below 80% |
| **Item record** | An item that expired is not flipped again for 12 hours; 24 after two failures in a row | Up to 48 hours; a sale clears it |
| **Profit bar** | Under 70% of the last 20 flips sold: bar goes up 5 points. Over 90% sold: down 2 points | Between 12% and 50%; reconsidered once per 10 results |

The bottom of the Setup tab shows the current state, for example: "Learning from 23 finished flips: 87% of the last 20 sold, sales came in at 96% of the planned price. Profit bar: 22%."

This is scorekeeping and calibration, not a neural network. It needs finished flips to learn from, so it changes nothing at first.

### The price history database

AuctionMesh keeps a database of price history inside its own saved data (an addon can't query an outside database while you play, so this is the only place it can be used for decisions).

* **What is stored:** one record per item per hour, for 7 days: the market price read from a full live listing, and the trading volume at the time.
* **How it is used:**
  * a deal on an item whose market price fell 10% or more in about 6 hours is refused ("price is falling fast");
  * a slower decline lowers the planned resale price by the same amount;
  * a rising price changes nothing (no optimism is added).
* **Where you see it:** the MARKET column on the Trades tab shows the 24-hour change next to the price; hovering a deal shows the 6h and 24h change and the 24h range; item tooltips show the 7-day range; the drawer's **Market** view lists the biggest movers.
* **Size:** about three numbers per item-hour, only for items that have had a full reading. It is trimmed to 7 days at login.

It needs a few hours of readings before trends appear. The optional central server still stores only the latest price per item; adding history there is a possible next step if you run it.

### Where the prices come from

The game's addon API has no realm-wide sales history. It offers two real sources, and AuctionMesh uses only those:

* **The complete live listing of an item.** Before judging a deal or pricing a post, the item is searched and every page of its listing is loaded. The "market price" is read from that full listing (rule 2 above). Price history is built only from these readings, at most one per 30 minutes, never from the single lowest price seen while browsing.
* **Real sales.** When sale gold is taken from your mailbox, the sale invoice says what the buyer actually paid. That is recorded, shown in chat ("Sold: 6 x Linen Cloth at 77c each"). When a recent sale is on record, a flip's resale price can't exceed what buyers actually paid, and the deal row says "(buyers paid 77c)".

Item tooltips show all three: cheapest listing, market price from the full listing, and what buyers paid.

### Bags tab (selling)

**The most valuable way out is the recommendation.** Something bought under vendor price is not automatically sold to a vendor. For everything you hold the addon compares the two ways out with real figures:

| Way out | Figure used |
|---|---|
| Vendor | The vendor price, in your hand at once |
| Auction house | The item's live price (checked whenever the auction house is open, re-checked every 45 seconds), one step under the cheapest other seller, minus the 5% cut, and minus the posting fee on a realm where it does not come back. With the auction house closed: the item's last full listing (up to 6 hours old), or the radar's last read (up to 10 minutes old) |

The auction house is recommended when it pays at least **10% more** than the vendor; otherwise the vendor's certain gold wins. Example from a real log: Silk Cloth bought at 99c, vendor price 1s 50c, market 1s 98c. The auction house leaves 1s 87c each after the cut, so the row says **Post it**, and the drawer adds what a vendor would give right now. If a live check finds the market no better than the vendor, the row goes back to **Sell to any vendor** and the item is checked again in 10 minutes.

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
| **Sell to any vendor** | A vendor is the best way out for this item. Talk to any vendor. Nothing is sold by itself: press **Sell all to vendor** (it shows the total you'll receive) or **Sell** on a single row. Only the units you bought are sold, never copies you already owned. |
| **Post it: worth more than at a vendor** | It was bought under vendor price, but the auction house pays more (see above). Open the auction house and press **Post**. At a vendor the row says **Worth more on the auction house** and still has its own **Sell** button; **Sell all to vendor** leaves it alone. |
| **Ready to post** | Press **Post** (or **Post next**). The price is 1 step under the cheapest other seller, and never below what you paid plus the deposit plus the 5% cut. It posts everything of that item in one click. |
| **Checking the price... / Price check is next** | The live price for this item is being fetched (about a second). The **Post** button is on the row all the same: a click then asks for the price first and posts on the next click. Prices are refreshed every 45 seconds while an item waits, so this is normally only seen in the first moment after the auction house opens. (The button used to disappear whenever a price was more than 90 seconds old, while **Post next** stayed.) |
| orange text on the row | **Why the last press of Post did nothing**, shown next to the button for 4 seconds: `Getting the live price first. Press Post again in a second.`, `The auction house is busy for a moment. Keep pressing.`, `Posting: waiting for the auction house to confirm.`, `Not enough gold for the posting fee (1s 00c).`, or `Not posted. The game says: ...` with the game's own error. Post can be pressed as fast as you like: a press with no live price asks for one and no longer holds that price check back (it used to, so spamming Post could do nothing for as long as you kept pressing). The mouse resting on a button pauses nothing either. |
| **Waiting: market is below your cost** | Nothing is posted, because that would lose money. It re-checks every 10 minutes. |

The game requires one click or key press per auction. For speed, make a macro `/click AuctionMeshPostButton` and tap it. An item only leaves the list once your bags show it really went. To remove an item, click its row and press **Stop tracking this item** in the drawer. Drag an item from your bags onto the window to add it by hand.

AuctionMesh only works while its own panel is open. When you switch to the game's own auction screens it sends nothing at all, so it never changes what those screens show. Moving the mouse over the auction house window doesn't pause anything; it only waits briefly while your mouse is on a Buy or Post button, and for 8 seconds after you use one of the game's own auction buttons.

Non-stackable items (gear, recipes) are never offered as deals. They are only priced for selling.

The server has the final word on a purchase. If its quote is higher than the listing showed, nothing is bought, and the window says so. When the quote shows the cheap listings can't be bought by you (for example your own auctions), that deal is removed and doesn't come back. Your own auctions are also read from the server's "my auctions" list and never counted as deals.

The top line of the window shows the result of your last click for 10 seconds, so a click always gets a visible answer.

**The posting fee.** The game takes a fee when you list an item and gives it back when the item sells; you lose it only if the auction expires or you cancel. So AuctionMesh keeps the fee aside (it never lets you spend gold you need for posting) but doesn't subtract it from profit. It asks the game for the fee on 1 unit and on 100 units of each item, which also reveals any minimum fee per posting. `Deals.cfg.depositIsCost = true` in `Deals.lua` switches to counting the fee as lost. The first sale you collect writes an `INVOICE` line to the log showing whether the fee came back.

**Clicks are never thrown away.** If the auction house is busy when you press Buy, the click is held and sent the moment the server is free. Background work also stops while your mouse is on a Buy or Post button. Items waiting on the Bags tab are priced before anything else is checked.

### If something goes wrong

* Press **Log** on the Setup tab (the log window also has **Last session's log**, for after a reload), then Ctrl+A, Ctrl+C, and paste it to Claude. It records every auction house call, every error, and every decision (which listings a deal was based on, quotes, purchases, posts).
* To track an item the Bags tab does not show, drag it from your bags onto the panel.
* All requests go through one queue, so your clicks go first and background scanning slows down automatically after an "Internal auction error".

## What WoW lets addons do

| Question | Answer |
|---|---|
| Can an addon reach the internet? | **No.** Addon Lua has no sockets and no HTTP |
| Can it buy by itself? | **No.** Asking the server for a price needs a real input from you (a click, a wheel notch, a key). The addon can then send the purchase itself once the price is back (confirmed in the real game) |
| Can it sell by itself? | It could at a vendor, but it does not: nothing is sold or posted without your click |
| How fast can it ask the auction house? | About one request every half second; the game queues anything faster. The radar, the item checks and your purchases all share that |
| Does it talk to other players? | **No.** Since version 3.29 the addon has no communication code at all: no addon messages, no chat channel, nothing sent to a guild |

Everything you browse by hand in the game's own auction screens is also recorded in the price book.

## Optional: a price table kept outside the game

The addon itself sends nothing to anyone. The repository also holds an optional pair of Python programs (`companion/`, `server/`) that run outside the game: the companion reads the addon's saved prices from disk after a `/reload` or logout and can write a price table back as `Seed.lua`. Nothing in the addon needs them, and they are not started by it.

## Changelog

Every release, newest first, is in [CHANGELOG.md](CHANGELOG.md).

## Install & use

1. Copy the `AuctionMesh` folder into `World of Warcraft/_forever_/Interface/AddOns/`. The folder name may differ on your install; it's the one Auctioneer lives in.
2. Open the auction house. The panel opens and price reading starts by itself. Price lines also show up in item tooltips.

There are no commands to remember. The panel opens with the auction house; elsewhere, click AuctionMesh in the game's addon list next to the minimap. Everything that can be changed is a control on the **Setup** tab.

## Tests

```bash
lua5.1 tests/ui_smoke.lua      # whole addon against a fake game client: scan, buy, mail, vendor, post
lua5.1 tests/deals_test.lua    # deal rules, posting prices, price history
lua5.1 tests/purchase_test.lua # purchase confirmation + mailbox check
lua5.1 tests/seller_test.lua   # posting / vendor safety
lua5.1 tests/tuner_test.lua    # request-budget learner: limit, pace trials, split
lua5.1 tests/journal_test.lua  # trade journal: purchase to sale, partial sales, expiry, totals
lua5.1 tests/scout_test.lua    # opportunity counts, prime items, laser focus, focus codes, daily report
python3 tests/test_server.py  # companion ↔ server ↔ Seed.lua round trip
```

## Known limits / to verify in game

* **Confirmed in the real game so far** (from logs): one-click buying, buying with the mouse wheel, the radar reads, posting, the mailbox and the import code. **Not yet tried in the real game:** buying with a key (tap or hold), the stake-out, the vendor-or-auction-house recommendation, the Cancel button and the new recognition of returned auctions in the mailbox. The Picks tab is arithmetic on recorded deals; its advice is only as good as that record, and the stake-out it points to is itself still unproven in the real game. Holding a key relies on the game repeating typed characters and accepting them as inputs for buying; if the game refuses, that mode switches itself off and says so.
* **The request engine's learning is tested with a fake clock only.** The rules (pause steps, trial lengths, split limits) are sensible starting values, not values proven on a live realm. The Setup tab shows what it actually measured; the log has a `TUNER` line for every change it makes.
* **Prime items use starting thresholds** (30 sold an hour, 10 minutes of watching, top 12). They are meant to be adjusted from the daily reports.
* **The two "Sold" lines** rely on the game's sale invoices (`seller_temp_invoice` with its arrival time). If this realm delivers sale gold with no delay, "still on its way" simply stays empty.
* If the client blocks automatic `SendBrowseQuery` (an `ADDON_ACTION_BLOCKED` message appears), automatic price reading will not work on this client; tell me and I'll add a button for it.
* While the radar runs, it uses the AH browse list, so don't browse by hand at the same time.
* The sniper never buys by itself. Every purchase is your click, which the game requires anyway. Check the numbers on expensive buys.
* **Deposits** are counted as a cost, since you lose them if an item doesn't sell. The amount comes from the game's own deposit calculation where that's available. Otherwise it's estimated at 15% of the vendor price, then replaced with the real figure after your first post of that item. Until an item's details have loaded, it's never treated as an AH flip.
* Prices are stored per item ID, so different item levels of the same gear collapse into the cheapest one. Battle pets are stored per species.

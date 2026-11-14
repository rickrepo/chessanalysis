# AuctionMesh

AuctionMesh is a WoW Forever addon (Midnight retail client, interface 16001) that lets a group of friends share auction house prices in real time and split the scanning work between them. It also includes a simple **sniper** that lists only the deals you can afford right now.

## How to use it

Open the auction house. The panel opens inside the auction house window and price reading starts by itself. It has three tabs and a bar at the top right.

```
 [ Trades ] [ Bags ] [ Setup ]              [#########------]
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
* **Bags** is what you hold and the one thing to do with each item: post it, sell it to a vendor, collect it from the mailbox, or wait.
* **Setup** has a control for every setting, and what the request engine has learned. No chat commands are needed.
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

### Details: the drawer on the right

A slim **DETAILS** handle sits on the panel's right edge. Clicking it slides a second panel out to the right (click again to hide it). The mouse wheel scrolls it.

```
 ALL TRADES
 Bought so far                              3 trades, 2s 76c spent
 Finished / still open                                      2 / 1
 Profit made on what has sold                           + 3s 43c
 Profit if everything open sells                        + 3s 18c
 OPEN (1)
 Linen Cloth x6                                         9 min ago
 Bought at 20c each                                     - 1s 20c
 On the auction house: 6 at 77c each                    + 4s 38c
 Profit if this sells                                   + 3s 18c
 DO    Someone lists at 70c. Cancel yours (the game's Auctions
       tab) and post again at 69c: still + 2s 70c. The posting
       fee is paid again.
 FINISHED (2)
 Copper Ore x12                                        23 min ago
 Bought at 3c each                                          - 36c
 Sold 12 to a vendor at 5c each                             + 60c
 Profit made                                                + 24c
```

* **Every purchase is one trade**, followed to its end: bought, listed (at what price), sold (what the buyer really paid, from the sale invoice), sold to a vendor, expired, or removed. Two purchases of the same item are matched oldest first.
* **Profit made** is only on units that have actually sold. **Profit if this sells** is what the rest brings at the listed or live price, after the cut.
* **One recommendation per open trade**, marked `DO` (act now), `WAIT` or `CHECK`:

| Where the item is | Recommendation |
|---|---|
| In the mailbox | Visit a mailbox to collect it |
| In your bags, vendor deal | Sell to any vendor, with the guaranteed profit |
| In your bags, flip, price checked | Post N at the live price, with the profit after the cut and how many sell an hour |
| In your bags, market below your cost | Hold: what selling under the cheapest listing would lose, and the 24h price change |
| Listed, nobody cheaper | Wait, with how many sell an hour and when the auction runs out |
| Listed, undercut by 3% or less | Wait: the cheaper units sell first |
| Listed, undercut by more, repost still clears your minimum profit | Cancel and post again at 1c under, with the profit that leaves. The posting fee is paid again |
| Listed, undercut by more, repost not worth it | Wait: says what going under would leave |
| No longer listed | Sold (invoice seen, gold on its way), or "sold or expired, a mailbox visit tells which" |

* The drawer has three views, **Trades | Activity | Market**. Activity is the log of everything that happened to your gold and items; Market lists the biggest 24-hour price moves and what sells fastest.
* The Market view starts with the **prime items** (see Laser focus below).
* **Click any item row** in the main panel and the drawer shows that item alone: cheapest listing and its age, market price from the full listing, 24h change, units sold per hour, what buyers really paid, vendor price, why the last check was or wasn't a deal, then your trades in it. **Trades** goes back.

The addon never cancels an auction itself; a "cancel and post again" recommendation is something you do in the game's own Auctions tab.

### Setup: every control in one place

Nothing has to be typed in chat. The Setup tab has a control for everything that can be changed, each showing its current value:

| Control | What it does |
|---|---|
| Smallest profit worth showing a deal for | Two boxes, silver and copper. Smaller deals are hidden |
| Profit a flip must leave after the auction house cut | A percentage box. Self-tuning nudges it from how trades turn out |
| What to look for | Vendor deals + flips, or vendor deals only (every deal guaranteed) |
| What the radar reads | Click to change: crafting materials (fastest), all money-makers, whole auction house |
| Laser focus | Click to change: off, prime items (picked from measured activity), or my own list |
| Focus code | A box and **Apply**, for a code you were given (see below) |
| The panel | Inside the auction house window or a window of its own; opens by itself on or off |
| Share prices with friends | Channel name, password, **Join**; or **Use my guild**. The line underneath says who you are connected to |
| Self-tuning | One switch for the pace, the split of requests and the profit bar. **Forget what was learned** needs a second click |
| Share with Claude | **Daily report** (once a day), **Log** and **Last session's log** (when something looks wrong), **Rebuild from purchases** |

Hovering a button explains it. Below the controls is everything the request engine has learned.

To track an item you bought some other way, drag it from your bags onto the panel.

### Laser focus: only where money moves fast

The addon counts what it sees, per item, and keeps the counts between sessions: how many units sell an hour (from quantity leaving the listing between radar reads), how much gold that is, how often the cheapest listing is 20% or more under the market, how many deals were confirmed, and how long deals lasted before someone else took them.

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

One limit of the measurement: units leaving a listing are counted as sold. A seller cancelling an auction looks the same, so "sells an hour" can be somewhat high.

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

* An auction you post is shown on the Trades tab under **LISTED** with its quantity, cost, your price and expected profit. It moves under **STUCK LISTINGS** when the latest radar read saw someone cheaper, and under **ENDED, CHECK A MAILBOX** when it is no longer among your auctions.
* **Banked so far** (bottom of the Trades tab) is profit actually made: vendor sales, plus auction sales once you collect the gold (sale price minus the auction house cut minus what you paid).

### Recent activity (drawer, Activity view)

Everything that happened to your gold and items, newest first: "Bought: 7 x … for 1s 40c", "Collected from mailbox: 7 x … is now in your bags", "Posted 1x Wool Cloth at 1s 60c", "Sold: …", and purchases that did not complete.

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
* **Buy** asks the server for the real total; then you press **Confirm**. If the total is even 1c above what was checked, the purchase is cancelled and the deal is re-checked.
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
| The sweep asks for the whole materials class in one request | Asking per sub-category returns the same items for about 12 requests |
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
| Where requests pay | Every item check is scored by what asked for it: vendor-price alert, under-market alert, price-drop alert, friend's hint, watch list | Alerts of a kind that keeps being real are checked first |
| The split | Once a minute. Alerts waited more than 4s for a check: 5 points move from radar to checks. Nothing waited and the checks were routine: 5 points move to the radar. Radar share stays between 15% and 70% | A calm market gets a fresher radar; a busy one gets faster confirmations |
| Waste | Requests the client never sent, and answers that never came | An answer is given up after 4 times the measured cost instead of a fixed 3s |

With friends connected, the measured figures are sent on the channel every 10 minutes at most. A friend who has just installed the addon starts from them and then measures for themselves.

These are fixed, bounded rules fed by measurements, not a neural network. The **Self-tuning** button on the Setup tab freezes the pace, the split and the profit bar where they are (measuring continues); **Forget what was learned** clears it all and needs a second click.

What one radar read really costs (items returned, requests used, largest page) is also measured and shown in the radar line: "Radar: 212 items in 5 requests, re-read every 11s. limit 1.6/s."

### How it looks for deals (the radar)

The auction house offers two kinds of search, and they cost the same one request each:

* a **category search** returns the lowest price and total quantity of *every item in the category*;
* an **item search** returns the full listing of *one item*.

AuctionMesh uses the cheap, wide one as its radar and spends the narrow one only where it pays:

1. **Sweep.** It re-reads the whole crafting-materials class every 8 to 20 seconds (the interval follows the sweep's measured cost).
2. **Trigger.** A full item search is queued only when the sweep shows something: the lowest price is at or under vendor price, is 20% or more under the known market price, or fell 15% or more since the last sweep.
3. **Confirm.** One item search loads the full listing and the deal rules decide.
4. **Volume for free.** A drop in an item's listed quantity between two sweeps means units were bought, so every material's trading volume is measured without extra requests.
5. **Routine.** Each of the 50 watched staples also gets one full look every 5 minutes to keep its market price current.

Compared with re-reading 50 items one by one, this covers every crafting material and uses fewer requests. It should also spot a new cheap listing within one sweep instead of one round. With friends on the same channel the sweep is shared: each category is read by one of you.

The game's full-download scan (one request for the entire auction house, allowed once per 15 minutes) is not used.

### Sharing with other players, live

Everyone running AuctionMesh on the same hidden channel (or in the same guild) is one network. Nothing extra to set up beyond typing the same channel name and password into the Setup tab once per person. What travels between you, within a second or two:

| Shared | What it does for you |
|---|---|
| Lowest price and quantity of every item a friend's sweep sees | **Shared radar:** a friend's sweep triggers a deal check on your side, without you spending a sweep on it |
| Which category each of you is sweeping | The sweep is split: each category is read by one of you |
| Market prices from full readings | Fills everyone's price history database |
| Real sale prices from invoices | Everyone knows what buyers actually paid |
| "Deal here I can't afford" hints | A friend with more gold gets it checked immediately |
| Price history (6h, 24h, 3 days, 7 days back) when someone logs in | A newcomer has trends straight away |
| A presence signal every few minutes | The radar line shows "Sharing live with N other players" (or says nobody is connected) |

Limit set by the game: each player can send about one hidden message a second, so this carries prices and signals, not bulk data.

### Learning from results, together

The addon predicts a resale price for every flip. It now checks every prediction against what happened, and everyone on your channel shares those results, so the rules are tuned on the whole group's trades.

**What counts as a result**

* **Sold:** when you collect the sale gold, the invoice says what the buyer really paid. That is compared with the price planned at purchase.
* **Expired:** an auction that comes back unsold in the mail. The addon recognises it, puts it back on the Bags tab with what it cost you (so it can be reposted without selling at a loss), and counts the failure.

**What is adjusted** (all bounded; nothing changes before 5 results)

| Learned | Effect | Limits |
|---|---|---|
| **Price factor:** average of real sale price / planned price | If sales come in at 93% of plan, every future plan is multiplied by 0.93 | Never above 100%, never below 80% |
| **Item record** | An item that expired is not flipped again for 12 hours; 24 after two failures in a row | Up to 48 hours; a sale clears it |
| **Profit bar** | Under 70% of the last 20 flips sold: bar goes up 5 points. Over 90% sold: down 2 points | Between 12% and 50%; reconsidered once per 10 results |

The bottom of the Setup tab shows the current state, for example: "Learning from 23 finished flips (9 yours, 14 from friends): 87% of the last 20 sold, sales came in at 96% of the planned price. Profit bar: 22%."

This is scorekeeping and calibration, not a neural network. It needs finished flips to learn from, so it changes nothing at first, and it learns faster the more people on the channel are trading.

### The price history database

AuctionMesh keeps a database of price history inside its own saved data (an addon can't query an outside database while you play, so this is the only place it can be used for decisions).

* **What is stored:** one record per item per hour, for 7 days: the market price read from a full live listing, and the trading volume at the time. Readings shared by friends on your channel are recorded too, so the database fills faster with more people.
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
* **Real sales.** When sale gold is taken from your mailbox, the sale invoice says what the buyer actually paid. That is recorded, shown in chat ("Sold: 6 x Linen Cloth at 77c each"), and shared with your friends. When a recent sale is on record, a flip's resale price can't exceed what buyers actually paid, and the deal row says "(buyers paid 77c)".

Item tooltips show all three: cheapest listing, market price from the full listing, and what buyers paid.

### Bags tab (selling)

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

**Clicks are never thrown away.** If the auction house is busy when you press Buy, the click is held and sent the moment the server is free. Background work also stops while your mouse is on a Buy or Post button. Items waiting on the Bags tab are priced before anything else is checked.

### If something goes wrong

* Press **Log** on the Setup tab, then Ctrl+A, Ctrl+C, and paste it to Claude. It records every auction house call, every error, and every decision (which listings a deal was based on, quotes, purchases, posts).
* **Rebuild from purchases** on the Setup tab rebuilds the Bags list from your purchase log. To track anything else, drag it from your bags onto the panel.
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

Scanning starts automatically when the AH opens:

1. The AH is split into about 100 work units, one per item class or subclass (Herbs, Ore, Cloth, Potions, Plate…).
2. Each friend claims the **stalest unclaimed** unit and browses it. One `SendBrowseQuery` returns the lowest price and listed quantity of every item in that category. When it's finished, the friend marks it done and the prices go out over the mesh.
3. Every player has their **own** query throttle, so the swarm scales with the number of people. Faster players automatically claim more units.
4. Units that anyone scanned in the last 5 minutes are skipped. When everything is fresh, the swarm waits, so you get a continuous rolling scan instead of one big scan every 15 minutes.

Simulated speedup (100 categories, 1 query per second per player, 1 to 3 pages each): **1 player 212 s → 4 players 53 s → 8 players 29 s**, with no duplicated queries.


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
2. Everyone in the group opens the **Setup** tab once, types the same channel name and password into the two boxes and presses **Join**. Or press **Use my guild** to share with guild members instead.
3. Open the AH. The window opens and scanning starts by itself. Price lines also show up in item tooltips.

There are no commands to remember. The panel opens with the auction house; elsewhere, click AuctionMesh in the game's addon list next to the minimap. Everything that can be changed is a control on the **Setup** tab.

## Tests

```bash
lua5.1 tests/ui_smoke.lua      # whole addon against a fake game client: scan, buy, mail, vendor, post
lua5.1 tests/deals_test.lua    # deal rules, posting prices, price history
lua5.1 tests/purchase_test.lua # purchase confirmation + mailbox check
lua5.1 tests/seller_test.lua   # posting / vendor safety
lua5.1 tests/sim.lua           # multi-player network simulator
lua5.1 tests/tuner_test.lua    # request-budget learner: limit, pace trials, split, sharing
lua5.1 tests/journal_test.lua  # trade journal: purchase to sale, partial sales, expiry, totals
lua5.1 tests/scout_test.lua    # opportunity counts, prime items, laser focus, focus codes, daily report
python3 tests/test_server.py  # companion ↔ server ↔ Seed.lua round trip
```

## Known limits / to verify in game

* **Not yet run in the real client.** The protocol logic is tested offline against stubbed WoW APIs. The AH calls follow the retail `C_AuctionHouse` API, which Auctioneer's Forever build also uses.
* **The request engine's learning is tested with a fake clock only.** The rules (pause steps, trial lengths, split limits) are sensible starting values, not values proven on a live realm. The Setup tab shows what it actually measured; the log has a `TUNER` line for every change it makes.
* **Prime items use starting thresholds** (30 sold an hour, 10 minutes of watching, top 12). They are meant to be adjusted from the daily reports.
* **The two "Sold" lines** rely on the game's sale invoices (`seller_temp_invoice` with its arrival time). If this realm delivers sale gold with no delay, "still on its way" simply stays empty.
* If the client blocks automatic `SendBrowseQuery` (an `ADDON_ACTION_BLOCKED` message appears), automatic price reading will not work on this client; tell me and I'll add a button for it.
* While the swarm runs, it uses the AH browse list, so don't browse by hand at the same time.
* The sniper never buys by itself. Every purchase is your click, which the game requires anyway. Check the numbers on expensive buys.
* **Deposits** are counted as a cost, since you lose them if an item doesn't sell. The amount comes from the game's own deposit calculation where that's available. Otherwise it's estimated at 15% of the vendor price, then replaced with the real figure after your first post of that item. Until an item's details have loaded, it's never treated as an AH flip.
* Prices are stored per item ID, so different item levels of the same gear collapse into the cheapest one. Battle pets are stored per species.
* Midnight blocks addon messages in some instanced or combat situations. Sends are paused in combat and retried automatically.
* Anyone on the channel can send data, so only share the channel password with people you trust.

# AuctionMesh changelog

Newest first. Every release passed the offline test suites before it was sent. "Confirmed in game" marks something a real log from the realm has since shown working; everything else is untested in the real game until a log says otherwise.

To install any version: delete the old `AuctionMesh` folder, unzip the new one into `Interface/AddOns`, and `/reload`. The Setup tab's heading shows the installed version.

---

## 3.66.1 (2026-11-26)

- **An alert whose check was lost is asked again.** In a real log the radar saw an item at vendor price; its check went out right after a refused purchase, came back as an error with no data, and was logged as "skipped". That price was never looked at. A lost check of an alert (vendor price, under market, price drop) is now asked again at once, ahead of what is waiting. Once in ten seconds per item; routine checks are not repeated.
- Not confirmed in game: only run in the offline tests.

## 3.66.0 (2026-11-23)

- **SPEED, in numbers, on the Buy tab.** Two lines under the snipe box, measured over the last 60 seconds:
  - `SPEED 100%  last 60s: lock unused 0.0s, radar reads lost 0, held for a deal 6.1s`
  - `Requests 113: radar 104, alert checks 4, buying 3, upkeep 2. The game's lock: 0.52s a request.`
- **What the numbers are.** The game takes one request at a time and keeps its lock shut for a fixed time after each answer; no addon can send sooner. What the addon can lose is what is measured:
  - **lock unused**: seconds the lock was open and the next request had not left yet (from the game's "ready" to the next "sent"). Should be 0.0s.
  - **radar reads lost**: reads that got no answer. Should be 0.
  - **held for a deal**: seconds the lock was left open on purpose because a deal was on screen or a purchase was in progress, so that your press goes first. Not counted against the speed.
  - **SPEED** = the share of the time (without what was held) that was neither unused nor spent on a lost read. 100% is the most the game allows. Green from 99%, gold from 95%, red below; a figure that is off is orange.
  - **Requests**: how many went to the radar and how many to anything else. Every request that is not a radar read costs one radar read.
- The same figures go into the log once a minute (`SPEED ...`) and into the Snapshot.
- **After a refused purchase the radar no longer loses a read.** In a real log two radar reads got no answer, each right after a failed try, each costing about half a second with no radar. Both had been sent 0.13s and 0.25s after the request before them: after an answer that is an error the game reports "ready" at once instead of after its usual 0.40s, and the read sent then came back as an error with no data. Background requests now wait out the usual time after an error as well (measured, less a 10% margin); your own purchases are not held by this. *That the server refuses a request for coming too soon is an inference from those two reads. "radar reads lost" on the SPEED line shows whether it holds.*
- The lock is now also measured from the answer (it opened 0.40s after each answer in that log, 0.52s after the request was sent).
- The status line no longer names the alert being checked; that is in the log.
- Not confirmed in game: only run in the offline tests.

## 3.65.0 (2026-11-23)

- **Cancelling one undercut auction no longer takes the Cancel buttons off the others.** Fixed in three places:
  - A list of your auctions that is suddenly empty (or that the game marks as incomplete) is no longer believed at once. It is asked for again, and the answer to the addon's own request is what counts. Before, an empty list right after a cancel made every other auction look ended: they left UNDERCUT, lost their buttons and showed up under "ended, check a mailbox". *That the game sends such a list after a cancel is an inference from what you described, not something seen in a log; the offline test reproduces it and the fix holds there.*
  - On the Sell tab your auctions are read again at once after a cancel, also while a deal is on screen (before, the read waited until no deal was shown). On the Buy tab deals still come first.
  - The Cancel button is on every undercut row while the auction house is open. If the addon has no auction on record for it, a click reads your auctions first and says so; the next click cancels. It no longer needs a fresh radar price to appear.
- **P / L on an undercut row is the profit of the advised choice, with every lost fee in it.** For RELIST: the units at the relist price after the cut, less what they cost, less the fee of this auction that the cancel loses (and a new fee for each time it would run out again). For HOLD: at your price, less a fee for each time it runs out before it sells. Where posting fees never come back, the fee already paid and the new one are both taken off. Example (30 units, cost 40c, listed at 1s00c, relist at 89c, fee 30c): the row said + 16s50c whatever the advice; with RELIST it now says + 12s90c. The cost of waiting decides between the two but is not gold lost, so it is not in this figure. When it cannot be worked out (no sale rate yet) the plain figure is shown in grey. The mouse-over text adds "Following it leaves you + 12s90c, after 30c in fees lost."
- **"Ended, check a mailbox" is on the Sold tab**, between what is on its way and what was paid. The Sell tab only has what is still to sell.
- **Farmed items are under TO POST with everything else.** No separate "FARMED, TO POST" section: the COST column says `farmed`. Farmed stays apart where results are added up (the footer, the record of trades).
- **The Sold tab has a SPREAD column**: what it sold at over what it cost (the same figure as SPREAD on the Buy tab), `all profit` for farmed. Click SPREAD to sort by it (widest first, farmed on top; click again for narrowest first). The quantity moved into the name (`x10`) to make room.
- **The "input every N ms" figure follows your pressing again.** No fault was found in the counting: the figure was the average of the last four seconds and was redrawn every 0.6 seconds, so pressing faster or slower hardly moved it. It is now the last second of inputs, brought up to date five times a second while you press (only that line, not the panel).
- Not confirmed in game: only run in the offline tests.

## 3.64.0 (2026-11-23)

- **Relist or hold is now worked out, not ruled.** The advice on an undercut auction was a list of rules with thresholds in them ("within the hour", "a quarter of the profit", "half of it"). It is now one sum, the same for every auction: each choice is given a value in copper, and the larger one is the advice.
  - **HOLD** = keep your price until it sells. The cheaper units go first, then yours. If that takes longer than the auction still runs, it comes back and is posted again at your price, one fee lost each time. Value: your units x (your price after the cut - cost) - those fees - the cost of the wait.
  - **RELIST** = cancel and post at the relist price now. The fee you paid is lost; yours are first in line. Value: your units x (that price after the cut - cost) - the fee - the cost of the wait.
  - **The cost of the wait** = what your gold earns an hour x the gold x the hours until it is sold.
- **What it is worked out from (all measured):** the units listed under yours; how fast they go (at first the item's measured sale rate; once the listing has been read twice, how fast the units ahead of you really went down, which has the people who keep undercutting in it); the hours your auction has left; the relist price; the fees; the item's price change over 24 hours (your price is counted lower by the time your turn comes if it is falling); and **what your gold earns an hour**: the profit of the flips you finished in the last 7 days, over all you have, per hour. Until five flips are finished that is zero and the wait is not charged for.
- **If the units ahead of you are not going down** (as many are listed under you as are bought), holding never sells: RELIST, if a relist pays.
- **Equal values:** the choice that has your gold sooner.
- **Two worked examples** (30 units at 1s00c, cost 40c, 60 cheaper units ahead, relist price 89c, fee 30c):
  - 120 sell an hour: hold = 30 x 55c = 16s50c; relist = 30 x 44c - 30c = 12s90c. **HOLD**, worth 3s60c more.
  - 20 sell an hour and your gold earns 6% an hour: hold = 16s50c - 6s41c of waiting = 10s09c; relist = 12s90c - 1s13c = 11s77c. **RELIST**, worth 1s68c more.
- The row says what the sum came to (`holding is worth 3s60c more`, `relist is worth 1s68c more`, `the queue is not moving; relist is worth 12s90c`); the two sums are behind the mouse and in the log. A hold still counts down to when your first unit should sell, and when that time is up the listing is read again and the sum is done afresh. Cancel still overrules it.
- **What the sum assumes**, since no sum is better than that: buyers take the cheapest units first; the item keeps selling at the measured rate; once the cheaper units are gone your price is the cheapest again (new undercutters only show up in the sum after the listing has been read twice); a falling price keeps falling at the same pace.
- Not confirmed in game: only run in the offline tests.

## 3.63.0 (2026-11-23)

- **The tabs are Buy, Sell, Sold, Chart, More.** Trades is now **Buy**, Bags is **Sell**, Gold is **Chart**, and what has sold has its own tab.
- **The Sold tab.** Two lists: **SOLD, GOLD ON ITS WAY** (auctions the auction house lists as sold and not paid out yet: quantity, cost, what it sold at, when its gold arrives, profit) and **PAID, LAST 24 HOURS** (sales whose gold you have collected). The tab's label counts what is on its way (`Sold (12)`), and the line at the top adds up the gold coming and the profit on what was paid. The Sell tab no longer has a sold section.
- **Sort by any column.** Click a column's name in a heading (PROFIT, SPREAD, VOLUME, COST, P / L, GOLD ARRIVES, and so on) to sort that tab by it, largest first; click again to turn it round; click the heading's name for the usual order. The sorted column is marked `v` or `^`. Works on Buy, Sell and Sold. On the Sell tab a click on a section's name still opens and folds it. Sorting changes what is shown and nothing else: which deal a press buys is still the sniper's choice.
- **The chart's ranges: hours and days, and Auto.** A row of buttons: `Auto 1h 3h 6h 12h 1d 2d 7d 30d`. **Auto** (the default) grows with what is on record: the shortest range that holds all of it, so an hour at first, then 3, 6, 12 hours, a day, and on up to 30 days. Picking a range keeps it. The range buttons are on their own row now, so the figures at the top have the whole width.
- **Relist advice: everything a relist costs is spelled out, and all of it is in the figure.** The full advice (mouse on the row) now ends with, for example: `relisted at 89c it leaves + 12s90c against + 16s50c if it sells where it is. What a relist costs, all counted in that: 11c less on each of the 30 (after the 5% cut); the 30c fee paid for this auction is lost with the cancel; a new fee of 30c is paid first: it comes back when it sells, and is lost too if that auction runs out.` On a realm where posting fees never come back, the new fee is the cost and is counted instead.
- Not confirmed in game: only run in the offline tests. In particular, sorting by a click needs the game to say where the mouse is; that part has only run against a stand-in.

## 3.62.0 (2026-11-23)

- **A relist is never advised when it throws the profit away.** Two of the rules could say RELIST for any relist that left anything at all: "it will not sell before it runs out", and the end of a timed hold. An auction that makes 1g51s where it is could be sent down to a price that left a few silver. Now, whatever rule says "relist", it is only said if the relist keeps at least half of what the auction makes where it is (or gives up no more than the smallest profit you bother with). Otherwise the advice is HOLD: `the price has dropped: a relist at 59c would give up 12s of the 16s50c it makes where it is. It may come back unsold: post it again then`.
- **Every piece of advice is in the log** when it changes for an item, with the figures it came from: `ADVICE 6522: HOLD (...) | yours 59 at 838, cost 540 | 120 cheaper ahead, cheapest 600, others' mean 790 | sells 40 an hour | 9 hours left | hold makes 15104, relist at 599 makes 1711`. A question like "why did this figure change" can then be answered from the log.
- About the Deviate Fish question that prompted this: the log that was sent has no line about that item, so whether a bug lowered its figure is not known. This version closes the one way the advice itself could have led to a low relist price; it is not confirmed as the cause.
- Not confirmed in game: only run in the offline tests.

## 3.61.0 (2026-11-23)

- **Requests follow the tab.**
  - **Bags tab (selling):** while selling has anything to read (a price for something to post, the listing of an undercut auction), every request goes to that, until it is all in. It was every other request. Once everything is read the radar ticks over again, so a deal still shows in the Trades tab's label.
  - **Trades tab (buying):** nothing is read for selling at all. Prices of what you hold used to be refreshed there every ten minutes; those requests go to the radar now. (One exception: with "One key: buys and posts" the key also posts from the Trades tab, so prices are still read there in that mode.)
- **The advice on an undercut auction is clearer, and says how to overrule it.**
  - **The reason is on the row itself**, in a few words where the cost and market columns are on other rows: `60 cheaper units ahead, 120 sell an hour`, `sells next for 7c less (or wait 3 hours)`, `will not sell in the 2 hours it has left`. The whole advice with its figures is still behind the mouse.
  - **You can always overrule it.** The Cancel button is on the row whatever the advice says: press it to relist something the addon would hold; leave it alone to keep something it would relist. The full advice now ends with `Your call: Cancel on this row relists it anyway.`
  - **A small amount is not worth a wait.** The rule held an auction when relisting gave up more than a quarter of its profit, however little that was: something that makes 20c could be held for hours over 7c. Now it also relists when what is given up is no more than the smallest profit you bother with (the "sniping for" figure).
- **A hold with a time counts down**, on the row: `HOLD 29:58`, `HOLD 0:42`. When the time is up the listing is read again by itself. Nobody cheaper any more: it is simply listed. Still undercut: the wait did not work, and the advice becomes `RELIST` (`still undercut after 30 min: relist`), provided a relist still pays and you have the fee.
- **The marks on the Gold chart are small diamonds** (they were 11-pixel squares).
- Not confirmed in game: only run in the offline tests.

## 3.60.0 (2026-11-23)

- **An undercut auction now comes with advice: RELIST or HOLD**, on its row on the Bags tab (the section is called UNDERCUT; its ADVICE column shows the word, and the mouse on the row gives the whole advice with its figures). It is worked out from what is measured:
  - **the other listings:** how many units other people list for less than yours, and the cheapest of them (from the item's listing as last read in full; yours are not counted);
  - **the activity:** how many of the item sell an hour (measured by watching it), so how long until the cheaper units are gone and it is your turn;
  - **the mean:** the mean price of what others ask, and what buyers really paid in the last 48 hours, next to your price;
  - **the time left** on your auction;
  - **what relisting brings and costs:** the price it would be posted at now, what that leaves after the cut, and the posting fee that is lost with the cancel.
- **The rule, in this order:**
  1. no sale rate measured yet: HOLD (nothing says a relist would sell sooner);
  2. your turn comes within the hour: HOLD (it sells anyway, for more), shown as `HOLD 30m`;
  3. relisting would leave nothing: HOLD (it comes back by mail if it runs out);
  4. not enough gold for the new posting fee: HOLD;
  5. it will not sell before it runs out: RELIST;
  6. relisting gives up a quarter of the profit or less: RELIST (it sells next, for a little less);
  7. otherwise: HOLD (the wait is worth it).
- An example of what it says: `RELIST at 89c: it sells next, for only 3s60c less than waiting 3 hours. Press Cancel on this row (twice), collect it at a mailbox, and post it again. The figures: 60 cheaper units ahead of yours, the cheapest at 90c; about 20 sell an hour, so your turn comes in about 3 hours; your auction runs 10 hours more; others ask 1s06c on average; yours is at 1s00c; relisted at 89c it leaves + 12s90c (the posting fee of 30c is lost with the cancel) against + 16s50c if it sells where it is.`
- The UNDERCUT heading counts the advice (`relist 2, hold 5`), auctions to relist are listed first, and the Cancel button stands out only where the advice is to relist. Nothing is cancelled or posted by the addon: the advice is words, the clicks are yours.
- The listing an advice needs is read on the Bags tab, in the turns that already go to prices there (one read an item, again after 15 minutes). Until it is in, the row says `READING`. Nothing changes on the Trades tab.
- The "one hour" and "a quarter" in the rule are my choices, not measurements; say so if they should be different.
- Not confirmed in game: only run in the offline tests.

## 3.59.0 (2026-11-23)

From a real screenshot of the Gold tab on 3.58.

- **Confirmed in game: the true line works on this client.**
- **Squares only where the line visibly moves.** The chart had red squares for posting fees of 4c and 2c on a line at 15g: marks for dips that cannot be seen. A change is now marked only if it is at least a fiftieth of the height drawn. Smaller ones are still in the list under the chart.
- **Sale gold collected at the mailbox no longer looks like new money at the start of a session.** That chart showed `+ 9g33s, not seen by the addon as it happened`: gold from auctions that had sold earlier, collected at the mailbox before the auction house had been opened, when the addon did not yet know they had sold. What has sold is now also known from the last look into the mailbox, which is kept across reloads, so those sales are already counted as cash and collecting them changes nothing. (The jump already on your chart stays there: it is in the record.)
- Not confirmed in game: these two corrections.

## 3.58.0 (2026-11-23)

- **The Gold chart's line is a true line.** It was pieced together from small rectangles, which is why it went up and down in blocks. It is now drawn with the game's own line segments, one from each point to the next: level where your cash does not change, sloping from the old amount to the new one where it does, in one unbroken line. The area under it is still filled.
- **If this client cannot draw lines**, or its lines fail when used, the chart goes back to the block drawing by itself and says so once in the log (`GOLD CHART: line segments are not usable on this client`). It never stops drawing.
- Worth knowing: your cash changes in jumps (a purchase, a sale) and sits still in between, so the line will always have level stretches joined by steep slopes. That is the data, not the drawing.
- Not confirmed in game: whether this client's line segments work is exactly what has not been seen yet. A screenshot of the Gold tab will show it.

## 3.57.0 (2026-11-23)

From four real screenshots.

- **The Gold chart charts your CASH: gold in hand plus what has sold.** It charted gold in hand alone, so a session of buying flips read `- 62%` while over ten gold of sales were on their way. An auction that has sold is as good as cash; only what is listed and has not sold is tied up. Now:
  - buying takes the line down by what you paid; a sale brings it up by what the buyer paid, the moment the auction house lists it as sold; collecting the gold from the mailbox changes nothing (it only moves from "sold" to "in hand");
  - the large figure is that cash, and the line under it says what it is made of: `Cash = in hand 3g85s + sold 10g50s      Not sold yet: 7g68s listed, 33s in your bags`;
  - new sales are named on the chart (`Sold 20 x Runecloth (auction)`) when the list of your auctions is read;
  - the record starts again with this version (the old one was of gold in hand, a different thing), and begins once the sold amount is known, so it cannot start too low.
- **Fixed: text at the top of the chart ran under the range buttons.** It ends where they begin now, and reads `since 23:48` (the longer wording is gone).
- **The money breakdown is back on the Trades tab**, always there, as it was before 3.54: gold in hand, sold (in the mailbox, on its way), listed, in your bags, and the total. The line saying what is being sniped stays above it.
- **The Bags tab with many auctions:**
  - **A scroll bar** at the right edge of the list (drag it; the mouse wheel still scrolls, three rows a notch).
  - **Sold and listed auctions fold into one line each**: `[+] SOLD, GOLD ON ITS WAY (12)   + 9g50s coming, the next in 14 min` and `[+] LISTED (14)   nobody is cheaper: + 7g68s if they sell`. Click a heading to open or fold its section; it is remembered. Stuck listings stay open (they need a decision).
  - **What you can act on comes first**: to post, to sell, to collect, then "in your bags, not tracked" (Add), then stuck listings, then the folded ones.
  - Headings are short (they were printed over their own column titles), the footer is no longer cut off, and the status lines do not repeat how many auctions are listed.
- **The More tab:** a message could be printed over the page buttons; it has its own line under them now. The rows have room between them (the buttons used to touch), and the footer is shown in full.
- Not confirmed in game: only run in the offline tests.

## 3.56.0 (2026-11-23)

- **The Gold chart begins where your record begins.** A real screenshot showed why it looked wrong: with 25 minutes on record and "2 days" picked, the chart was two days of empty space with everything squeezed into the last sliver. Now, when there is less on record than the range asked for, the chart shows what there is across its whole width (never less than ten minutes), the times along the bottom are spaced to fit (every 5 minutes, 15 minutes, hour and so on), the marks sit along the line where each change happened, and the change at the top reads `since 23:40 (recording began then)` in place of `2 days`. Once two days are on record, "2 days" is two days.
- Confirmed in game from that screenshot: the four tabs and Refresh fit in the header, the Gold tab draws, and purchases and vendor sales are recorded with what they were.
- Not confirmed in game: the corrected chart itself.

## 3.55.0 (2026-11-23)

- **The reagent bag.** The bags were read as numbers 0 to 5, with 5 taken to be the reagent bag (it is on the retail client). The reagent bag's number is now asked of the game itself, and every bag the game names is read. Whether the old assumption was wrong on this client has not been seen in a log.
- **Refresh says what it read**, so this can be checked at a glance: `Refreshed: 14 stacks in your bags (96 slots), 9 in the reagent bag (32 slots).` If it says `no reagent bag found` while you have one, send a Snapshot or the log: the log line also lists the bag numbers that were read.
- Note for anyone on 3.53 or earlier: there, the "in your bags" list only offered items the radar had a price for. Since 3.54 it offers everything that is not bound to you, reagent bag included.
- Not confirmed in game: only run in the offline tests.

## 3.54.0 (2026-11-23)

Streamlined: fewer places, no duplicates, and the front says plainly what is being sniped.

- **The Trades tab's front is two lines and the game.**
  - `SNIPING FOR  any deal that makes + 50c or more    vendor deals and flips`: the profit a deal must make to be offered, in plain words. The addon sets and adjusts that figure itself; there is nothing to enter or work out.
  - Your money in ONE line: gold in hand, what is still to come, and the total once everything has sold. The six-line MONEY block is gone from the tab; the mouse on the line opens the breakdown.
  - Then the snipe box, the deals and the score, with more room for deals.
- **Four tabs: Trades, Bags, Gold, More.** More has three pages: **Settings** (how you buy, the panel, your bank alt, what to send to Claude), **Advanced** (the figures the addon works out by itself: smallest profit, flip margin %, the money limits, what the radar reads; change one only to overrule it) and **Stake-out picks** (it was a tab).
- **Duplicates removed:** the Snapshot and Dock buttons in the header (both are on More, Settings), the engine bar at the top right (the Trades status line says what the radar does), and the "Show: vendor deals + flips" setting from the everyday page (the badge at the top left is that switch).
- **The Details sidebar is gone**, with its handle. To stop tracking an item (it had the button for that): **Shift + right-click** its row on the Bags tab. A plain click does nothing.
- **The Gold chart is redrawn as a market chart:** a line with the area under it filled; the amount now in large figures with the change and its percentage (green up, red down); the amounts down the left at round figures with a line across for each; a divider where each day begins with its date; times of day on the 2-day view; and the latest amount in a box on the end of the line. Three ranges: 2, 7 and 30 days. The biggest changes are still marked on the line (mouse over a mark for what it was) and listed under the chart, and the mouse anywhere on the chart gives the amount at that time.
- **Selling has nothing to do with what the radar is set to buy.** The Bags tab's "in your bags" list used to offer only items the radar had a price for, which meant crafting materials: gear you farmed never showed. It now offers everything in your bags that is not bound to you (gear that binds when equipped, recipes, anything; grey vendor junk excepted), uncommon or better first. Where the radar has no price, the price is read when you press Add.
- **No price is ever made up.** If nobody else lists an item and no price is on record, its row says `No price to go by` and it is not posted by the addon: post it from the game's own Sell screen at a price you choose.
- Not confirmed in game: all of this is new layout and drawing that has only run in the offline tests.

## 3.53.0 (2026-11-23)

- **Posting: you can see what is going on, and it is faster.** Posting needs a live price for each item, and each price is one request to the auction house. Until now only one request in four read a price while you were on the Bags tab, and nothing said so: a dozen items took about half a minute of what looked like a frozen panel.
  - The Bags tab now says it in figures: `READING PRICES: 4 of 12 ready, now Runecloth. About 10s for the rest.` and, when done, `All 12 priced and ready`. Items whose price is in can be posted while the rest are read.
  - While prices are missing, every other request reads one (twice as fast as before); once they are all in, the radar has three of every four requests again. On every other tab nothing changes: the radar keeps eight of every nine.
  - If you roll the wheel while on the Bags tab, sniping has every request, and the tab says the prices are paused for that.
- **Farmed or mined items are never held back.** 3.49 held them when a vendor paid more than the auction house. They cost nothing, so there is no price they have to wait for: they are always priced just under the cheapest listing and can be posted. Where a vendor pays more, the row says so (`a vendor pays more: 95c each`) and the choice is yours.
- **TODAY has a clock too**, next to the session's in the footer: the time of all of today's sessions, running while a session is on and kept across reloads and log-outs.
- Not confirmed in game: only run in the offline tests.

## 3.52.0 (2026-11-23)

- **A Gold tab: your gold over time, drawn like a stock chart.**
  - **One candle per day (the last 30 days) or per hour (the last 24 hours)**, with two buttons to switch. The thick part of a candle runs from what your gold was when the day began to what it was at its end: green if it ended higher, red if lower. The thin line reaches the most and the least it was in between. A day with no change is a flat grey mark.
  - **At the top:** your gold now, today's change, and the change over 7 and 30 days, each with its percentage.
  - **The biggest changes are marked on the chart** with a square: green above the candle for gold coming in, red under it for gold going out. **Mouse over a square** and it says when, how much, what it was (`Bought 60 x Runecloth`, `Sold 40 x Thick Leather (auction)`, `Sold 12 x Copper Ore to a vendor`, `Posting fee: ...`) and the gold after it. A change the addon did not cause (the game's own screens, a trade, a repair) says `not through the addon`.
  - **Mouse over a candle** for that day or hour in figures: began, ended, most, least, and what moved it.
  - **The same changes are listed under the chart**, largest first.
  - Changes in the same direction within 10 seconds count as one (a mailbox being emptied is one change, with its sales named).
- **How it is recorded:** each time the game says your gold changed, the hour, the day and the list of changes are updated. Kept per character, for 120 days (72 hours by the hour, the 300 largest recent changes). No request is sent and nothing runs on a timer.
- **It starts from this version:** there is no history from before, so the chart fills in from the first login with 3.52.
- The header has five tabs now. They are as wide as their labels need, and on the floating panel the button reads `Dock` in less room, so nothing overlaps (a test holds the gap).
- Not confirmed in game: only run in the offline tests. In particular the look of the chart has not been seen on a real screen.

## 3.51.0 (2026-11-23)

- **Bank alt, corrected: it is the one character the addon is for.** 3.48 to 3.50 had this the wrong way round (they switched the addon off at the auction house on the bank alt, which is why posting sat on "pricing" there). Now:
  - **On the bank alt** everything works as it always did: deals, prices, posting, mailbox, vendors.
  - **On every other character** the addon is switched off: it opens nowhere by itself (not at a vendor, the mailbox or the auction house), adds no tab, reads no prices, sends no request, collects no mail, writes nothing off as "not found" and says nothing at login.
  - **With no bank alt set** it works on every character, as before.
- **Setup, the "Panel / bank alt" row:** the button reads `Use on: every character` or `Only on: Name`. Each click moves to the next choice; the character picked last time comes first. A character is on the list once it has logged in with the addon.
- **If you open the panel by hand on a switched-off character**, the badge at the top left reads `OFF ON THIS CHARACTER` and the Trades and Bags tabs say so in full, so nothing ever looks stuck. One click on that badge makes the addon work on every character again (the bank alt is remembered for next time). The log says `SWITCHED OFF on this character` when the auction house opens there.
- If your main was set as the bank alt in 3.48 to 3.50, that setting now means what you wanted: the addon works on the main and is off on the others.
- Not confirmed in game: only run in the offline tests.

## 3.50.0 (2026-11-23)

- **Clicking the `BANK ALT: VENDORS ONLY` badge switches the mode.** It used to do nothing there. One click takes that character out of bank-alt mode (to `VENDOR + FLIPS`); at the auction house everything starts at once, with no need to reopen it.
- **The bank alt is remembered.** On the character that was last set as the bank alt, the badge has a third step: `VENDOR + FLIPS` > `VENDOR ONLY` > `BANK ALT: VENDORS ONLY` > back to the start. On your other characters it still goes between the first two only. Setup shows `Bank alt: off (Name)` while it is switched off.
- (3.49.0 was not sent out on its own: its changes, the header fix and the farmed or mined items, are in this version.)
- Not confirmed in game: only run in the offline tests.

## 3.49.0 (2026-11-23)

- **Fixed: the Refresh button lay over the Setup tab** on the floating panel while the auction house was open (the Dock button, Snapshot and Refresh together needed more room than there was). The four tabs and the buttons at the top right are narrower now, their sizes are in one place, and a test holds the narrowest panel to a gap between them (20 px).
- **Farmed or mined items: post what you did not buy.** Ore you mined, herbs you picked, anything an alt mailed you.
  - The Bags tab has a new section at the bottom, **IN YOUR BAGS, NOT BOUGHT BY THE ADDON**: the items in your bags that the auction house has a price for (the 12 worth the most), each with what it is worth after the cut and an **Add** button.
  - **Add** tracks the item as farmed, at a cost of nothing. Nothing is posted by that click, and nothing is ever added by itself.
  - It moves to its own section, **FARMED OR MINED, TO POST: ALL PROFIT**, apart from what was flipped. Its price is read at once and set the same way as for a flip (just under the real market, a few cheap units ignored). Post, Post next and the one key post it like anything else.
  - Because it cost nothing, all of what it sells for after the cut is counted as profit. The only floor is the vendor: it is not posted for less than a vendor pays.
  - Its row says `farmed` where the cost would be (also once it is listed, and if it comes back unsold), the Bags footer counts it apart (`Farmed or mined: + X when sold`), and it is left out of "Your biggest purchases" in Details.
  - Adding farmed units of an item you also bought makes one holding, with the cost spread over all of it; that holding is listed with what you bought.
- The Setup row with the bank alt button is labelled `Panel / bank alt` (the longer label could be cut off).
- Not confirmed in game: only run in the offline tests.

## 3.48.0 (2026-11-23)

- **Bank alt.** One of your characters can be marked as the bank alt, and the setting is kept for the whole account. On that character the addon is for vendors only:
  - **At a vendor** the panel opens on the Bags tab when something the addon bought is in that character's bags, and selling works as on any character. With nothing to sell it stays closed.
  - **At the auction house** nothing happens: no AuctionMesh tab, the panel stays closed, the radar and the sniper do not start (not by hand either) and no request is sent.
  - **At the mailbox** nothing is collected, and nothing your other character holds is given up on as "not found" for not being in the bank alt's bags.
  - No reminder at login. The badge at the top left reads `BANK ALT: VENDORS ONLY`. The panel can still be opened by hand (`/amesh`, or the addon list by the minimap) to change the setting.
- **Picking it: Setup tab, last group, the button "Bank alt"**. Each click moves on: none, then each of your characters in turn. The game gives addons no list of your characters, so the addon keeps its own: a character is on it once it has logged in with this version. Log in on the bank alt once, then pick it from either character.
- Not confirmed in game: only run in the offline tests.

## 3.47.0 (2026-11-23)

- **Details is redone: one view, "What to focus on", with two lists and nothing else.**
  - **Your biggest purchases** (the 8 that made the most): what each cost and what it made (green, "made") or makes if it sells at its listed or planned price (orange, "if sold").
  - **Biggest spreads** (the 10 items whose deals offered the most, from the last 400 deals seen): per item the profit its deals offered in all, its best single deal (how many, bought at, sells at, the percentage) and what you got of it ("got 2s50c, 1 of 2"). Each item has two tick boxes: **Focus** (on your own focus list) and **Ignore** (never offered). Ignored items are listed at the bottom so a tick brings them back.
  - Gone: the Session view with its three charts and its figures, the Items view, the Ledger and the Market view. The gold sample the charts took every 20 seconds is gone with them, and its stored history is deleted. The timings of your tries are still in the Snapshot.
  - Clicking an item on the left still shows that one item (market, your trades, advice, stake-out); a button at the top goes back.
  - It costs no request, is worked out at most every 10 seconds, and is not touched at all while a deal is appearing.
- **A Refresh button at the top of the panel** (next to Snapshot), for when the lists do not match what you hold. It counts your bags again (and the mailbox, if it is open), tracks again anything bought in the last 48 hours that the addon had given up on as "not found" and that is in your bags after all (with what it cost, and never more than it had marked not found: what you hold apart from the addon's purchases is left alone), asks for your own auctions again in the radar's next upkeep turn, and redraws every list from its top. Nothing is bought, posted or sold by it.
- **The item you went for is framed in its own row**, under DEALS TO BUY NOW: green when you bought it, red when someone was faster, for the same second and a half as the panel's edge. A deal that is over keeps its row for that long, in its place, with what happened written in it (it has no button and is not counted as a deal).
- **Deal rows are coloured by profit**, in four steps: 1g and more (the row tinted gold, name and profit in gold), 25s and more (bright green), 5s and more (a lighter green), less (no tint, the profit greyed). They were already listed most profit first within each kind.
- Not confirmed in game: all of the above is new drawing and has only run in the offline tests. The cause of the lists missing items from your bags has not been seen in a log; if Refresh does not bring an item back, a Snapshot taken right then will show why.

## 3.46.0 (2026-11-23)

- **The mode is at the top left of the panel**, where the name used to be, on every tab: a coloured badge that reads `VENDOR + FLIPS`, `VENDOR ONLY`, `VENDOR ONLY: GOLD LOW` or `STAKE-OUT: Runecloth`. **A click changes it**: between vendor + flips and vendor only, or, during a stake-out, it ends the stake-out. No trip to the Setup tab. (The status line under the snipe box no longer starts with the mode; the tabs moved right to make room.)
- **The footer of the Trades tab is SESSION | TODAY | the year**, each with how many deals you bought and what they are worth when sold (the "Worth + X when sold" of every purchase, added up):
  `SESSION 18:42  5 bought, 14 missed  + 9s65c   |   TODAY  35 bought  + 3g12s   |   2026  412 bought  + 41g20s`
  - **SESSION** is one stretch of pressing, **with a running clock**. It starts with your first press after a break of 10 minutes or more (or after logging in). Ten minutes without a press and it is over; its figures stay until the next one starts.
  - **TODAY** carries over reloads and log-outs and starts again at midnight (server time).
  - **The year** is the year to date. The first time, today and the year are filled from the journal of your trades (which keeps the most recent ones), and counted from then on.
  - The count that was under the snipe box ("This session: N got ...") and "Banked so far" are replaced by this.
- Not yet tried in the real game.

## 3.45.0 (2026-11-23)

- **Confirmed in game: the stake-out works.** Real log, 20:28: Runecloth's price was asked every 0.72 to 0.75s (the game's limit for price requests); at 20:28:25 the answer was 1s58c against a limit of 4s38c, the purchase was sent half a second later and one Runecloth was bought. The next request asked for two: none were left at that price.
- **A stake-out is unmistakable on the Trades tab.**
  - The status line starts `MODE: STAKE-OUT on Runecloth.` in gold, followed by `Running: every input asks its price. Nothing else is bought and the radar is off.` or `Not running: press in the snipe box to start it. Until then the radar reads as usual.`
  - The snipe box is gold while a stake-out is set (brighter while it runs) and says `STAKE-OUT RUNNING` or `STAKE-OUT SET, NOT RUNNING`.
  - A **Stop stake-out** button sits on the status line while one is set (it could only be ended on the Picks tab or in Details).
- **"One flip may take" has its own button** on the Setup tab, next to the one for unsold auctions: 35%, 50%, 75%, 100% of the gold you hold. No code to paste.
- **The import box and a key-press tool.** On the Setup tab your buy key is not bound, so a tool that keeps pressing it types into whatever has the keyboard: with the import box in focus it fills with that character until it is full, and then nothing can be pasted and Backspace cannot keep up. The box now empties itself when it holds nothing but one repeated character and the panel says `Something keeps typing '9' into the import box`. Clicking the box selects what is in it (a paste replaces it), and Enter applies the code. (That this is why your paste failed is the likely explanation, not a confirmed one: nothing in the addon blocks pasting.)
- Fixed: two texts still said "roll, tap or hold" (holding a key was removed in 3.33.4).
- Not yet tried in the real game: the new display, the button and the import box change.

## 3.44.0 (2026-11-17)

"Why don't I see the big flips more?" From the report of 21:11 and the code.

- **Fast sellers outside the focus set are checked for flips too.** With laser focus on "prime", flips were only looked for on the 12 best items plus your own list (15 in your report). Every other item measured to sell fast (about 35 more in that report: Copper Ore, Tin Bar, Medium Leather, Kingsblood, Stranglekelp, Iron Ore and so on) was passed over for flips altogether, however cheap it was listed. They are now looked at, without costing the focus items anything:
  - listed at half its market price or less: an ordinary alert, checked at once;
  - otherwise it waits for the upkeep turn (one request in nine), ahead of the routine listing re-reads that turn used to go to (`watch list: 23 real deals of 2617 checks` in your report), best first, and only if the radar's latest read still shows the price. A cheap price that is gone before its turn costs no request.
  - Flips straight from the radar (no item check) stay with the focus items: only their listings are kept current.
  - The panel's focus sentence says how many other fast sellers are covered this way.
- What limits the SIZE of a flip is your capital, and that is not changed here (your settings, shown on the Setup tab):
  - *Unsold auctions may hold 70%.* At 21:10 you held 1g17s with 10g48s in auctions that had not sold yet: 89% of everything you own. Over the limit, only small flips are offered: up to 15% of the gold in hand, which was 17s55c.
  - *One flip takes at most 35% of the gold in hand.* 41s at that moment. The 51 Thick Leather (1g42s for +1g34s) needed 4g05s in hand to be offered whole.
  - Both limits protect against gold stuck in auctions that do not sell. Your record so far: `100% of the last 20 sold, at 142% of the planned price`.
- Not yet tried in the real game.

## 3.43.0 (2026-11-17)

"Does something happen after the first 10 to 20 minutes?" Two things, both in the real log and Snapshot of 21:10 to 21:33. One is the addon's and is fixed here.

- **Auto-adjust raised the smallest profit a quarter every 10 minutes of a busy market, and nothing brought it back.** The rule was "15 or more deals shown in 10 minutes is more than can be acted on": true when you bought with clicks, not with the wheel or a key. At 20:58 it went from 1s01c to 1s26c (`69 deals shown in the last 10 minutes`), and that day 32 checks ended `profit is under your minimum` (a 1s05c Wool Cloth flip among them). It could only come down when at most one deal was shown in 10 minutes, which a busy market never has, so a session offered less and less.
  - **New rule, from what is measured.** A small deal has one cost: while it is being bought (about two seconds of auction house lock) a bigger one that appears has to wait. That is now counted: a deal that appears while a purchase of a smaller one is in progress. Three or more in 10 minutes raise the smallest profit by a quarter. None, with three or more deals hidden by the minimum, lower it by a quarter, in a busy market too. Limits as before (20c to 2% of what you own); a value you set yourself is left alone for 30 minutes.
  - **The old rule's raises are taken back**, once, at this update: they are in the auto-adjust log with their reason, and the smallest profit returns to what it was before the first of them, unless you have changed it since. The Setup tab and chat say so.
- **The other thing is your gold, and it is not the addon's to fix.** At 21:10 you held 1g17s with 10g48s in auctions; at 21:33 you held 2s31c, then 33c after two Silk Cloth, with 34 auctions sold and waiting to be paid (the auction house pays an hour after a sale). A Wool Cloth at 34c under a 1s78c market and eleven Silk Cloth at 99c under the vendor's 1s50c were on the list and could not be paid for. The first minutes of a session spend what you hold; after that only what comes back can be spent.
  - The reason for the Wool Cloth said `more than you have` with 2s31c in hand. It was your "spend" setting (one flip may take 35% of the gold in hand: 80c). The reason now says so.
- Confirmed in game (this log): radar reads 0.64 to 0.66s apart; 60 inputs in 5 seconds while rolling; the stale-deal and gold messages as designed.
- Not yet tried in the real game: the new auto-adjust rule.

## 3.42.0 (2026-11-17)

- **Vendor now, or wait and list it: both on the row.** For anything a vendor pays more for than it cost you, the Bags tab now shows the other way out and the difference.
  - Under **To sell to a vendor**: the profit is the vendor's, and a new **IF LISTED** column says what waiting and listing would add or lose (`+1s00c more`, `12c less`, `?` when no auction house price is known). Orange means you do not have the posting fee right now.
  - Under **To post, or sell to a vendor now** (a new section: items to post that a vendor would also take at a profit): the profit is the listing's, and a **VENDOR NOW** column says how much less the vendor pays (`24c less`).
  - Hover the row for the full sentence: `Vendor now + 5s00c   or wait and list: about + 6s00c, 1s00c more (fee 10c first: you have 5c, sale gold in 12 min)`. The fee is the posting fee it takes first; when you do not have it, the row says what you hold and in how many minutes your next sale gold arrives.
  - The item's advice in Details says the same in words, with how many sell an hour.
  - The auction house figure is from the live price once it has been checked; before that from the item's last full listing or the radar's last read (marked "about").
- **A holding kept as a flip can still go to a vendor.** Since 3.41.0 one item is one record, so units bought under vendor price can be held as a flip. If a vendor pays more than the holding cost, the row has a Sell button at a vendor (its own button only; "Sell all to vendor" never touches it), and the sale is booked at the vendor's price.
- Not yet tried in the real game.

## 3.41.0 (2026-11-17)

From a real Snapshot, report and log of 3.39.1 (21:10).

- **Fixed: items you hold dropped from the Bags tab.** The addon keeps one record per item of what you hold. A purchase of another kind replaced that record instead of adding to it: you held 7 Thick Leather bought under vendor price (5+1+1), bought 1 more as a flip, and the record became "1". The 7 were never offered for sale again, wherever they were, and the journal marked them `lost: no longer in your bags, mailbox or auctions`. Now every purchase of an item adds to its record, whatever kind of deal it was; if any of it was bought as a flip, all of it goes to the auction house.
- **The units that were dropped come back.** Once, at this update, units the journal marked lost in the last 48 hours are noted. When your bags hold more of such an item than the record says, that many go back on the Bags tab with what they cost (chat says so: `Thick Leather: 7 that the addon had lost track of are in your bags`). Never more than was marked lost, and only losses from before the update, so nothing you own apart from the addon's purchases is taken for its own. Looked for at login, when the auction house opens, and after a mailbox visit.
- **The mailbox with full bags.** A purchase that did not fit was tried again every 0.4 seconds for as long as the mailbox stayed open, with `Collected from mailbox: ... is now in your bags` in chat each time, and what the mailbox and bags really held was never looked at afterwards. Now the same mail failing four times in a row stops it: `Your bags are full: Thick Leather and anything after it stay in the mailbox. Make room, then open the mailbox again.` Each mail is announced once. (Read from the code, not seen in a log.)
- **Fewer alert checks that can only repeat the last answer.** A check that ends `cheapest is 50c, market 68c: needs 41c or less` says what price the item needs. Until the radar shows that price, another check can only say the same, but one was sent whenever more units were listed, and at once whenever the price fell, however far above 41c it still was. In the log 3 of 14 alert checks were such repeats, each a request (0.64s) the radar did not get. Now the item is not checked again for 5 minutes unless the radar's price is at or under what it needs, the market it was judged against has risen, or your settings have changed.
- Confirmed in game (this log): the input tracing of 3.39.1 works (`INPUTS as the deal appeared ...`); the radar reads every 0.62 to 0.66s on a lock of 0.64s; no addon error was caught.
- Not yet tried in the real game: the four points above.

## 3.40.0 (2026-11-17)

- **A deal that is gone leaves the panel as soon as the radar shows it.** In the real log of 3.39.0 each deal nobody bought stayed on the panel for 10 to 21 seconds, until its own re-check, and that re-check then cost one request (0.75s with no radar read) to learn what the radar had been showing since its next read. While it sat there it was the target of your inputs: a press on it costs a price request and a miss, with any live deal waiting behind it. Now a radar read that was sent after the deal was read, and shows the item's lowest price too high for the deal's units to cost what the deal says, takes it off at once and counts it as gone. No request is spent on it.
  - Only the price going up counts (a listing can lag behind sales and still show units that are gone, never the other way round), and a read that was already on its way when the deal was read says nothing about it.
  - A deal you are in the middle of buying is left to the purchase: the server's answer decides.
  - If another deal is still up, the radar's pause for it stands.
- **Churn in the daily report** (units leaving a listing per hour) only counted two radar reads a second or more apart. Since the radar reads every 0.73s that dropped eight intervals in nine. The minimum is now 0.3s. The figure is in the report only; no deal rule uses it.
- Checked against the real logs and NOT changed (from a modified copy of 3.33.0 that was sent in):
  - *Reserving the auction house for a purchase cancel.* In 17 cancels in the logs the cancel never took a request slot, and in every one since 3.x the next request left 0.01 to 0.2s later and was answered normally. The two errors after a cancel are from 2.6.0 and were fixed then (the cancel is sent 0.4s after the price answer). Waiting for the cancel to "settle" would delay the radar by about 0.3s after every miss.
  - *The game's own search on opening pausing the addon for 8 seconds.* Not in the logs: on opening the game asks for your auctions or bids (a 1 second pause). The three 8-second pauses after a search were clicks in the game's own screens.
  - *A radar read lost after an error.* Real, and fixed in 3.33.3.
- Not yet tried in the real game: the first point. Offline it passes its tests; the next log will show `GONE <item> by the radar`.

## 3.39.1 (2026-11-16)

From a real log of 3.39.0 (00:47 to 00:48): the radar read every 0.72 to 0.76s as before and found five vendor deals in 90 seconds (Silk Cloth three times, worth up to 19s38c). Not one input reached the addon while they were up: the box was not armed, no purchase was started, and each deal left after 10 to 21 seconds. The log could not say why, so this version makes the log say it.

- **The log says what the inputs were doing.** When a deal appears: `INPUTS as the deal appeared (4306): 0 input(s) in the last 5s, last input never | panel open, tab BUY, buy with one (key F), wheel bound: no, key bound: F`. When a deal leaves unbought: `INPUTS for the deal that went (4306): 0 input(s) while it was up, ...`.
- **Addon errors are caught and reported.** The game hides addon errors unless you switch them on, so one in the panel's redraw or in the input handler would only show as "it stopped working". Both now run guarded: an error is written to the log once with where it happened, counted, shown on the panel (`AuctionMesh hit an error ... send a Snapshot`), and listed at the top of the Snapshot. The rest of the addon carries on.
- Nothing else is changed: no request, timing or rule is different from 3.39.0.

## 3.39.0 (2026-11-16)

Details (the handle on the panel's right edge) now holds everything that is not needed to buy, and the Trades tab is down to what is.

- **Details, Session** (new view). Charts fixed at the top, figures under them:
  - **Tries**: one bar, green bought, red missed, orange gone with no input, with the count and percentage of each.
  - **Gold**: a column for every stretch of the session (gold in hand), a teal line above it (what you are worth when everything has sold, after the cut), and paler columns for the next hour, with sale gold that is already sold arriving when the auction house pays it. Nothing in it is a guess. Under it: in hand, when all has sold, the change since the start, sale gold due within the hour.
  - **Speed**: a column for each of the last 40 tries, in seconds from the deal showing to its end: green you bought it, red someone else had it first, orange gone with no input. Under it, your purchases against the buyer who was first: how many, the average, the fastest, and where the time of your purchases goes (input, the game's lock, the price answer, the purchase).
  - **Last tries, newest first**, each with its time against yours: `BOUGHT in 1.21s`, `TAKEN within 0.95s` (the other buyer's purchase was in before your price request was answered), `TAKEN between 0.80s and 1.30s` (still there for your price request, gone for your purchase), `GONE after 3.20s` (no input from you), with your own input, lock and price-answer times on the line below. The other buyer's time is a limit, not a measurement: the server only tells the addon that the units were gone when its own request arrived.
  - Presses in time and the two pressing limits, the radar's figures (time between reads, the last minute's requests, listings ready for an instant flip) and the last alert: all moved here from the Trades tab.
- **Details, Items** (new view): the items the addon goes for, best first (with laser focus off: the most active items), then your own list, then what you ignore. Two tick boxes on each:
  - **Always**: on your own list, watched whatever the addon picks (it counts once laser focus is on).
  - **Ignore**: never offered, flip or vendor deal. A deal on screen for it goes at once, without counting as a miss.
  - An item is one or the other. A row stays where it is while you tick; the list is put together again when the view is opened.
- **The Trades tab says less.** Status: one line, the mode and the radar's time between reads (a second line only for a warning: gold low, not enough gold, big flips paused). The gauge: the figure and the verdict (`An input every 100 ms: OPTIMAL`); the target is named only when you are not on it. "Last try", "Last alert", the last-minute counts and the presses-in-time count are in Details, Session.
- **Faster where it matters**: when a deal appears the panel is redrawn at once, and Details used to be rebuilt in that same redraw (ledger, market lists and all). It is now left alone on that path and brought up to date a fifth of a second later. No request is sent for any of the new views; with Details shut none of it is worked out.
- Snapshot: each of the last outcomes carries its timings (deal shown to its end, input, lock, price answer).
- The session chart of 3.38.0 (never sent out) sat under the deals on the Trades tab; it is in Details, Session instead.
- Not yet tried in the real game: all of the above, and 3.37.0's gauge.

## 3.38.0 (2026-11-16, not sent out: see 3.39.0)

- **A session chart under the deals** on the Trades tab. It takes the room the list does not need: shown while at most three deals are up (two on a short panel), and it gives way to the list when more are.
  - **Tries**: one bar, green for bought, red for missed, orange for gone before an input, with the count and the percentage of each: `24 bought (24%)   68 missed (68%)   8 gone before an input (8%)`.
  - **Gold this session**: a gold column for every stretch of the session showing the gold in hand, and a teal line above it showing what you are worth once everything has sold (gold, sale gold on its way, your auctions and what is bought and not listed, after the cut). Ups and downs are purchases, sales and fees as they happened. The heading gives both figures and the change since the start.
  - **The next hour**, paler, to the right of the "now" line: the gold in hand plus sale gold that is already sold, arriving when the auction house pays it. Nothing in it is a guess: auctions that have not sold are in the teal line only.
  - A sample is kept every 20 seconds, three hours of them, and they survive a reload. A break of over 30 minutes starts a new session on the chart.
- The chart costs the radar and your purchases nothing: no request is sent for it, and it is worked out once a second at most (at once when a try has ended), not each time the panel is redrawn for a new deal.
- Not yet tried in the real game: the chart (and 3.37.0's gauge). The panel's height when docked on the auction house is not known offline; if the chart does not show, send a screenshot.

## 3.37.0 (2026-11-16)

- **A gauge for your pressing speed**, under the snipe box on the Trades tab: a bar in three zones with a white marker where you are, and the figures next to it.
  - **Green, OPTIMAL**: an input at least every half window (245 ms at the 740 ms lock measured on this realm). Two or more inputs always land in the window.
  - **Yellow, IN TIME, NOTHING TO SPARE**: up to one window (490 ms). One input always lands in it.
  - **Red, TOO SLOW**: longer than that. A deal can sit waiting for your next input.
  - The window is the half second the game keeps its lock shut after the answer that showed the deal: a price request made inside it leaves the moment the lock opens, whenever in the window it was made. The zones follow the measured lock, so they move if the server slows down. Pressing faster than the green limit gains nothing.
  - Next to it: `Presses in time this session: 24 of 27`.
- **Each try gets a verdict**: `Last try (Silk Cloth, missed): your input was IN TIME.` or `... LATE (the lock was already open).` In time means the purchase could not have left sooner, so a miss was not down to your pressing.

## 3.36.0 (2026-11-16)

- **The mode is the first thing on the Trades tab**, in capitals and in colour: `MODE: VENDOR + FLIPS.`, `MODE: VENDOR ONLY.`, or `MODE: VENDOR ONLY (gold is low).`
- **The whole panel flashes**: green around its edge for a purchase, red for a miss, for a second and a half.
- **A miss is no longer written in the middle of the screen.** A purchase still is. (The game's own red error text for a refused purchase is the game's and is left alone.)
- **Your inputs against the game's lock, measured.**
  - While armed, the line under the snipe box reads `Armed. An input every 98 ms. The game takes one request every 740 ms: an input within about 490 ms of a deal is in time.` A press and its release each count as an input.
  - After each try, the second status line shows how it went: `Last try (Silk Cloth, missed): input 30 ms after the deal, the game held the price request 460 ms for its lock, price back after 710 ms, over after 1460 ms.` The log has the same as a `TRY` line.
- Shorter status texts so the first line fits.
- **Posting says what it is doing.** Each step of a post is shown where you are looking, in the snipe box on the Trades tab and at the top of the Bags tab: `Posting Thick Leather: Getting the live price first`, `Posting 7 x Thick Leather at 6s97c each: sent, waiting for the auction house to confirm...`, `POSTED 7 x Thick Leather at 6s97c each. 2 more items to post: keep pressing.` Posting from the Trades tab with the one key showed nothing at all.
- **A Post press that finds the auction house busy holds the radar for 3 seconds**, so the next press posts. It was 1 second: pressing about once a second, every press found it busy again and the post looked stuck (7 to 10 seconds between posts in the log).
- **Fixed: the "Last: GOT IT ..." line stayed on screen over the Bags, Picks and Setup tabs.**
- **A flip that would take more than your share-per-flip of the gold in hand is skipped at the radar.** With 11s in hand and the limit at 35%, a 4s78c Runecloth was alerted, checked and refused about every 20 seconds. It is counted on the "not enough gold" line instead.
- The Snapshot's `SLOW` figures no longer include the time the auction house was closed.

## 3.35.0 (2026-11-16)

- **Low gold: vendor deals only, by itself, and back by itself.** The addon keeps count of the posting fees still owed on everything you have bought and not listed (each auction costs its fee up front; it comes back when the item sells). When the gold in hand no longer covers them:
  - it stops offering flips and offers vendor deals only (gold back at the next vendor, no fee);
  - it tells you once: a line in chat with the figures, a sound, and the first status line of the Trades tab (`Gold is low: vendor deals only. You hold 2s50c; posting the 2 items you bought takes 4s. Flips come back by themselves. Next sale gold in 27 min.`);
  - it switches flips back on by itself when the gold in hand covers the fees with a little to spare (a fifth, at least 1s), or when nothing is left to post, and says so.
  - Your own setting (Vendor deals + flips) is not changed; the Setup tab shows `Vendor deals + flips (off: low gold)` meanwhile.
  - Something bought under vendor price that the auction house pays more for is still shown as "Post it", and its fee is counted.
- Snapshot, MONEY: `posting fees owed for what is bought and not listed`, and whether flips are off because of it.
- Not yet tried in the real game.

## 3.34.1 (2026-11-16)

From a Snapshot that listed 10 Mageweave Cloth as "sell to a vendor".

- **Listings under vendor price are not the market.** A vendor pays 2s50c for Mageweave Cloth and its market was about 4s40c, but piles at 2s00c kept being listed (the deals you were buying). A price check that caught one of those piles concluded "the auction house pays no more than a vendor", and that stood for ten minutes: 25s at a vendor for ten cloth the auction house would pay about 41s for. Rows listed at or under a vendor deal's price are now left out before the price is worked out, because anyone can buy them and vendor them at once and they are gone in seconds.
  - The same goes for the posting price: a post no longer undercuts such a pile.
  - If everything listed is under vendor price, or the market is not 10% better than the vendor after the cut, a vendor is still the advice.

## 3.34.0 (2026-11-16)

- **One key for buying and posting** (Setup, **Buy with**: `One key: buys and posts`; it uses the key chosen with **Key**). Each press does the next useful thing:
  - a deal is up: it buys it (exactly as "A key: tap it" does);
  - no deal: it posts the next item in your bags that is ready, at the addon's own price (one step under the market, never under what the item cost you with the cut; an item whose market is below that stays held);
  - nothing to do: it keeps the snipe box armed.
  - It works on the Trades tab and on the Bags tab. A deal always comes before a post.
  - Made to be pressed many times a second: a press with nothing to post says nothing in chat, posting is tried at most five times a second, and a post the game refuses is left alone for 30 seconds instead of being tried on every press.
  - Settings code: `buy=one`.
- **The radar goes on as soon as a post is confirmed.** It waited out a fixed 2 seconds after every post.
- How often to press: the game holds a price request until the lock from the radar's read opens, about half a second after a deal appears, so any press inside that half second leaves at the same moment. One press every 100 ms is already as fast as it gets; pressing faster gains nothing.
- Not yet tried in the real game: the one-key mode.

## 3.33.4 (2026-11-16)

From a log of "hold a key down" in the real game.

- **"A key: hold it down" is removed.** The game blocks every price request sent from a held key (`ADDON_ACTION_BLOCKED` three times out of three in the log). Each refusal switched buying back to the mouse wheel, which is what "it reverts to scroll" was, and gave the keyboard back to the game, so the held key did what it normally does (action bar 9). Three ways to buy remain: the mouse wheel, a key you tap, clicks. A saved "hold" setting becomes the mouse wheel, with a line in chat.
- **A blocked input no longer freezes the deal.** The purchase it tried to send was kept "waiting for a price" that was never asked: four seconds with the deal untouchable and the radar standing still, three times in that log (among them 27 Medium Leather that had become 199 by the time it was free again). Now it is dropped in the same instant and the deal stays on screen for the next input that works.
- **A blocked buy input is no longer counted as a blocked radar read** (three of those in a row would have switched the radar off).

## 3.33.3 (2026-11-16)

From a Snapshot of 3.33.2 (3 got, 15 missed in 4 minutes).

- **A lost radar read is sent again at once.** Four radar reads in four minutes got no answer, each one right after a purchase the server refused, and each cost 2.7 to 3 seconds with no radar: the moments after a miss, when more cheap units often follow. While a request is really on its way the auction house is locked, and it opens only after the answer. So "free again, and nothing came" is now read as lost immediately: the read goes out again about half a second after it was lost.
  - The `NO-ANSWER` line in the Snapshot now says whether the game transmitted the lost read or never did.
- Seen in that Snapshot: Wool Cloth has a buying price again on the Picks tab, which an item on hold does not have, so the one-time repair of 3.33.1 appears to have run.

## 3.33.2 (2026-11-16)

From a log and a Snapshot with 5 copper in hand ("not getting any bites").

- **The panel says when you cannot pay.** The radar passes over any listing that costs more than the gold you hold (for a flip: one unit plus its posting fee, 1s at least on this realm). It did so silently: 115 radar reads without one alert and nothing on the panel to say why. The Trades tab now reads `Not enough gold in hand: you hold 5c. 4 cheap listings in the last minute cost more than that ... and were skipped. Next sale gold in 27 min.`
- **No item check for a flip you cannot pay the fee of.** With about 1s in hand the radar raised alerts on cheap listings, each cost a request while you were armed, and each was refused with "more than you have". They are now counted on that line instead.
- **An unanswered radar read is sent again after 2.5 to 4 seconds** (6 in 3.33.0, 60 before). The Snapshot showed one in 800 reads, right after a refused purchase.

## 3.33.1 (2026-11-16)

From the first real logs of 3.33.0.

- **Fixed: a cancel made with the Cancel button could be booked as an auction that ran out unsold.** The game confirms a cancel with a number that is not the auction's (113 for auction 93521571 in the log), so the addon did not recognise its own cancel. When the 2 Wool Cloth came back by mail they were booked as expired, and Wool Cloth (26 flips sold out of 26) was put on hold for 12 hours: every Wool Cloth flip was refused with "did not sell last time".
  - The confirmation is now recognised without that number. The game fires the same event when an auction SELLS (right after its "sold" notice); that is told apart and never taken for a cancel.
  - A cancel you sent is remembered for an hour: whatever the confirmation looks like, what the mail brings back is booked as a cancelled auction, not as a flip that failed.
  - **One-time repair on first login:** if the only "ran out unsold" on record is a recent one, it is that wrong booking and it is taken back (chat says so). Wool Cloth is flipped again at once.
- **The second click on Cancel goes through.** The radar now keeps the auction house locked nearly all the time, so the click that cancels kept finding it busy (four clicks for one cancel in the log). After the first click nothing else is sent for 3 seconds.
- **Confirmed in game (3.33.0):** the radar leaves the moment the lock opens. Reads are 0.73 to 0.76 seconds apart, steadily (the server answers in about 0.23s here, then the 0.5s lock); on the Trades tab 8 radar reads go out between any two other requests. No refused request, no error, no back-off in either log.

## 3.33.0 (2026-11-16)

Sniping first. Every request slot the auction house allows (one per 0.65s) now goes to the radar, to the checks its alerts ask for and to your purchases; everything else waits its turn behind them. Figures below are from the offline lock model (`tests/pace_test.lua`: the game's lock as measured in your logs), not from the game.

- **The radar no longer leaves late.** It waited 0.4s of its own after each read, counted from a 0.2s timer, so about every second read missed the moment the lock opened and left 0.3s late: 0.80s between reads on average instead of 0.65s. The next read is now ready before the lock opens and leaves in that frame. Armed: 71-75 reads a minute before, 90-91 now.
- **Item checks no longer take the radar's turn.** They used to alternate one for one with radar reads whenever any were due (twelve focus items a minute: sixteen seconds of every minute at half radar speed). Now anything that is not the radar, an alert or a purchase gets one request only after the radar has had 8 reads in a row (3 on the Bags tab), never two in a row. Not armed: 64-68 radar reads a minute before, 82-91 now.
  - A focus item's listing is re-read when the radar shows the item has changed (not sooner than its interval), or after 5 minutes; no longer every minute regardless.
  - While you are armed the only such request is a listing a flip needs and does not have (see next point). No prices of what you hold, no side class, no list of your auctions.
- **Flips straight from the radar keep working while you are armed.** They needed the item's full listing read in the last 2 minutes, and nothing is re-read while you roll, so two minutes into a session every flip was back to waiting for an item check (0.65s). Now a listing up to 15 minutes old is used if the radar has watched the item without a gap since, and the market it showed is still deep enough after taking off every unit the radar has seen leave since.
  - The bottom of the market is always the radar's own previous lowest price, never the old listing's: the planned resale cannot be above it, and rows that have sold out no longer count.
  - Only the new units are bought; whatever sits above them is treated as competition.
- **A listing that is not a deal is not checked over and over.** A standing cheap listing that the rules refuse (say a vendor profit under your minimum) was checked every 20 seconds, armed or not, with the radar waiting each time. Now it is checked again only when the radar shows a lower price (at once), more units, you have more gold, or after 5 minutes.
- **A cheaper listing on an item just checked is checked at once** (it used to wait out 20 seconds).
- **After a purchase the radar is back at once.** The re-check of the item that followed every purchase (one request) is only made when cheap units may be left: your gold ran out, part of a pile was bought, or the count was not clear.
- **A purchase the server refuses** leaves those units alone for a few seconds (as a missed price already did) instead of checking and offering them again.
- **The radar starts when the auction house opens** (it waited 1.5 seconds, then let the list of your auctions and side classes go first: 1.6 to 6.9 seconds to the first read). The first request is now a radar read.
- **A price request that gets no answer** is given up after 4 seconds (was 10, with nothing else sent meanwhile). **A radar read that gets no answer** is sent again after 6 seconds (was 60).
- **Alerts go ahead of re-pricing what you hold** (they could wait behind it when not armed).
- **Your auctions moved to the Bags tab**: SOLD, STUCK LISTINGS (with Cancel), ENDED and LISTED are listed there under what you hold. The Trades tab lists deals only.
- **The Trades tab's status lines show what is really being sent**: armed or not, how many watched items can be flipped straight from the radar, the measured time between radar reads, and what the last minute's requests went to (`Last minute: 91 reads, 2 alert checks, 1 buying, 0 other`). "Next check: ... in 0.0s" is gone: it named checks that were not being sent while you were armed.
- **Snapshot, THROTTLE WATCH block**: what the session's requests went to (radar, alert checks, buying, upkeep, posting), the last 60 seconds, the average and longest time between radar reads, and how many reads left late with what was sent in between.
- Fixed: a blocked automatic purchase or radar read while the wheel was rolling could switch wheel buying off (the input was blamed for it).
- Not yet tried in the real game: all of the above. The first Snapshot will show whether the radar reads every 0.65s (`time between radar reads`).

## 3.32.0 (2026-11-15)

- **Throttle watch.** Everything that makes an auction house request wait is recorded for the whole session with its cause, as one log line starting with `THROTTLE` and as a block in the Snapshot:
  - `QUEUED`: the game held a request back because an earlier one still had the lock. Says which request waited, how long, and which one held the lock.
  - `SLOW`: the lock stayed shut much longer than usual after a request.
  - `BACKOFF`: a dropped or refused request or an auction house error; the addon's 5-second stop, with the reason.
  - `NO-ANSWER`, `GAME-UI` (one of the game's own screens made a request), `PACE` (the addon's pause between requests changed), `STALL` (nothing sent for over 3 seconds, with the reason).
  - Each incident lists the requests sent just before it and how many went out in the last 2 and 10 seconds.
  - The Snapshot block also has a table of lock times per request and the held-back requests by kind with their average wait.
- **A refused post or cancel no longer stops the radar.** The game's error message for it was treated as the server pushing back: a 5-second stop, and it could lengthen the pause between all requests.
- **Fewer routine requests.** Items you hold are re-priced every 45 seconds only while the Bags tab is open; on other tabs once in 10 minutes. Pressing Post still asks for the price at once.

## 3.31.0 (2026-11-15)

- **Picks tab: which item is worth a stake-out.** A fourth tab, between Bags and Setup. From the deals the radar has already seen in the last 24 hours it lists, per item: deals, how many you got, how many you went for and missed (with their worth), how many were gone before any input, what a stake-out would buy at, and the cheapest price now.
  - The line at the top says `Try a stake-out on <item>` when what you missed on it is worth more than everything the radar caught on other items in the same time (what a stake-out gives up, since the radar is off while it runs). Otherwise `Keep the radar`, with both figures.
  - **Stake out** on a row sets it in one click and takes you to the snipe box; the button then reads **Stop**. The tab's label reads `Picks (1)` when there is a recommendation.
  - With a stake-out set, the tab shows what it buys at and what it has done on that item so far (price asked N times, M bought), kept across sessions.
- **No cost to sniping.** The tab sends no request to the auction house. It is recalculated at most every 30 seconds and never while inputs arrive in the snipe box, a deal is on screen or a purchase is in progress.
- The record of deals holds the last 400 (was 80), so there is enough to compare items.
- The Snapshot has a PICKS block and the stake-outs so far.

## 3.30.0 (2026-11-15)

- **Cancel an undercut auction from the panel.** A row under STUCK LISTINGS has a **Cancel** button while the auction house is open. The first click says what it costs (the posting fee is not returned) and the button asks **Sure?**; the second click cancels. The units go back to the Bags tab as "In your mailbox", the addon takes them out at a mailbox, and at the auction house **Post** lists them again one step under the cheapest seller.
  - One auction per pair of clicks, dearest first. The lost fee comes off banked profit. A cancel is not scored as a failed flip.
  - If the auction house is busy on the second click it stays armed; if the game refuses, the row shows the game's own reason.
- **Expired auctions come back ready to post, in the cases that were left to you.** They are now recognised from the mail itself (an item you have listed, in a mail without an invoice). It used to need the auction house's list of your auctions from the same session, every auction of the item to be gone, and none of the item in your hands. So it failed when you went to the mailbox first after logging in, when you held more of the same item, and when one of two auctions ran out.
  - Returned units are added to what you already hold of the item, cost averaged.
  - Taking the mail out by hand before the addon does is recognised too.
  - A purchase of the same item arriving by mail is not mistaken for a returned auction.
- "Visit a mailbox: N item(s) to collect" (it said "purchase(s)").
- Not yet tried in the real game: the cancel (it uses the game's own cancel call and its confirmation event) and the new recognition of returned mail.

## 3.29.0 (2026-11-15)

- **All communication removed.** The addon no longer has any code that sends or receives anything: no addon messages, no chat channel, no guild. The sharing controls are gone from the Setup tab, and "spotted by a friend" from the deals. An install that had joined a channel for it leaves that channel once, ten seconds after the first login, and says so in chat. Prices are kept in a local price book as before.
- **The most valuable way out is the recommendation.** An item bought under vendor price is no longer sent to a vendor automatically. Its live auction house price (after the 5% cut, and the posting fee where that is not refunded) is compared with the vendor price; when the auction house pays at least 10% more, the row says **Post it: worth more than at a vendor**. Example: Silk Cloth bought at 99c, vendor 1s 50c, market 1s 98c, is posted.
  - **Sell all to vendor** leaves such items alone; the row's own **Sell** button still sells one to a vendor, and the drawer gives both figures.
  - Everything held is priced live while the auction house is open; with it closed the last full listing or the radar's last read is used.
- **Four ways to buy** (Setup, **Buy with**): the mouse wheel, a key you tap, a key you hold down, or clicks only.
  - **A key: tap it.** Press **Key**, then the key (modifiers and mouse side buttons work). It buys anywhere while the Trades tab is open and is your own key again everywhere else.
  - **A key: hold it down.** Click the snipe box, then hold any letter: every repeat is an input. Esc gives the keyboard back.
  - If the game refuses one kind of input for buying, that mode is dropped for one that works, and the panel says so.
  - Settings code: `buy=wheel|key|hold|click` and `key=F` (the older `wheel=1/0` still works). The Snapshot shows which is in use.
- **Setup tab in five short groups**: DEALS, BUYING, WATCHING, CLAUDE, ADDON, then three lines (auto-adjust's last change, the server's limit, the radar). Removed: the sharing rows, the eight engine lines, and the **Rebuild from purchases** button (dragging an item onto the panel still tracks it). **Last session's log** moved into the log window. "Self-tuning" is called **Auto-adjust** everywhere.
- Not yet tried in the real game: the key modes (holding a key in particular depends on the game accepting repeated characters as inputs) and the vendor-or-auction-house recommendation.

## 3.28.0 (2026-11-15)

From the seventh real log.

- **Faster vendor-price drops.** When a price falls under vendor price but the item's total quantity does not rise (other units were bought in the same second), the deal is shown at once for four units and the server's price decides. It used to wait for an item check, about 1.1 seconds.
- **Falling prices are priced in, not refused.** A fast-falling market no longer blocks every flip on the item. The resale is planned at the price the market is heading for (at most half off) and the usual margin decides.
- **Empty categories are rested.** With the wider radar setting, a category found empty is read every 10 minutes instead of every 30 seconds.
- **Stake-out terms judged on a lot.** The smallest profit is judged on up to eight units, not one, so cheap materials can be staked out.
- Deals shown straight from the radar accept a previous radar read up to 5 seconds old (was 2.5), so they survive the side reads.

## 3.27.0 (2026-11-15)

- **Stake-out mode.** Pick one item in the drawer (**Stake out this item**). While the wheel rolls in the snipe box, every notch asks the server that item's price directly and buys the moment it is a deal. This skips the radar read and the item check.
  - The buying price comes from the normal deal rules and the item's own listing, re-read once a minute.
  - After a purchase it asks for two, four, up to eight units, and buys them only if every one is at the price just paid.
  - The radar is off while it runs.
  - Set or ended from the drawer, or with `stake=` in a settings code. Shown in the snipe box and the Snapshot.

## 3.26.0 (2026-11-15)

From the sixth real log (wheel in use, reaction time 0.0s).

- **A failed purchase no longer slows the radar.** The game's error message after a refused purchase was counted as the server throttling requests: two 5-second radar stops, and the pause between all requests raised to 0.5s. Errors in the seconds after a purchase now belong to that purchase. The pause learned this way is reset once.
- **Posting price ignores cheap outliers.** A few units far under the market wall are skipped when pricing your own auction. 9 Heavy Stone had been posted at 2s 24c under a 3s 24c market.
- **Layout fits the window.** The engine bar sits between the tabs and the Snapshot button, shrinks to the room available and hides when there is none. Setup labels and engine rows cut off with "..." instead of overlapping. The drawer opens on the left when there is no room on the right.
- Confirmed in game: the mouse wheel starts purchases (27 in one session).

## 3.25.1 (2026-11-15)

- **Focus items are re-read every 60 seconds** (was 30). A real day showed 2,859 item checks against 2,054 radar reads. The interval is a setting: `every=20..300` in a settings code.

## 3.25.0 (2026-11-15)

- **Import.** The Snapshot ends with a settings code (`AMS1:...`). Pasting a code, or the whole message it came in, into the Import box on the Setup tab applies it and lists exactly what changed. A code can set the smallest profit, flip margin, radar scope, laser focus and capital limits; add to or remove from the watch list; give one item its own smallest profit; and put items on an ignore list. It never changes sharing.
- **Auto-adjust**, under the Self-tuning switch:
  - Smallest profit is reviewed after every 10 minutes of use: 25% lower when hardly any deal is shown and several are hidden by it, 25% higher when far more are shown than can be acted on. Bounded, and a value set by hand or imported is left alone for 30 minutes.
  - The radar's quiet time after a deal appears follows how fast inputs really come (1 second while the wheel is rolling).
  - Each change is logged with its reason on the Setup tab, in chat and in the Snapshot.
- With laser focus on prime items, the own watch list is watched as well.

## 3.24.0 (2026-11-15)

- **Sharing is off unless switched on.** A "Sharing: off / on" switch on the Setup tab; off is the default, and the update switches it off on existing installs (channel name and password stay saved). While off, nothing is sent to any channel or to the guild, nothing received is used, and the addon's channel is left.
- The guild is used only when chosen with **Use my guild**. It used to be the fallback whenever no channel was set.

## 3.23.0 (2026-11-15)

- **Snapshot.** A button on the panel header, on every tab, opens about 50 lines of plain text to paste: gold in hand, mailbox, each sold auction with its pay-out time, unsold auctions, holdings, settings, the last 20 snipe outcomes with reaction time and input used, the top reasons checks were not deals, the last purchases and the engine's figures.

## 3.22.0 (2026-11-15)

- **Snipe mode.** While the wheel rolls in the snipe box (and for 3 seconds after), only radar reads and alert checks are sent: no routine item checks, side categories or housekeeping.
- **Flips straight from the radar.** When the cheapest price falls, new units appeared since the last read and the item's full listing was read in the last two minutes, the deal is shown without an item check first.
- The box is "armed" only while the wheel is actually rolling (a notch in the last 0.7s).
- Fixed a stall: with routine work pending, the radar could wait for work that snipe mode would never take.

## 3.21.1 (2026-11-15)

- **Post says why it did nothing.** Every press of Post that does not post shows the reason on the row for four seconds; chat gets it once, not once per press.
- Spamming Post no longer pushes back the price check it is waiting for.
- The mouse resting on a row button pauses nothing.

## 3.21.0 (2026-11-15)

From the fifth real log.

- **Retry for the units still left.** When a price answer fits no exact count of leftover units, the deal is offered again for about as many as it implies; each further miss halves it. A dear unit is never bought.
- An item is muted after five misses in a row for 3 minutes (was three misses, 10 minutes).
- **MONEY double count fixed.** Sale gold collected at the mailbox comes off "waiting in the mailbox" as it arrives.
- The snipe box no longer shows chores; it says when the smallest-profit setting is hiding deals.
- Confirmed in game: one click buys (the addon's own purchase after the price came back was accepted).

## 3.20.0 (2026-11-15)

- **The snipe box.** The big Buy button became a box: keep the mouse in it and keep rolling the wheel; the first notch after a deal appears buys it.
- The mouse resting on the Buy button no longer pauses the radar. It did, so waiting with the mouse there meant no deal could be found.
- The game's Key Bindings screen lists "AuctionMesh: Buy the best deal".
- The Setup tab's heading shows the installed version.

## 3.19.2 (2026-11-15)

- The wheel stays bound to Buy for the whole of a purchase, so a notch can always supply a second input if the game refuses the automatic one.

## 3.19.1 (2026-11-15)

- **The Post button stays on the row.** It used to vanish whenever an item's price check was more than 90 seconds old. Prices are refreshed at 45s and trusted for 120s.
- "Post next" is hidden when there is nothing to post.

## 3.19.0 (2026-11-15)

- **One-input buying.** After one click, the purchase is sent as soon as the server's price matches the deal; switches itself off if the game blocks it.
- **Mouse wheel buys** while a deal is showing (Setup toggle).
- A price answer that shows part of a deal is gone re-offers the units still there.
- **Materials are always read back to back**, whatever the radar setting; other categories are side reads every 30s.
- **Capital.** Gold from auctions that have sold no longer counts against the flip limit; a small flip is always allowed.
- Sold auctions are shown under "SOLD, GOLD ON ITS WAY" with their pay-out time, not as stuck or undercut.
- **The drawer is a ledger:** one line per purchase with the profit made, the profit coming, or how much is down until it sells.
- Right-click no longer removes a row; the drawer has a button for it.

## 3.18.0 (2026-11-15)

- **Capital rules for the one-hour pay-out delay.** One flip takes at most 35% of the gold in hand, and flips stop once half of everything owned is in auctions. Vendor deals are never limited. A setting changes the limit.

## 3.17.0 (2026-11-15)

From the third real log.

- The radar reads back to back, about every 0.65s (was every 3s).
- An alert is always checked next; nothing else gets a turn while one waits.
- Vendor deals are shown straight from the radar when a price falls under vendor price and new units appeared.
- Every deal says who spotted it: your radar or a friend's.

## 3.16.0 (2026-11-15)

From the second real report.

- Clicks are always sent at once (held clicks were blocked by the game and lost).
- A blocked action no longer switches the radar off for the session.
- The false "not buyable (your own?)" error is gone.
- Old category lists re-sent by the game are no longer read as new.

## 3.15.0 (2026-11-15)

- Sharing status says what actually happened after Join, and who is connected.
- **Pop out / Dock:** the panel can be a separate, draggable window.
- The posting fee is checked against real sale invoices.

## 3.14.0 (2026-11-15)

- Sniping speed: the radar holds fire when a deal appears, clicks are spam-safe, and every deal ends in GOT IT, MISSED or GONE.

## 3.13.0 (2026-11-15)

From the first real daily report.

- A radar read that costs one or two requests is no longer shared out between players.
- Sales per hour are measured from full listings only (cancelled auctions had been counted as sales).
- The alert bar follows the deal rule's own margin.
- Small vendor profits are shown while the purse is under 5 silver.
- Selling a tracked item to a vendor by hand is recorded.

## 3.12.0 (2026-11-14)

- Scout: opportunity counts, prime items, laser focus, focus codes and the daily report.

## 3.11.0 (2026-11-14)

- A control for every setting on the Setup tab; no chat commands needed.

## 3.10.0 (2026-11-14)

- Detail drawer with a trade journal and one recommendation per open trade.

## 3.9.0 (2026-11-14)

- A request engine that learns the server's limit, an engine bar showing what it is doing, and the Trades / Bags / Setup layout.

## 3.8.0 (2026-11-14)

- Flat panel style and the MONEY section.

## 3.7.0 (2026-11-14)

- Learns from how flips turn out, shared across the channel.

## 3.6.1 (2026-11-14)

- Measures the request limit and the cost of a sweep live.

## 3.6.0 (2026-11-14)

- Spends the measured request budget efficiently.

## 3.5.0 (2026-11-14)

- Live sharing: shared radar, presence, deal hints, history catch-up. The NEXT line.

## 3.4.0 (2026-11-13)

- Price history database and a trend rule.

## 3.3.0 (2026-11-13)

- Panel rebuilt from the game's native interface pieces.

## 3.2.0 (2026-11-13)

- No mouse-over pause; the addon works only in its own panel; vendor sales need a click.

## 3.1.0 (2026-11-13)

- The portfolio keeps listed auctions; banked profit; a layout anchoring fix.

## 3.0.0 (2026-11-13)

- Radar engine and a panel docked inside the auction house.

## 2.9.1 (2026-11-13)

- The log starts empty on every reload.

## 2.9.0 (2026-11-13)

- HISTORY tab and mailbox pick-up messages.

## 2.8.0 (2026-11-13)

- Trading volume is measured; trading-terminal layout.

## 2.7.0 (2026-11-13)

- Fixes to the posting-fee model, held Buy clicks and starved sell pricing.

## 2.6.0 (2026-11-13)

- Flip rules tuned against a real market log; partial buys for a small purse.

## 2.5.0 (2026-11-13)

- Smallest-profit control; watch list and fee estimate tuned from guides.

## 2.4.0 (2026-11-13)

- Next-check timer, last result with its reason, and a scan timer.

## 2.3.1 (2026-11-13)

- Staple low-level materials are watched first.

## 2.3.0 (2026-11-13)

- Watch-list sniping and a profit headline.

## 2.2.2 (2026-11-13)

- Vendor-only mode switch.

## 2.2.1 (2026-11-13)

- Only money-making stackable goods are scanned by default.

## 2.2.0 (2026-11-13)

- The server's price answer is trusted over the listing; visible answers to every action.

## 2.1.2 (2026-11-13)

- Per-item price bug fixed; background work pauses during manual auction house use.

## 2.1.0 (2026-11-13)

- Prices come only from full live listings and real sale invoices.

## 2.0.0 (2026-11-13)

- Revamp: one window (BUY / SELL), strictly verified deals, exact buys.

## 1.0.0 (2026-11-13)

- First version: price sharing between players, shared scanning, a sniper for vendor and resale deals, and the Flip Bag for selling what was bought.
- Deposits counted in buying, screening and posting; a shareable debug log; purchases recorded only after confirmation.

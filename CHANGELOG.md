# AuctionMesh changelog

Newest first. Every release passed the offline test suites before it was sent. "Confirmed in game" marks something a real log from the realm has since shown working; everything else is untested in the real game until a log says otherwise.

To install any version: delete the old `AuctionMesh` folder, unzip the new one into `Interface/AddOns`, and `/reload`. The Setup tab's heading shows the installed version.

---

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

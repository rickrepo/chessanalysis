# AuctionMesh changelog

Newest first. Every release passed the offline test suites before it was sent. "Confirmed in game" marks something a real log from the realm has since shown working; everything else is untested in the real game until a log says otherwise.

To install any version: delete the old `AuctionMesh` folder, unzip the new one into `Interface/AddOns`, and `/reload`. The Setup tab's heading shows the installed version.

---

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

# Poker Game — Game Design Document

Last updated: 2026-11-01 · [Online version](https://claude.ai/artifact/FaTpfDN57VWJEVrPA2vPyp) (has the roadmap diagram, but hasn't been updated since 2026-10-28; this file is the main copy)

## Overview

A social No-Limit Texas Hold'em game where joining a friend's table always works. It ships on PC first, with accounts and tables on our own server, and keeps the game logic separate so a mobile version can follow.

**Why it exists:** the poker game we play now regularly fails to let us join a friend's table. This game makes "join friend" a first-class, one-click feature.

**Design pillars**

1. **Friends first.** Joining, inviting, private tables and spectating friends never take more than two clicks.
2. **Feels physical.** In 3D you peek at your cards and push chips. The rules engine stays authoritative, so physics is only for show.
3. **Always a game.** Bots fill empty seats, so a table or tournament can start with any number of humans.
4. **A bankroll to climb.** Persistent play chips, venues that get fancier as stakes rise, and bots that get smarter as buy-ins rise.
5. **Play chips only.** Chips can never be cashed out. Real money buys cosmetics only.

## Platforms & tech

It's built in Godot 4 with GDScript and ships on Windows first. Players log in to our own game server, which is self-hosted on a home PC for now and moves to a rented server later. Mobile (Android/iOS) comes later and reuses the same game logic with a 2D view.

| Layer | What it is | Notes |
| --- | --- | --- |
| Rules engine | Pure GDScript: deck, hand evaluator, betting state machine | No nodes, no rendering. Unit-tested. Runs on whoever is the authority. |
| Table authority | Runs the engine, deals, validates every action | On the game server (headless Godot, same code). Offline games against bots run it locally. |
| Transport | Godot `MultiplayerPeer` | ENet. Clients connect to the server's address on one UDP port. |
| Views | 2D table scene, 3D table scene | Both listen to the same table events. Choose in settings. Mobile uses 2D. |
| Accounts & save | Login, bankroll, cosmetics, stats | Stored on the game server, so chips persist between sessions and can't be edited locally. |

The split matters for two reasons. The 2D and 3D views share every line of rules code, and a dedicated server later is a deployment change, not a rewrite.

## Core gameplay

The only variant is No-Limit Texas Hold'em, played 6-max (2–6 seats), using standard rules.

**Hand flow:** post blinds → deal 2 hole cards → pre-flop betting → flop (3) → betting → turn (1) → betting → river (1) → betting → showdown.

**Rules the engine must get right**

- Dealer button moves clockwise. Heads-up: the button posts the small blind and acts first pre-flop.
- Minimum raise = the size of the previous bet or raise. An all-in for less than a full raise doesn't reopen betting.
- Side pots for multiple all-ins, split pots for ties, and odd chips go to the first winner left of the button.
- Hand ranking from high card to royal flush, with kickers. The best 5 of 7 cards play.
- Showdown order: the last aggressor shows first. Losing players can muck.
- A player who joins mid-game waits for the big blind or posts one to play immediately.

**Turn timer:** 20 s per action plus a 30 s time bank per player that refills slowly. When time runs out the player checks if possible, otherwise folds.

**Disconnects:** a dropped player auto-checks/folds and their seat is held for 3 minutes. If they rejoin within that window they continue with their stack. After that they're stood up and their stack goes back to their bankroll (cash) or keeps blinding off (tournament).

**Table actions:** fold, check, call, bet/raise with a slider and presets (½ pot, ¾ pot, pot, all-in), pre-select actions (check/fold, call any), sit out, stand up, top up (cash), and show cards after winning.

**Topping up (cash tables):** between hands you can add chips from your bankroll, up to the table max. A per-player setting chooses **manual** (a Top up button) or **auto** (refill to a chosen amount whenever your stack drops below it).

## Game modes

There are three modes. Each can be public or private, and bots can fill any of them.

| Mode | How it starts | Buy-in | Ends when | Bots |
| --- | --- | --- | --- | --- |
| Cash table | Sit down any time | Min–max per venue tier (e.g. 40–100 big blinds) | You stand up and your stack returns to your bankroll | Optional seat-fillers. The host sets how many. |
| Sit & Go | Starts when 6 seats fill, or the host starts early and bots fill the rest | Fixed entry fee from your bankroll | One player has all the chips. Top 2 paid (65/35). | Fill empty seats at start |
| Private friend tournament | The host presses Start | Set by the host | Same as Sit & Go. Payout split set by the host. | The host chooses how many and how difficult |

**Public vs private:** a public table appears in the lobby browser. A private table is either friends-only (visible to the host's friends) or invite-only (code or invite).

**Host settings for private tables:** blinds, min/max buy-in, starting stack and blind level speed (tournaments), turn timer, bot count and difficulty, and whether spectators are allowed.

**Rake (cash tables):** a cut of each pot is removed as a chip sink. Public tables take 5%, capped at 2 big blinds. Friends-only and invite-only tables take 2.5%, capped at 1 big blind. There's no rake on pots that end before the flop. Tournaments take no rake; the entry fee is the sink.

**Tournament blinds:** levels rise every N hands (Turbo 6, Normal 10, Slow 15), with antes from level 5.

**Spectating:** watch any table you can see. Hole cards stay hidden until showdown. Spectators can chat and emote, and a spectator can take an open seat. Spectator views lag 1 action behind so they can't be used to pass information to players.

Multi-table scheduled tournaments are out of scope until there's a dedicated server.

## Venues & stakes

Each stakes tier is its own venue. Moving up changes the room, the blinds, and the bots at the same time. A venue unlocks once your bankroll covers its minimum buy-in. No XP gate.

| Tier | Venue | Blinds | Buy-in (min–max) | Bot difficulty |
| --- | --- | --- | --- | --- |
| 1 | Garage game | 10 / 20 | 800 – 2,000 | Novice |
| 2 | Dive bar back room | 50 / 100 | 4,000 – 10,000 | Casual |
| 3 | Jazz club | 250 / 500 | 20,000 – 50,000 | Regular |
| 4 | Harbour yacht | 1,000 / 2,000 | 80,000 – 200,000 | Skilled |
| 5 | Penthouse suite | 5,000 / 10,000 | 400,000 – 1,000,000 | Shark |
| 6 | Private island | 25,000 / 50,000 | 2M – 5M | Pro |

Sit & Go entry fees follow the same tiers, roughly 25 big blinds per entry. Private tables can use any venue as decoration at any stakes. New players start with **5,000 chips**, enough for a couple of tier-1 buy-ins.

Numbers are first-pass and get tuned in playtests.

## Economy & progression

Progression is your chip bankroll. Chips come in through play, the daily bonus, free chests and the bailout. They go out through losses, entry fees and cosmetics.

| Source / sink | Amount | Rule |
| --- | --- | --- |
| Starting bankroll | 5,000 | Once per profile |
| Daily bonus | 1,000, +250 per streak day, up to 2,500 | Claim once per 24 h. A missed day resets the streak. |
| Free loot chest | Chips or a random cosmetic | One per day, plus one per 25 hands played. **Never sold for real money.** |
| Free bailout | 1,000 | Only when bankroll + table stacks < 400. Max 3 per day. |
| Paid bailout (future) | Larger amount | Needs the server-side economy first. See Monetization & legal. |
| Cosmetics shop | Priced in chips | Card backs, chip sets, felt colors, avatars, emote packs |
| Rake | 5% / 2.5% of cash pots, capped | See Game modes |

**Levels:** XP for each hand played, plus bonus XP for winning pots and tournaments. Levels unlock badges and some cosmetics only. They never unlock venues or stakes; the bankroll does that.

**Wealth milestones:** reaching a bankroll of a set size (e.g. 50K, 250K, 1M, 10M) unlocks a title shown on your name plate ("High Roller", "Tycoon"…) and a badge. Once earned, they stay even if you go broke later.

**Stats shown on the profile:** level, hands played, biggest pot, tournament wins, highest venue reached, and earned titles and badges.

The bankroll lives on the game server with the player's account. The client only displays it, so editing local files can't create chips.

## AI bots

Every bot combines a **personality** (how it likes to play) with a **difficulty** (how well it plays). The venue tier sets the difficulty, so higher buy-ins bring sharper bots.

**Personalities** (each bot also gets a name, a portrait and chat lines)

| Archetype | Style | Tell-tale behavior |
| --- | --- | --- |
| Rock | Tight-passive | Plays few hands. Bets only with strong ones. |
| Calling station | Loose-passive | Calls too much, rarely raises |
| Grinder | Tight-aggressive | Solid ranges. Raises rather than calls. |
| Maniac | Loose-aggressive | Raises constantly, bluffs a lot |

**Difficulty knobs** (Novice → Pro)

- **Hand reading:** equity estimate from Monte Carlo simulation. Novice runs few samples plus noise. Pro runs many samples against a modeled range.
- **Pot odds & position:** ignored at Novice, used fully from Skilled up.
- **Bet sizing:** fixed sizes at low tiers, sized to board and stack depth at high tiers.
- **Bluffing:** random at low tiers, board-aware semi-bluffs at high tiers.
- **Opponent memory:** none at low tiers. From Skilled up it tracks how often each player folds or raises and adjusts.
- **Mistake rate:** deliberate errors that shrink as the tier rises.

Bots never see hidden cards. They use the same information a human has. Mix per table: 2–3 archetypes, so no table is all Maniacs.

When a human leaves a bot-filled table, the bot that replaces them gets a fresh stack from the house. Bots have no bankroll.

## Multiplayer & networking

The game server is the table authority. It runs the rules engine, shuffles, deals, and checks every action. Players' games only send intents ("raise 400") and draw the events they receive.

**Hidden information:** the authority sends each player only their own hole cards. Other players' cards go out at showdown and only if shown. With the server as authority, no player's machine knows the deck. While the server runs on our own PC, whoever runs it could in theory read it, which is accepted among friends.

**Phase 1 — direct connect (done, replaced by the server).** One player hosted and friends joined by IP. The server does the same job for LAN and internet play, so it was removed.

**Phase 2 — own game server (MVP)**

- The same Godot project runs as the server with `-- --server` (`server.bat` starts it headless). Each table is a `TableRoom` (`net/room.gd`), and the server runs up to 20 at once.
- **Self-hosted for now:** it runs on our own PC with one UDP port forwarded. Players connect to a fixed address or a dynamic-DNS name, so it keeps working when the home IP changes. Moving to a rented server later only changes that address.
- **Accounts:** players register and log in with a username and password. Passwords are stored hashed (never as plain text), and the whole connection is encrypted (DTLS on ENet). The server makes a self-signed certificate on first start; copying its `server.crt` into the project folder lets clients check they reached the real server.
- **Persistent bankroll:** each account's chips, stats and cosmetics live on the server and are saved after every hand, so a crash or restart loses nothing. Cash-table buy-ins come out of the bankroll, and standing up puts the stack back. Everything is stored in one `accounts.json` on the server. Tournaments are free to enter until entry fees arrive in milestone 4.
- **Lobby:** after login, players see the server's table list. They can create a table (cash or tournament, with the host settings) or join one. Joining a full table or a running tournament watches it. Friends find each other through that list.
- **Backups:** the server copies `accounts.json` into a `backups` folder on every start. Copying that folder off the server PC now and then is still on us.

**Phase 3 — rented server (later)** runs the same server build in a data center. It brings better uptime, mobile cross-play and multi-table tournaments. Steam can still be added as a storefront later, with Steam login linked to accounts.

## Presentation

There are two views of the same table. The 3D view is the PC default and feels physical. The 2D view is for mobile and low-end PCs. Either can be picked in settings.

**Art style:** cartoony low-poly. Simple shapes and flat colors, with exaggerated characters (big heads, expressive faces and reactions). It's cheap to produce, runs on modest hardware, and translates directly into the 2D view.

**3D view (PC)**

- First-person seat at a 6-max table inside the current venue. The camera can lean in to look at the board or look around at opponents.
- **Cards:** your hole cards lie face down. Hold the mouse on them to lift and peek. Releasing puts them back down. Folding slides them to the dealer.
- **Chips:** drag from your stack to the betting line to bet. The amount snaps to legal sizes and shows a number while dragging. The bet buttons and slider stay available as a precise alternative.
- **Physics is cosmetic:** chips clink and settle, and the dealer pitches cards. The engine decides every result, so physics never changes an outcome and nothing physics-related is synced over the network.
- **Opponents:** avatars at their seats with a name plate, stack size, timer ring and emote bubbles.

**2D view (mobile / optional on PC)**

- Top-down oval felt, portrait-friendly. Your cards are large at the bottom and opponents sit around the rim.
- Tap your cards to peek, and use buttons plus a slider for bets.
- Readable at phone size: minimum 44 px touch targets, big stack and pot numbers.

**Shared UI:** lobby browser, table HUD (pot, blinds, timer, hand strength hint), hand history of the last 20 hands, settings, and profile/shop. Built once in Godot Control nodes and used by both views.

## Social

Social features stay light: text chat, emotes, spectating, and one-click joining of friends. Voice is left to Discord or Steam.

- **Text chat:** a per-table chat box with player and spectator messages labeled. Mute per player, plus a basic profanity filter (toggle).
- **Emotes:** a quick wheel of 8 reactions (nice hand, thinking, laugh, angry, GG…) that show as bubbles over the avatar. Rate-limited to 1 per 3 s. More packs unlock as cosmetics.
- **Spectating:** see Game modes. Spectators show in a side list and can sit when a seat opens.
- **Friends:** in the MVP, players find each other in the server's table list. Later, a friends list on the account with status ("At Jazz club table") and Join/Spectate buttons.

## Monetization & legal

Real money buys cosmetics only. Chips can never be withdrawn, traded or gifted between players, which keeps the game outside real-money gambling.

- **Cosmetic purchases:** direct purchases of specific items (card backs, tables, avatars). No paid random rewards.
- **Loot chests:** earned only, never bought, and no keys are sold either. The Dutch gambling regulator (Kansspelautoriteit) has acted against paid loot boxes, and Belgium bans them.
- **Paid bailout (future):** selling chips makes this a "social casino" game. Before adding it: (1) the bankroll must run on a properly managed server, not a home PC, so bought chips are safe, (2) check the age rating, since simulated gambling raises PEGI/ESRB ratings, and (3) check Steam's and the stores' current rules. Don't ship it without that review.
- **Chip transfers between players** are not allowed, because they would create a gray market for chips.

This is design guidance, not legal advice. Get a proper check before any real-money feature goes live.

## Roadmap

Every milestone ends with something playable. Milestones 1–3 are the MVP: Hold'em with bots and friends on our own server, with accounts.

1. **Milestone 1 — Rules engine and 2D table vs bots** (MVP, done)
   Deck, hand evaluator, betting and side pots with tests; 2D table; four bot archetypes at one difficulty.
2. **Milestone 2 — Play with friends (ENet direct connect)** (MVP, done)
   Host and join by IP, hidden cards, timer and disconnects, chat and emotes, Sit & Go and private tournaments. Works over the internet.
3. **Milestone 3 — Own game server and accounts** (MVP, in progress: server, accounts, bankroll and lobby are built; left: set up dynamic DNS, pin the certificate, run the MVP gate)
   - Headless server build that runs the table authority, with several tables at once.
   - Self-hosted on our own PC: port forward, fixed address or dynamic DNS, a start/stop script, and backups of the account data.
   - Register and log in, with hashed passwords and an encrypted connection.
   - Bankroll stored per account and saved after every hand. Cash buy-ins and cash-outs go through it. Starting bankroll 5,000.
   - Lobby screen: log in or register, table list, create table, join (watch when full).
   - **MVP gate:** friends log in from their own homes, play a cash session and a full tournament, and their chips are still there after the server restarts.
4. **Milestone 4 — Bankroll and venues**
   6 venue tiers with scaled bot difficulty, daily bonus, free chests, bailout, chip shop, levels and stats.
5. **Milestone 5 — 3D view**
   Venue rooms, card peek, chip dragging, dealer animations; 2D stays selectable.
6. **Later — Rented server**
   Move the server off the home PC, mobile cross-play, multi-table tournaments, friends list, optional Steam storefront, real-money cosmetic store.

## To do

- [ ] Show who is small blind and big blind on the table, with a chip or marker like the dealer button.
- [ ] Blinds stay fixed in cash games (only tournaments raise them).
- [ ] Tweak tournament blind speeds (hands per level for Turbo/Normal/Slow, and the blind steps).
- [ ] Bots need much more personality, and should drop their style when a hand is an obvious loss. Still to figure out how.
- [ ] Bots take a short "thinking" delay before acting.
- [ ] Try LLM-driven bots to make them less predictable (and maybe give them table chat). Open: cost per decision, response time vs the turn timer, and falling back to the normal bot when the LLM is slow or unavailable. Runs on the server so API keys never ship in the game.
- [ ] Bots get their own bankroll: they rebuy from it when busted, and once it's empty they leave and a new bot takes the seat, so different bots cycle through the table. (Replaces "bots get a fresh stack from the house" in AI bots.)
- [ ] Check and validate the winning logic (hand evaluation, showdown, pot and side-pot awards); it seems slightly wrong in play. Note the hands where it happens so they can become tests.
- [ ] Show clearly who won how much and who only got uncalled chips back, and show the main pot and each side pot with their sizes on the table.
- [ ] Session summary screen when you leave a table: your hands, what you won and lost in each, and the totals (hands played, total won, total lost, net result).
- [ ] Find a way to check if someone cheated chips into their account (e.g. a log of every chip change, so a bankroll can be traced back).

## Open questions

- [ ] Game name?
- [ ] Exact XP curve, wealth milestone amounts and title names (tune in playtests).

**Decided (2026-11-01)**

- [x] Server storage: one JSON file, written safely after every hand. SQLite would need an add-on and isn't needed at friends scale.
- [x] Direct connect is removed; the server covers LAN play too. Offline play against bots needs no account.

- [x] Own game server instead of Steam. Self-hosted on our own PC for now, rented server later. It's part of the MVP.
- [x] Accounts with a persistent bankroll on the server, so chips carry over between sessions.

**Decided (2026-10-28)**

- [x] Host leaving or quitting → the game keeps running minimized until the hand finishes, then hands over. Only a crash or a long disconnect voids the hand and refunds the bets.
- [x] The host is invisible to players; they just join tables.
- [x] Rake everywhere on cash tables, lower on friends-only tables.
- [x] Top up between hands, manual or auto (player setting).
- [x] No run-it-twice or rabbit hunting.
- [x] Art style: cartoony low-poly.
- [x] Levels unlock badges and some cosmetics; wealth milestones give titles and badges.
- [x] ~~Profile syncs via Steam Cloud if we go with Steam.~~ Replaced: profiles live on our server.
- [x] ~~Steam vs own server is decided after MVP playtesting.~~ Decided early: own server (2026-11-01).

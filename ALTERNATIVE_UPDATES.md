# The Darkness Of The Grasslands — Alternative Updates & Decision Log

> Purpose: a running log of development decisions, scope cuts, and things the user
> has explicitly said NOT to put into next releases. Future-me (and anyone picking
> up the project) reads this before making changes so nothing already-decided gets
> contradicted or re-added by accident.
>
> Source of truth for the game vision: the full "The Darkness Of The Grasslands —
> Full Planned Game Plan" document. This file tracks deviations, clarifications,
> and confirmed decisions on top of that plan.

---

## Decision Log

### Session 1 — Plan review & audit kickoff (current)

The user reviewed the full game plan. Decisions confirmed:

| # | Topic | Decision | Note |
|---|-------|----------|------|
| D1 | **LGS/LMS/LWS naming** | **Undecided — treat as alternatives for now.** | Use any of: **LGS (Last Grass Standing)**, **LMS (Last Man Standing)**, **LWS (Last Woman Standing)**. Code currently uses `LAST_MAN_STANDING` / `LMS`. **We will focus on this later.** |
| D2 | **Demo roster** | **Demo ships with killer ViolentGrass + survivor GreenGrass only.** | Other characters (Pink, Yellow, Orange, Cyan, Grey, AmberGrass, etc.) are unlockable/later content, not in the demo's free starting roster. |
| D3 | **Session task** | **Audit current game vs plan** (compare what's built against the plan and report gaps/mismatches). | Nothing is being built yet; the first deliverable is a gap/mismatch report. |
| D4 | **MD file** | Keep a **full decision log** (not just "do NOT include" items). | This file. It logs both what we ARE doing and what we explicitly decided NOT to do. |

> Note: The **kill timer bonus** was removed from the decision log (previously logged as
> "+30s vs plan's +15s"). The kill bonus decision is no longer tracked here.

---

## Do NOT include (explicit cuts / avoided features)

> Anything the user explicitly says should NOT go into a release gets logged here
> so it is not accidentally added later.

- *(none yet — nothing explicitly cut as of Session 1)*

---

## Pending / open items

- **LGS/LMS/LWS naming** (D1): code uses `LAST_MAN_STANDING` / `LMS`. All three names are
  acceptable alternatives; final choice deferred — **we will focus on this later**.
- **Audit report** (D3): full current-vs-plan gap analysis — **DONE (below)**.

---

## AUDIT — Current game vs. Full Plan (Session 1)

Verified against the live codebase (`scripts/`, `scenes/`, `assets/`). Legend:
**✅ Done** · **🟡 Partial / present but incomplete** · **❌ Not built**.

### Core match format (§2, §54)
- ✅ Match flow: Lobby → Intermission → Killer Intro → Round → LMS/LGS → Ending → Rewards → Lobby. All present in `game_map.gd` / `lobby.gd`.
- ✅ 4-minute round: `MATCH_DURATION = 240.0` (both map + server).
- ✅ No-revive philosophy: survivors stay dead for the match.
- 🟡 Intermission is currently a 60s lobby countdown (`countdown_duration = 60.0`), not a separate dedicated intermission scene. It mostly works as the plan's "intermission".

### Kill timer mechanic (§6)
- ✅ Every kill adds time to the match timer.
- ✅ Timer ticks up to target via `add_timer_bonus()` / `_bonus_target`.
- ℹ️ Current code adds +30s per kill. (Kill bonus decision removed from the log — see D1 note.)

### LGS / Last Grass Standing (§8)
- ✅ Fully built as "LMS" (`_lms_active`, `LMS_MUSIC`, heartbeat, VFX, kill zoom, final-chase presentation, reveal arrow).
- 🟡 Naming: code uses `LAST_MAN_STANDING` / `LMS`; **LGS/LMS/LWS are all acceptable alternatives (D1)** — final choice deferred. Not yet renamed.

### Victories (§9–10)
- ✅ Killer win when 0 survivors (outro + analysis).
- ✅ Survivor win when timer hits 0 with ≥1 survivor alive.
- ✅ Rewards: +1 gift ring + rounds-count per match (`_end_match`).

### Killer roster (§11)
- ✅ **ViolentGrass** — playable, 6666 HP (`max_hp = 6666.0`), intro + outro, multiple skins.
- 🟡 Monster GreenGrass, BlueGrass–Glitched, RedGrass, PurpleGrass — planned, **not built** (no controllers/scenes).

### Survivor roster (§12–14)
- ✅ **GreenGrass** — playable (healer/sentinel, block/punch/heal abilities).
- 🟡 Pink, Yellow, Orange, Cyan, Dark Grey, Grey, AmberGrass — planned, **not built** as playable characters. Classes (Healer/Sentinel/Looper/Hacker) are design concepts only.

### Abilities / health / damage (§15–16)
- ✅ Character-specific abilities + cooldowns (Greengrass: block, punch, spare-flower heal; ViolentGrass: attacks/teleport).
- ✅ Character-specific HP (6666 killer vs 100-ish survivor).
- 🟡 Not every planned class has an ability set (only the built characters do).

### Puzzles (§17)
- ✅ 3 puzzle types: Memory, Wiring, Rhythm (`puzzles/`).
- ✅ **Every puzzle has 5 levels** (`Level %d/5`, `_puzzle_level` 1–5) — matches plan exactly.
- 🟡 Only 3 of the planned puzzle purposes wired (objectives); unlock/resource/fuel purposes not yet.

### Waiting-room minigames (§18–20)
- ❌ **Tetris-style (Tetrino/sirteT), Save the Princess, Practice Range** — none built.
- ❌ Minigame → 2 Grass Coins progression — not built.
- ❌ **Cartridges** unlock system — not built.

### Currency / Shop / Browngrass (§21–22)
- ✅ Currency exists as `player_money` (add/spend) — but named "money", **not "Grass Coins"**.
- 🟡 Shop exists (`shop_layer.tscn`) but only shows 2 character cards (ViolentGrass + Greengrass) + a SKINS browser; no actual purchases/prices yet.
- 🟡 Browngrass as shop NPC — planned, not confirmed built.

### Character levels / milestone skins (§23–25)
- ❌ Character levels / XP — **not built** (no level system in `game_state.gd`).
- ❌ Milestone skins (Greengrass L25/50/75, ViolentGrass extremes) — not built.
- 🟡 Some skin assets/skins exist via the SKINS browser, but no level-gated milestones.

### Achievements (§26)
- ❌ Achievements UI + any achievements — **not built**.

### Chat / Quick Chat (§27)
- ✅ Player chat exists (WebSocket chat + admin commands).
- ❌ Quick Chat — **not built**; no character-specific quick-chat dialogue.

### HUD (§28)
- ✅ Health bar, stamina bar, ability icons, timer, damage VFX (shake + vignette).
- ❌ Minimap, objectives list, match state/LGS state panel, status effects — not built.

### Minimap (§29)
- ❌ No minimap (only a teleport "minimap" close helper, not an actual map minimap).

### Damage floats (§30)
- ❌ **No floating damage numbers** (no `-25` / `-9000` popups). Only labels used for AI name tags.

### Main map / environment (§31–32)
- ✅ Large forest map via `MapManager` (blueprint-driven collisions + navigation).
- 🟡 Interactive objects partial: puzzle triggers + a few interactables; doors/hidden areas/lore objects/collectibles not fully built.

### Map voting (§33)
- ❌ **Map voting — not built.**

### Killer intros/outros (§34–35)
- ✅ 1 killer intro (Violentgrass) + 1 killer outro (Violentgrass+Killer+Outro) both wired.

### Animation system (§36)
- 🟡 Many animated assets exist (idle/walk/attack via `AnimateSprite2D`, bot controllers); full per-character animation set not complete.

### Music & audio (§37–38)
- ✅ ~14 audio files, Lobby/Menu/Match/Chase/LMS music, dynamic chase layers, voicelines.
- 🟡 Full dynamic-music ladder (normal→tension→chase→LGS→ending) partially built (chase + LMS + ending present; menu/victory/defeat/special-mode themes partial).

### Lore & delivery (§39–41)
- 🟡 Lore via killer intro/outro + some environmental pieces exist.
- ❌ Full lore delivery (letters, hidden rooms, collectibles, secret achievements) — not built.

### Save system (§42)
- ✅ Robust save system (`save_manager.gd`: per-user `user://saves`, atomic writes, backup recovery, schema versioning).
- ❌ **Encryption** — not implemented (plain JSON currently).
- ❌ Saves coins/rings but not levels/achievements/cartridges (those don't exist yet).

### Multiplayer networking (§43)
- ✅ Dedicated server (`dedicated_server.gd`) is authoritative for match events (phase, player list, roles).
- ✅ WebSocket NetworkManager client + P2P bridge (`p2p_*`).
- 🟡 Client-side simulation still does a lot locally; full authoritative health/damage/ability sync is partial.

### Starting characters (§44)
- ✅ Demo/free roster = ViolentGrass (killer) + GreenGrass (survivor) — **matches D2**.

### External servers & special modes (§45–51)
- ❌ **Double Trouble** (2K/16S), **Infection**, **HELL MODE**, **"HOLY EVERYONE IS HIGH!!"**, **One Bounce** — none built.
- ✅ Canon-vs-gameplay separation is a design principle (respected; special modes non-canon).
- 🟡 `double_trouble` flag exists in `game_state.gd` but the mode isn't implemented.

### Demo scope (§52) — what IS in the demo today
✅ Lobby · Intermission (countdown) · one main map · ViolentGrass · GreenGrass ·
survivor+killer gameplay · timer · health · damage · abilities · puzzles ·
no revives · kill timer bonus · LMS/LGS · HUD · basic multiplayer · audio ·
1 killer intro · 1 killer outro.
❌ Still missing from the demo list: **minimap**.

### Development phases (§53)
- Phases 1–5 (foundation, core gameplay, LGS, map, interface) → largely **built**.
- Phase 6 (progression: XP/levels/coins/shop/unlocks/skins/achievements) → 🟡 partial (money + shop shell; no XP/levels/achievements).
- Phase 7 (presentation) → 🟡 partial (intro/outro/audio good; full per-character set incomplete).
- Phases 8–11 (more characters/maps/modes) → mostly ❌ planned.

---

### Biggest gaps to close first (recommended order for the demo)
1. **Minimap** — the only explicitly listed demo item not present.
2. **Damage floats** — cheap, high-impact feedback, fits the -9000 joke.
3. **LGS/LMS/LWS naming** — pick a final name (D1) and align the code (low-risk rename).
4. **XP / character levels + milestone skins** — core progression missing.
5. **Grass Coins currency naming** — align `player_money` → Grass Coins.
6. **Achievements UI** — entirely absent.
7. **Quick Chat** — entirely absent.
8. **Waiting-room minigames + Practice Range** — entirely absent.
9. **Map voting** — entirely absent.

---

## Session 2 — Arcade Room + Tetrino (built)

Added a playable arcade room to the lobby.

### What was built
- **Arcade room** (`res://scenes/arcade_room.tscn` + `res://scripts/systems/arcade_room.gd`):
  a pitch-black room ("no lighting whatsoever") with a single interactable
  arcade machine (`assets/objects/arcade machine.png`) and a controllable
  lobby-person player.
- **Lobby entrance** (both `lobby.gd` / `lobby_test.gd`): an invisible walk-in
  Area2D on the right side of the lobby. Walking into it triggers a **black
  block sweeping right→left** across the screen, then loads the arcade room.
- **Console boot sequence**: VHS-style flicker → green boot text
  `COMPUTERING CONSOLE BOOT V0.5P.R.O.T.O.T.Y.P.E.` → quick fake loading bar
  (10% → 78% → 100% in ~1s).
- **Minigame browser** (black screen): shows the single cartridge **TETRINO**
  with its thumbnail (`assets/Thumbnails/Minigame_TETRINO.thumnail.png`).
  - **WASD** navigation shows: *"This is the minigame we got in the Demo, so
    either have fun or just leave the game."*
  - **ENTER** launches Tetrino; **ESC** leaves back to the lobby.
- **Tetrino title/menu** (menu-first scope): thumbnail + looping
  `assets/Music/Minigames/tetrino.wav` on the **Music** bus + placeholder play
  field ("INSERT COIN TO PLAY — coming soon"). ESC returns to the browser.
- **Controls**: WASD/arrows + Shift to move, E to interact, ESC to back out.

### Decisions
- Tetrino is **boot + menu first** (title screen + placeholder field) — full
  playable Tetris is a later task.
- Room is reached via an **area** (no door), with a right→left black wipe.

*Last updated: Session 2 (arcade room + Tetrino built).*

## Session 3 (piece rendering + music loop fixes)
### Changes
- **Game blocks are now drawn procedurally** as clean solid-colour squares with a
  black outline, using each piece sprite's exact fill colour. This fixes the
  "glitching" (missing blocks / thin-line artifacts) that came from slicing the
  tightly-fused piece sprites into block textures. Pieces now render as clean,
  complete 4-block shapes in the playfield and the NEXT queue.
- **tetrino.wav now plays fully and loops seamlessly.** The .wav was being
  imported as QOA-compressed, which made the stream-level loop-end math wrong
  (it cut the track short at ~5.5s). The import is now uncompressed 16-bit PCM,
  so the loop covers the entire 13.7s track. Code also falls back to restarting
  on `finished` if a compressed import is ever encountered, so looping is robust.
### Decisions
- D-S3-1: Use procedural blocks (piece colours from the sprites) rather than
  slicing the fused sprite art, for reliable, glitch-free rendering.
- D-S3-2: Keep the loop logic in code (stream-level for PCM, `finished`-restart
  for compressed) so it does not depend on `.import` files (which are gitignored).

## Session 4 (Tetrino: collision fix, line-clear flash, win condition + coin economy)
### Changes
- **Fixed the piece collision problem**: rendering now uses the board grid as the
  single source of truth (blocks drawn cell-by-cell). Previously the render list
  (`_settled`) wasn't updated when lines cleared, so old blocks stayed on screen
  and new pieces appeared to overlap/clip them.
- **Line-clear flash**: completing a row flashes it pure white for a moment, then
  it collapses and disappears (classic Tetris), with gravity/input paused during
  the flash.
- **Win condition**: the minigame ends when the FIRST of (score >= 1000) OR
  (10 lines cleared) happens — a proper win, not a game over.
- **Win screen**: plays `MINIGAME-COMPLETED.wav`, shows the Grassconatication
  coin with a shine sweep, a pixelated +N (built-in 5x7 pixel font, no font
  asset), and the reward/retry/gamble prompts. The coin + earned count also
  appear on the minigame browser screen.
- **Coin economy** (rules confirmed): 1st win = +1 coin; after it you can
  GAMBLE into HARD MODE (faster gravity) — win = 3 coins total, lose = keep only
  1 (fair punishment). Without gambling, a 2nd win = 2 total (cap). Daily limit:
  one coin-earning opportunity per calendar day (local midnight reset). Admins
  are unlimited. Detected clock roll-back (to bypass the daily limit) adds a +5h
  penalty. Coins persist to disk via SaveManager.
### Decisions
- D-S4-1: Board grid is the single source of truth for both collision and
  rendering (removed the separate `_settled` render list).
- D-S4-2: Coin/daily-limit state stored in GameState + persisted via SaveManager;
  time-tamper detection is best-effort (a local game can't be fully tamper-proof).
- D-S4-3: Hard mode = the gamble; it's entered from the win screen with the G key.

## Session 5 (Arcade console power-on/off + entry/exit transitions)
### Changes
- **Turn off the console** (ESC while in the TETRINO browser): the screen goes
  WHITE and shrinks down vertically toward the middle until it's gone (CRT
  power-off), returning you to the idle arcade room so you can press E to boot
  it up again.
- **Leave the arcade room** (walk left off the left edge, or ESC while idle):
  a black block sweeps LEFT→RIGHT across the screen covering it, then loads the
  lobby.
- **Enter the arcade room** (walk right in the lobby): black block sweeps
  RIGHT→LEFT revealing the room (already existed, but was broken because the
  lobby's invisible walk-in area failed to attach during scene setup).
- **Fixed the arcade-entrance bug**: `_setup_arcade_entrance()` called
  `add_child()` while the lobby parent was still busy setting up, so the walk-in
  area was never added and you couldn't enter the arcade room. Now uses
  `add_child.call_deferred()` (in both lobby.gd and lobby_test.gd).
- **Console branding**: boot text now reads "COMPUTERING CONSOLE — THE MAGIC
  ENTERTAINER — BOOT V0.5P.R.O.T.O.T.Y.P.E."
### Decisions
- D-S5-1: The power-off (white vertical-shrink) is the console's turn-off effect
  and is tied to closing the TETRINO browser (ESC); leaving the room uses the
  black block left→right instead.
- D-S5-2: Leaving the room is done by walking left off the left edge (reverse of
  entering by walking right), matching the user's requested left→right black wipe.

## Session 6 (Fix: Grassconatication coin actually rendering big)
### Bug found
- The coin badges kept looking big no matter what size I set. Root cause: the
  TextureRect's `texture` was assigned BEFORE `expand_mode`. With the default
  `EXPAND_KEEP_SIZE`, assigning a texture makes the node auto-grow to the
  texture's native size (248x245) and it never shrank back, so setting
  `size = 10x10` had no effect.
- Fix: set `expand_mode = EXPAND_IGNORE_SIZE` (and `size`/`stretch_mode`) BEFORE
  assigning the texture, so the node stays at the requested size and the
  texture is scaled to fit. Applied to both the win-screen coin (10x10) and the
  browser badge (16x16). Verified via runtime debug print (`size=(10,10)`) and
  on-screen inspection.
### Decisions
- D-S6-1: For any TextureRect we size ourselves, assign `expand_mode`/`size`
  before the texture so the node doesn't auto-grow to the texture size.

## Session 7 (Arcade browser: cartridge nudge & shake on WASD)
### Change
- Replaced the "this is all we've got" nag text in the minigame browser with a
  tactile rejection animation. Pressing WASD (no other minigame to navigate to)
  now nudges the Tetrino cartridge OPPOSITE the pressed key (W pushes it down,
  A pushes it right, S up, D left), shakes it in place, then settles it back to
  the middle and stops.
- Refactored the cartridge into a single Control container (card + thumbnail +
  gloss + name) so it moves & shakes as one unit.
### Decisions
- D-S7-1: Since there's only one minigame in the demo, every WASD direction is
  a dead end — the cartridge always shakes and returns to center. This is the
  intended "nothing to navigate to" feedback.
- D-S7-2: Direction is opposite the pressed key (per user's spec: W->down,
  A->right, etc.).

## Session 8 (Console rhythm-sync + new audio)
### Changes
- ESC debounce: after any ESC is accepted, further ESC presses are ignored for
  0.35s so mashing it can't cascade across states (which caused glitches and
  repeated pitched-down cartridge-eject audio).
- Console background music: `Console-navigation-music.wav` now plays on the
  Music bus while the console navigator (minigame browser) is on — started on
  boot/console-on, stopped on launch / power-off. Loops seamlessly like
  tetrino.wav.
- Beat-sync: the browser runs a 140 BPM beat clock driven by the console
  music's playback position. Navigation (WASD) and confirm (ENTER) are QUEUED
  and fire on the next detected beat, so all console actions land on the beat.
- Navigation error: `Navigation-error-cant-navigate.wav` plays (random pitch
  0.8–1.25) each time the cartridge shakes.
- Confirm: `Console-confirm-sound.wav` plays (beat-synced) when launching a
  minigame with ENTER.
### Decisions
- D-S8-1: Beat-sync applies to the console navigator (where the background
  music plays). The Tetrino gameplay loop keeps its own timing.
- D-S8-2: ESC is debounced but intentionally NOT beat-latched so it always
  feels responsive when backing out.

## Session 9 (Console music muted in background + Tetris choice jingle)
### Changes
- Choosing a minigame no longer STOPS the console music — it now MUTES it
  (keeps playing in the background at -80 dB) so the minigame's own audio is
  what you hear. Returning to the browser unmutes it and it continues from the
  same playhead.
- The console music also keeps playing (no restart/gap) when the player changes
  the display/theme: the music node lives on the room, not the cleared UI, and
  _start_console_music resumes from where it left off.
- Playing Tetris now also fires the one-shot `tetrino-minigame-choice.wav`
  selection jingle on launch.
### Decisions
- D-S9-1: Launch mutes (not stops) the console music; only powering the console
  off fully stops it.

## Session 10 (ESC-mash during Tetrino intro fix)
### Changes
- Mashing ESC during the cartridge-start zoom-in intro no longer cascades
  through multiple states (cancel intro → close menu → turn off console → leave
  room). Cancelling the intro now locks out ESC for 1.2s so the rest of a rapid
  mash is absorbed and only the cancel happens; general ESC debounce raised to
  0.5s.
### Decisions
- D-S10-1: A burst of ESC presses while entering Tetrino should only back out
  of the intro (return to the title menu), never continue walking back further.

## Session 11 (Subtle old-console / prototype CRT aesthetic)
### Changes
- Added a full-screen CRT post-process overlay (`shaders/console_crt.gdshader`)
  on a canvas layer (51) above the console UI (layer 50), active for the whole
  console session (boot, browser, menu, game):
  - Slight pixelation (blocky sample ~2px).
  - Faint scanlines (alternating rows ~10%).
  - Barely-visible barrel curvature + subtle vignette.
  - Static noise controlled by a `noise_amount` uniform.
- Static appears ONLY while the console is loading (set in `_start_boot_sequence`
  and flickered through the boot/loading bar), and is set back to 0 the moment
  loading finishes (`_show_minigame_browser`).
- Overlay is removed on console power-off (`_turn_off_console`).
### Decisions
- D-S11-1: Effects kept deliberately subtle so text stays readable; no glitchy
  distortion or constant screen shaking. Static is intentionally stronger
  during the brief boot/loading phase, then fully gone.

## Session 12 (Multi-line Tetrino clear pause)
### Changes
- Line clears now pause the game based on how many lines were completed:
  - Single line: quick 0.28s white flash, unchanged.
  - Double / triple / more: the minigame FREEZES for a full 1.0s (via the
    existing `_clearing` flag, which already blocks gravity + input) with a
    brief full-screen white flash, then the rows collapse, the score is added,
    and play resumes.
### Decisions
- D-S12-1: Multi-line clears earn their impact with a longer freeze (1s) so the
  score feels earned; single lines stay snappy.

## Session 13 (Synced console boot-up → navigator music)
### Changes
- The console boot-up sound (`Console-bootup.wav`, 1.714s) now plays at the
  loading-bar phase instead of the very start of boot.
- The loading bar is now driven to run for exactly as long as the boot-up sound,
  so it reaches 100% at the same moment the boot-up ends.
- The 140 BPM navigator music starts the instant the boot-up finishes
  (`while boot_p.playing` handoff), giving a perfectly-synced boot-up → music
  transition with no gap.
### Decisions
- D-S13-1: Loading duration is derived from the actual boot-up clip length at
  runtime, so the handoff stays in sync even if the audio file changes.

## Session 14 (Two-cartridge camera-pan browser + coin spending)
### Changes
- The console browser now shows TWO cartridges in a horizontal row:
  - "TETRINO" — FREE (the original).
  - "TETRINO 2" — a copy costing 2 Grass coins (to test navigation + currency).
- Navigation works like the old single-cartridge browser: cartridges sit in a
  row and the "camera" (a panning container) slides so the selected cartridge is
  always centered, exactly where the player navigated. Thumbnails keep their
  glossy screen reflections.
- Navigating past the end of the row does NOT wrap around — it refuses and plays
  the navigation-error sound (no cartridge exists that way).
- Selecting the paid cartridge checks your Grass-coin balance: if you can't
  afford it, it plays the error sound and flashes "NOT ENOUGH COINS"; if you
  can, it spends the coins (tetrino_coins_spent, persisted) and launches Tetrino.
- The browser coin badge now shows the spendable balance (earned - spent).
- Player movement is frozen while the console is booting (confirmed existing
  _boot_active gate).
### Decisions
- D-S14-1: Paid cartridges deduct from a spendable balance (earned - spent) kept
  in the Tetrino coin domain, displayed in the badge and persisted via SaveManager.
- D-S14-2: Browser navigation is camera-pan (not wrap-around); at the row ends it
  refuses with the navigation-error sound.

## Session 15 (Nav-error shake + rebound restored)
### Changes
- Re-added the navigation-error shake + rebound: pressing a nav key toward a
  direction with no cartridge plays the error sound and shakes the camera (row)
  opposite the pressed key, then rebounds it back to center.
- Navigation is now strictly one of two outcomes per key press: move to the
  cartridge in that direction (confirm + pan), or nav-error (shake + rebound +
  error sound) — never any ambiguous/in-between behavior.

## Session 16 (Tetrino objective change, retry fix, gamble, permanent purchase)
### Changes
- Tetrino win/earn objective: reaching 1000 score NO LONGER earns a coin or wins.
  The objective is now purely clearing 10 lineups (WIN_LINES=10).
- Fixed "try again": pressing ENTER on the game-over/win screen did nothing
  because _start_tetrino_game() bailed when the title menu wasn't active. It now
  accepts a retry from a running-but-ended game (game over or win), which also
  makes the gamble (hard) mode fully playable end-to-end (win → 3 coins, lose →
  drop to 1, then retry works for both).
- TETRINO 2 is now a PERMANENT, profile-linked purchase:
  - Selecting it opens a PURCHASE CONFIRMATION screen that requires your game
    profile (shows PROFILE: <name>) before spending.
  - ENTER confirms (spend 2 coins once, unlock forever, persisted); ESC cancels
    back to the browser.
  - Once owned, the cartridge shows "OWNED" and costs 0 to play (no re-buy).
  - Spending gates on balance (error + "NOT ENOUGH COINS" if you can't afford).
  - New persistent GameState/save field: tetrino_owns_paid.
- ESC now also cancels a queued (beat-synced) action so a quick ESC backs out
  cleanly instead of racing a launch and turning the console off.
### Decisions
- D-S16-1: Win condition = 10 line clears only (score removed as a coin objective).
- D-S16-2: Paid cartridge = one-time permanent unlock tied to the profile, shown
  as OWNED afterward, rather than a per-launch spend.

## Session 17 (console sounds beat-synced to 140 BPM)
### Changes
- Every one-shot console blip now plays in rhythm with the console's 140 BPM
  background music. _play_console_sfx aligns each sound to the next beat of the
  music (confirm, error, choice, and cartridge-start jingle all land on the
  beat), while sounds that already fire from a detected beat stay immediate.
  Previously the purchase-confirmation sounds (and the cartridge-start jingle)
  played instantly mid-beat instead of in rhythm.
### Decisions
- D-S17-1: Console input blips are beat-aligned to the console music; blips fired
  from an on-beat action play immediately (no double-defer) and all others wait
  for the next beat.

## Session 18 (persistent cartridge ownership + grass coins)
### Changes
- Fixed persistence across restarts: on auto-login (session restore), the saved
  GameState was never loaded, so grass coins and cartridge ownership reset to
  defaults every launch. AuthManager._auto_login_from_session() now calls
  SaveManager.autoload(username) just like a manual login does.
- Verified live: with a saved state, the browser shows TETRINO 2 as OWNED and
  the correct spendable coin balance after a fresh session-restore launch.
### Decisions
- D-S18-1: Ownership and grass-coins are persisted per-profile via the existing
  save (already saved on win/purchase/spend); the missing piece was loading them
  on the session-restore login path.

## Session 19 (anti-softlock gift + real Tetris gravity)
### Changes
- Anti-softlock apology gift: if the player harvested Grass coins but spent them
  all and is stuck at 0 (and can't earn more — daily limit reached, already
  gambled, or at the 2-coin cap), the console auto-gifts them 2 Grass coins +
  1,000 gold once per profile, showing a "SORRY!" notice. Persisted via
  tetrino_gift_given so it only happens once. Grant happens before the balance
  badge is drawn so the badge shows the new coins.
- Tetrino now respects gravity like real Tetris:
  - Fixed the soft drop, which was broken (it reset the gravity accumulator
    every frame so holding Down barely did anything). Holding Down now drops the
    piece at a fast fixed soft-drop rate (~16 rows/sec), independent of level.
  - Gravity accelerates with level more aggressively (1.0s/row at level 1, down
    to 0.05s/row), like classic Tetris.
  - Hard drop (Space) and rotations unchanged.
### Decisions
- D-S19-1: The gift is one-time per profile and only for a genuine soft-lock
  (coins harvested then wasted, with no way to earn more) — not a new-player
  handout.
- D-S19-2: Soft drop is a fixed fast rate while holding Down (real-Tetris
  behavior), separate from level-based base gravity.

## Session 20 (2D smart-watch browser grid + TETRINO 3)
### Changes
- The cartridge browser is no longer a left/right-only horizontal row. It is now
  a 2D grid laid out like a smart-watch app launcher, navigated with WASD
  (Left/Right AND Up/Down).
- Added a third cartridge, TETRINO 3, costing 3 Grass coins (permanent,
  profile-linked purchase like TETRINO 2, shown as OWNED afterward).
- Grid layout:
      [TETRINO 3]        <- reached ONLY by pressing Up/Down (costs 3 coins)
  [TETRINO] [TETRINO 2]  <- reached by Left/Right
- Navigation is "smart-watch style": Up/Down grabs whatever is generally
  above/below (so TETRINO 3 is reached by Up from either bottom cartridge),
  while Left/Right only moves to a clean horizontal neighbor — so the TETRINO 3
  copy is NEVER reachable by pressing Left/Right (pressing Left/Right while on
  it plays the nav error + shake instead).
- Focused cartridge is full size; every other cartridge shrinks by its
  grid-distance from the focused one (the farther you navigate away, the smaller
  it looks) — a subtle depth effect.
- Purchase overlay/confirm logic generalized to any paid cartridge (uses the
  cartridge's own name and ownership key), so TETRINO 2 and TETRINO 3 both work.
- New persisted flag tetrino_owns_paid3 (save/load).
### Decisions
- D-S20-1: Grid-neighbor navigation: vertical presses are generous (grab the
  copy diagonally), horizontal presses are strict (copy is isolated). This keeps
  navigation simple while enforcing "the copy is only up or down".
- D-S20-2: No camera pan — all three cartridges fit on screen, so focus is shown
  by full-size + gold highlight, and distance by scaling.

## Session 21 (camera follows the chosen cartridge)
### Changes
- The browser camera now FOLLOWS the player to the minigame they're about to
  choose: as you navigate with WASD, the whole grid pans in 2D so the focused
  cartridge slides to the center of the screen (full size + gold highlight),
  while the other cartridges shrink by grid-distance behind/around it.
- Previously the grid stayed fixed; now the focused cartridge is always centered
  on screen for clarity.
- Compacted the cartridge cards slightly and moved the Grass-coin balance badge
  to the top-right corner so it never sits underneath a centered cartridge.
### Decisions
- D-S21-1: The pan target is the screen center; the grid is compact enough that
  the focused cartridge is centered and the others remain fully visible on
  screen (no clipping), so the "follow" reads as a smooth camera slide rather
  than a disorienting jump.

## Session 22 (console navigation music — retro effects on Soft-AnalogKeys)
### Changes
- The console navigation music is the existing "Soft-AnalogKeys" analog-keys
  track, renamed to Console-navigation-music.wav (the code name the game uses).
  Kept that track and ADDED subtle retro-console effects to it instead of
  replacing the melody:
  - Slightly pixelated / digital: gentle sample-rate drop to 22050 Hz with a
    clean anti-alias lowpass (soft, warm lo-fi character).
  - Subtle retro-console: mild 9-bit bit-crush for a faint digital "pixel"
    crunch.
  - Clear original melody preserved: the analog melody is untouched in pitch
    and timing, only given the retro texture.
  - Not harsh or noisy: the anti-alias + a gentle warm lowpass smooth the
    crunch, so it stays soft and non-fatiguing.
  - Suitable for TME's human-era aesthetic: keeps the original warm analog feel
    with just a hint of old-console character.
- Output is 16-bit PCM stereo, 22050 Hz, ~137s, and loops seamlessly
  (LOOP_FORWARD), so the console's beat-synced SFX still work (beat clock is
  position-based and independent of the track's tempo).
- _start_console_music loads the WAV via AudioStreamWAV.load_from_file() so it
  plays reliably without depending on the import cache.
### Decisions
- D-S22-1: Applied effects to the user's existing Soft-AnalogKeys track rather
  than synthesizing a new melody (the user's music was to be kept).
- D-S22-2: 22050 Hz + 9-bit crush + gentle lowpass = "slightly pixelated,
  subtle retro-console" while staying warm and not harsh.

## Session 23 (display toggle keeps your spot in the browser)
### Changes
- Pressing T (display/theme) while in the minigame browser no longer resets
  you back to the first cartridge. _rebuild_browser now preserves the selected
  cartridge index across the theme rebuild and re-centers the camera on it, so
  players keep their place even when there are many minigames.
- Verified headlessly: navigating to TETRINO 2 then toggling the theme keeps
  index 1 selected and pans the row back onto TETRINO 2.
### Decisions
- D-S23-1: Targeted the fix at _rebuild_browser (the display-toggle path) so
  re-entering the browser after a minigame keeps its existing reset-to-first
  behavior; only the display toggle preserves selection.

## Session 24 (controller support + full keybinding + settings + pause)
### Changes
- New InputSystem autoload — a central input system for the whole game:
  - Owns every rebindable action with default keyboard AND gamepad bindings.
  - Applies saved keybindings at startup (persisted to user://keybinds.cfg).
  - Rebinding a keyboard key never wipes the gamepad binding (and vice versa).
  - Detects the active input device ("keyboard" / "gamepad") and exposes
    is_pressed() / just_pressed() helpers for game code.
  - Binds the left analog stick to movement for smooth controller movement.
  - Adds gamepad bindings to Godot's built-in ui_* actions, so every menu is
    navigable with a controller (D-pad/stick + A select + B back) with no
    per-menu code.
- Console (arcade room) is now fully controller-compatible and rebindable:
  arcade_room.gd polling of raw keys was replaced with InputSystem actions
  (interact, cancel, confirm, move_* for browser navigation, display_toggle,
  tetris_left/right/down/rotate/harddrop, gamble). Gamepad D-pad drives the
  browser and Tetris; gamepad A/Start/Y map to confirm/rotate/gamble.
- Full keybinding in the settings menu: every action now has a dedicated Key
  button AND a gamepad button for rebinding independently (keyboard + gamepad),
  covering movement, interact/cancel/confirm/pause, abilities, display, gamble,
  and all Tetris controls.
- Expanded settings: added a CONTROLLER section (Controller Vibration toggle,
  backed by a new GameState.vibration_enabled). Existing audio/video/gameplay/
  accessibility settings kept.
- New PauseManager autoload: a controller-friendly Pause menu (Resume /
  Settings / Quit to Main Menu) opened with Pause (Esc/Start).
  - In normal gameplay it opens the full pause menu (tree paused, overlay
    always processes).
  - While the arcade console UI is on-screen, Pressing the gamepad Start opens
    Settings directly (the console pause); Esc in the console still means
    cancel/back.
  - Pure menu scenes (login / start menu) are skipped so their own Esc handling
    is unaffected.
  - Settings are opened via the existing settings_layer scene (also reachable
    from the start menu's SETTINGS button).
- Core gameplay scripts (lobby, game_map, match_manager) now use InputSystem
  actions for movement/sprint/interact instead of raw keys, so controller +
  rebinds work across the game.
### Decisions
- D-S24-1: Removed class_name from InputSystem (it's an autoload singleton);
  a class_name would shadow the autoload and break calls like
  InputSystem.is_pressed().
- D-S24-2: Rebinding only touches the target device's events, so switching
  inputs never discards the other device's mapping.
- D-S24-3: Esc double-duty resolved cleanly — Esc is cancel/back in the console
  and pause elsewhere; the console's settings access is the gamepad Start button.

## Session 24b (phone / touch detection)
- InputSystem now detects a third device: "touch". A touchscreen event
  (InputEventScreenTouch / ScreenDrag / magnify / pan) sets current_device to
  "touch" and emits device_changed("touch").
- On a phone, Godot also synthesizes mouse events from touches, so those are
  classified as touch too (avoids flickering between "touch" and "keyboard").
- New helpers: InputSystem.is_phone() (true when running on Android/iOS/mobile
  web) and InputSystem.is_touch() (true when the touchscreen is in use).
  Consumers can listen to device_changed or check current_device to switch
  prompts / show on-screen controls.
### Decisions
- D-S24b-1: "running on a phone" (is_phone, a capability) is separate from
  "player touching the screen" (is_touch / current_device), so a phone with a
  gamepad connected is still detected correctly.

## Session 25 (intermission timer sync + arcade notification)
- The "intermission" countdown (lobby's "Intermission: N left.") now lives in a
  new IntermissionTimer autoload instead of the lobby node. Because it's an
  autoload it is never freed on scene changes, so stepping into the arcade room
  no longer silently resets it — the timer keeps running and both scenes read
  the same remaining time (fully synced).
- The lobby starts the timer only when one isn't already running, so returning
  from the arcade room keeps the same countdown (no reset).
- When the intermission hits zero the timer autosaves and moves to the game map
  exactly as before, from whichever scene is active (lobby or arcade room).
- Added a top-left notification in the arcade room showing the synced
  "Intermission: N left." countdown. It appears only while an intermission is
  actually running and updates every second via the timer's ticked signal.
- Process mode is PAUSABLE, so the countdown fairly pauses while the pause menu
  is open but keeps running across scene changes.
### Decisions
- D-S25-1: Centralized the "intermission over" transition (autosave + game map)
  in the IntermissionTimer autoload so lobby and arcade room behave identically.
- D-S25-2: The old CountdownTimer node's autostart was disabled (both lobby and
  lobby_test scenes) so it no longer double-drives the countdown; the shared
  timer is the single source of truth.

## Session 25b (intermission-end heads-up in the console)
- When the intermission ends while the player is in the arcade room, the game no
  longer teleports them straight into the match. Instead a small heads-up panel
  appears: "A MATCH JUST STARTED!" with two choices — JOIN MATCH and
  KEEP PLAYING.
- JOIN MATCH leaves the console and goes to the game map (progress is autosaved
  by the IntermissionTimer as before).
- KEEP PLAYING dismisses the heads-up and leaves the player free to continue on
  the console (the intermission countdown label hides, since the intermission
  is over).
- The panel is controller/keyboard friendly: JOIN is focused by default, you move
  between the two buttons with left/right (D-pad / arrow keys) and activate with
  Enter/A; Esc/B also means "keep playing".
- The IntermissionTimer autoload now checks whether the current scene is the
  arcade room before auto-transitioning — if so it lets the room offer the
  choice instead of forcing the scene change. Lobby behavior is unchanged (still
  transitions immediately at zero).
### Decisions
- D-S25b-1: The "intermission over" choice is handled entirely inside the arcade
  room (it listens to IntermissionTimer.finished); the timer only auto-transitions
  when the player is NOT in the arcade room, so the lobby keeps its original
  jump-straight-in behavior.

## Session 25c (timers keep running while paused — multiplayer integrity)
- The intermission countdown no longer pauses with the pause menu. Because the
  game is multiplayer, the world keeps going even if one player pauses: the
  IntermissionTimer now uses PROCESS_MODE_ALWAYS, so it keeps counting down (and
  can finish the intermission) while the pause menu is open.
- Applied the same "keep running while paused" treatment to every timer that
  keeps the match intact:
  - MatchTimer (the round/last-man-standing clock) in game_map + game_map_test.
  - The AI StateTimers on the survivor (Greengrass) and killer (Violentgrass)
    controllers, so bot state keeps advancing for everyone.
  - Cosmetic/UI timers (dialogue, font-swap, bitmap HUD timer, etc.) are
    untouched — they still pause as normal.
- The scripted pauses during gameplay (bonus timer, round end) still work: the
  match clock's own `.paused` flag is unaffected by process_mode.
- Added a safety to PauseManager: if a gameplay timer ends the match (changing
  scene) while the pause menu is open, the pause is automatically cleared so the
  next scene isn't left stuck paused with the overlay on screen.
### Decisions
- D-S25c-1: Only timers that keep the multiplayer match intact were switched to
  PROCESS_MODE_ALWAYS; UI/cosmetic timers remain pauseable.
- D-S25c-2: PauseManager clears the pause on scene change while paused, so a
  match that ends behind the pause menu transitions cleanly.

## Session 25d (AI freezes on local pause; private server panel)
- The killer/survivor AI StateTimers were reverted from "always" back to
  "pausable": when you open the pause menu the AI now fully freezes (its state
  timers AND its physics). During normal/multiplayer play the AI still ticks as
  usual — the freeze only happens while the pause menu has the tree paused.
  (The match clock and intermission stay "always" per the multiplayer-integrity
  requests.)
- Added a PRIVATE SERVER PANEL (host / solo only). It's a button in the pause
  menu ("Server Panel") and opens a tabbed panel with:
  - Match: read/set the round clock (+/- 30s, set exact time), end the round,
    restart the round.
  - Players: live list of connected peers with Kick buttons (host only).
  - AI: killer difficulty floor slider + spawn killer/survivor bots.
  - Server: set the server name, broadcast a message to all players.
  - Values: live tweaks (money, player rings, match time).
- Added P2PManager.kick_player() (host only) and server_display_name.
- Cosmetic/UI timers are untouched; the pause overlay UI overlap seen on screen
  is pre-existing and unrelated.
### Decisions
- D-S25d-1: The AI freeze is scoped to the local pause menu only; the match
  clock and intermission remain PROCESS_MODE_ALWAYS for multiplayer integrity.
- D-S25d-2: The server panel is host-or-solo gated (active session requires the
  host; no session = solo owner). The Tetrino coin/unlock economy is local
  per-profile and anti-cheat gated, so it is intentionally NOT in the panel.

## Session 25e (Tetrino coins are now genuinely farmable)
- Made the Tetrino Grass-coin economy farmable (removed the lifetime cap and
  the daily gate on normal wins), so focusing on the console and winning the
  minigame repeatedly actually earns coins.
- New rules:
  - Every WIN (clear 10 lines / the objective) = +1 Grass coin. Repeatable,
    no lifetime cap, no daily limit. The "limit" is per run: you get exactly 1
    coin per normal win.
  - The 2nd coin comes from the daily HARD-MODE GAMBLE: on a win you're offered
    "play again (normal)" or "G to GAMBLE (hard mode)". Winning a gamble run
    pays 2 coins for that run. Losing the gamble keeps the coins you farmed but
    uses up the day's gamble.
  - The gamble resets each new calendar day (was a permanent one-time flag
    before), so it's a daily bonus on top of normal farming.
  - Removed the now-obsolete "earned caps at 2 / gamble sets to 3" logic and the
    anti-softlock gift (no soft-lock exists when coins are farmable).
### Decisions
- D-S25e-1: "Genuinely farmable" = every win earns 1 coin with no lifetime cap.
  "Limits also apply" = 1 coin per win, and the bonus 2nd coin is the daily
  gamble. This matches the user's description (farm 1 from finishing a
  minigame; 2nd coin by beating again with the objective OR the daily gamble).

## Session 25f (Owner coins + gifting system)
- Owner request: set the Greengrass profile's spendable Grass-coin balance to
  1,000 (earned = 1005, spent = 5). This was applied to the owner's profile
  directly (the earlier 10 coins were a test artifact and are superseded).
- NEW GIFTING SYSTEM — buy a game for a friend instead of yourself:
  - On a paid cartridge's purchase screen, press G to "GIFT to a friend"
    (Enter still buys for yourself, Esc cancels).
  - A friend picker lists local profiles + online P2P peers (self and
    current-owners excluded). Up/Down to choose, Enter to gift, Esc to back.
  - The gift costs the same as buying it (2 = TETRINO 2, 3 = TETRINO 3) and is
    deducted from your coins.
  - Delivery requires the FRIEND TO ACCEPT:
    • Local gifts persist in user://pending_gifts.json and pop an
      ACCEPT / DENY prompt when that profile opens the console.
    • Online gifts travel as P2P messages (offer/accept/deny) and the friend
      is prompted live.
  - Accepting grants the cartridge permanently to the friend's profile.
    Denying REFUNDS the gifter's coins.
- New autoload: GiftSystem (scripts/systems/gift_system.gd) handles gift
  persistence, applying unlocks, refunds, and the P2P message protocol.
### Decisions
- D-S25f-1: Reuses the "gamble" action (G) for gifting/denying — it's only used
  on the Tetrino win screen, so it's free elsewhere.
- D-S25f-2: Local gifts are delivered only when the friend opens the console;
  online gifts are delivered live over P2P. Denial refunds the gifter in both
  cases.
- D-S25f-3: A "testbuddy" local profile was created to verify gifting. It and
  any other test data will be deleted once the user confirms testing is done.

## Session 26 — Touch controls (controller + Android + iOS compatible)
Added a `TouchControls` autoload (`scripts/systems/touch_controls.gd`) that shows
an on-screen **virtual joystick + action buttons** whenever a touch screen is in
use (`InputSystem.is_touch()`). The overlay feeds the exact same rebindable
input actions as keyboard/controller (move_*, confirm, cancel, sprint, pause,
tetris_rotate, tetris_harddrop), so phones play identically with zero gameplay
changes. It auto-hides when a controller/keyboard is connected and adapts to any
screen size via anchors. Works on Android AND iOS (pure Godot input synthesis).
Re-exported and signed the Android APK with the new controls.
- D-S26-1: Overlay only shown while a touch device is active (is_touch()).
- D-S26-2: On-screen buttons reuse existing InputSystem actions (no new logic).

## Session 27 — Android compatibility + satisfaction fixes
- **CRITICAL login fix**: the Android export had `permissions/internet=false`, so the APK had
  NO INTERNET permission — the phone could never reach the server, which is why login failed.
  Enabled it. Verified `android.permission.INTERNET` now in the built manifest.
- **HD app icon**: replaced the tiny 64×64 SVG with a crisp 512×512 PNG (`icon512.png`,
  dark theme + DG monogram). Android now generates proper adaptive launcher icons at every
  density (hdpi/mdpi/xhdpi/...).
- **Resolution/centering**: switched `window/stretch/aspect` from `expand` to `keep`
  (letterboxes cleanly, no distortion on phone screens) and re-anchored the login screen
  (title + login card) to the center so it's centered on any screen.
- **Orientation**: forced the Android app to **landscape** so a phone held either way shows
  the game properly instead of in a broken portrait view.
- Re-exported + manually signed the APK with all fixes.
- D-S27-1: INTERNET permission is mandatory for online login; it was silently off.
- D-S27-2: `keep` aspect + centered UI gives a clean letterboxed phone experience.

## Session 28 — Fully offline/local login (temporary until Oracle Cloud server)
- Dropped pinggy. Login is now **100% local/offline**: no server connection attempt,
  no tunnel dependency. `AuthManager` handles local accounts, the admin account
  (Greengrass), reserved users, and auto-registration directly on the device.
- The login screen no longer waits on or fails due to a server — it just uses local
  auth and loads the player's saved data (coins, cartridge ownership, gifts).
- Online/multiplayer code is left intact (guarded by `if not connected`), so the game
  stays playable solo and the online path can be re-enabled when the Oracle Cloud
  server is ready.
- Rebuilt + signed the Android APK with offline login.
- D-S28-1: Local auth is primary; no server round-trip for login.

## Session 29 — The Magic Entertainer boot icon
- The console boot-up now shows `The-Magic-Entertainer-icon.png` (added by the user)
  flickering up with a CRT-style shimmer, then locks on and stays on screen through
  the whole loading bar, fading out only when loading completes and the navigator
  appears.

## Session 30 — Dirtysweeper (full minesweeper minigame)
- **Removed the TETRINO 2 cartridge** from the console browser and added a brand-new
  **DIRTYSWEEPER** cartridge (classic minesweeper) costing **2 Grass coins**
  (permanent, profile-linked unlock like the other paid cartridges).
- Built a **full playable minesweeper** (`scripts/dirtysweeper.gd` + `scenes/dirtysweeper.tscn`):
  9x9 board, flood-fill reveal, number clues with classic colours, flags, a restart
  button, and the user's **neutral / warning / dead face sprites** (with the gambling
  variants used in Hard mode). Win = +1 coin; Hard/gamble win = +2 (daily).
  Works with keyboard, controller (InputSystem actions), and touch/mouse.
- **Reset recent purchases**: cleared the paid-cartridge ownership and refunded the
  spent coins on the owner profile (Greengrass now has 1005 spendable coins, no paid
  cartridges owned), so purchases start fresh for the new economy.
- New GameState fields `dirtysweeper_owns_paid` / `dirtysweeper_hard`, persisted by
  SaveManager.
- D-S30-1: Dirtysweeper is a standalone scene launched from the browser; returns to
  the arcade room when quit.

## Session 31 — Mobile focus pass: music, drag navigation, playable minigames, cleaner touch controls
- **Fixed music on phones**: the console navigation music was loaded with
  `AudioStreamWAV.load_from_file()` (a raw file read that is fragile in Android's
  packed export). Switched it to the standard pck-safe `load()` used by every
  other sound in the game — the only `load_from_file` in the whole project.
- **Console browser: drag to navigate on touch.** New "browser" touch mode —
  swipe left/right/up/down to move between cartridges, tap to launch, small
  BACK button. Beat-synced like WASD.
- **Context-aware touch controls** (`touch_controls.gd` rewritten). The overlay
  now adapts to the current screen instead of always showing every button:
  - overworld (walking) — joystick + OK / BACK / SPRINT / small MENU
  - browser (arcade) — DRAG to navigate, TAP to launch, BACK
  - tetris (Tetrino) — joystick + DROP / ROTATE / OK / BACK
  - minesweeper (Dirtysweeper) — joystick + REVEAL / FLAG / BACK
- **De-cluttered & clearly labelled**: buttons are now plain text pills (no
  cryptic ⓐ/ⓧ/↻/⤓ symbols), subdued colours, low opacity, rounded. The old
  loud top-right pause button is gone — replaced by a small centred MENU pill
  in overworld only.
- **Dirtysweeper fully playable on phone**: tap a cell to reveal (with the new
  classic **press-and-hold shows the worried/warning face**, cancelled if you
  slide off), a FLAG button (new `flag` input action), joystick moves the
  cursor, BACK quits.
- **Tetrino fully playable on phone**: joystick moves left/right/down, DROP +
  ROTATE buttons edge-trigger exactly like the keyboard.
- New InputSystem action: `flag` (default key F, gamepad X).
- D-S31-1: Browser drag/tap lives in TouchControls (emits `swipe`/`tap`
  signals) and the arcade room listens — keeps one source of truth for touch.
- D-S31-2: Touch buttons use clear text labels + context-aware layouts so each
  screen shows only what it needs; pause is a small centred MENU in overworld.

## Session 31b — LAN cross-play (laptop + phone on the same Wi-Fi)
- Added a **LAN Party** cartridge to the arcade console: play together on the
  local network. One device HOSTS, the other JOINS by entering the host's LAN
  IP — no Ziva relay, no server, no subscription. Uses Godot's built-in ENet
  local networking directly over the Wi-Fi.
- New `scripts/lan/lan_manager.gd` autoload (`LANManager`): ENet host/join on
  port 2456, detects the host's LAN IPs, tracks peers, exposes
  host_started/join_started/connected/peer_joined/peer_left signals.
- New `scenes/lan_lobby.tscn` + `lan_lobby.gd`: host/join screen with an IP
  entry (the laptop shows its IP; the phone types it in). HOST shows the IP and
  waits; START (enabled once the phone connects) launches both devices together.
- New `scenes/lan_arena.tscn` + `lan_arena.gd` + `lan_player.gd`: a 2-player
  competitive "ORB RUSH" arena. The host (peer 1) spawns both players via a
  MultiplayerSpawner, owns the orbs and scoring; each device controls its own
  character (position synced via MultiplayerSynchronizer); first to 10 orbs
  wins. ESC / BACK returns to the arcade.
- Arcade browser: added "LAN PARTY" (free) cartridge at grid slot (1,-1), routed
  to the LAN lobby. Also fixed a stale global-class-cache entry that shadowed
  the LANManager autoload.
- Verified: two headless instances connect over localhost (host saw
  peer_joined, join connected); full arena e2e — the client received both
  spawned players (`players=2 host=false connected=true`); all scenes boot
  clean.

## Session 32 — Player-customizable touch controls + top safe area
- Touch controls are now **player-repositionable**: a small "⚙" button (bottom-
  centre) opens edit mode — drag any button (or the joystick) wherever you like,
  then tap "✓" to save. Layout is saved per-device to user://touch_layout.cfg
  and remembered across runs. Positions are stored as normalized screen
  coords, so they work on any screen size/orientation.
- **Notification/notch safe zone**: the top ~16% of the screen is reserved for
  the phone's status bar, notch and notifications. Buttons physically can NOT be
  dragged into that strip (position is clamped to TOP_SAFE).
- **MENU (pause) no longer sits at center-top** where phone notifications appear.
  Its default is now top-left just below the safe area, and the BACK buttons in
  Tetrino/Dirtysweeper/browser also moved below the safe line. All of them are
  now draggable anyway.
- Cleaner, more professional style: rounded pills, subtle border, slightly
  higher-contrast labels; in edit mode buttons highlight with a white border so
  it's obvious which ones are movable.
- Fixed earlier: LAN arena Back returns to the LAN lobby (a page back) rather
  than jumping straight to the console room.

## Session 33 — Removed LAN Party + parallel-instance testing launcher
- **Removed the entire LAN feature** (the user asked to delete it): the "LAN
  PARTY" cartridge in the console browser, the LAN lobby, the LAN arena (Orb
  Rush), the LANManager autoload, and all `scripts/lan/*` files + `lan_arena.tscn`
  / `lan_lobby.tscn` / `lan_party_thumb_frame_0.png`. The console browser now
  shows 3 cartridges (TETRINO, DIRTYSWEEPER, TETRINO 3). Verified no LAN
  references remain anywhere and the built APK contains no lan files.
- **Added `run_parallel_instances.bat`** in the project root: opens 9 windowed
  copies of the game at once, tiled in a 3x3 grid so you can watch them all run
  and spot anything wrong. Pass a number to change the count, e.g.
  `run_parallel_instances.bat 6`. (All instances share the same save folder.)

## Session 33b — Test multiplayer by yourself on one laptop (9 separate players)
- **Goal:** let the user run the online multiplayer game 9 times on the SAME
  laptop, each window as a DIFFERENT player, all connected to the same server,
  so they can watch/balance how the game behaves with many players.
- **Problem solved:** Godot 4.7 does NOT support `--user-data-dir`, and login is
  local (`user://accounts.dat` / `session.dat`), so plain parallel instances all
  became the SAME single player.
- **Solution:** `test_instances/player1..9` folders — each a real dir that
  *shares* the game files (815MB) via Windows directory junctions, but has its
  own `project.godot` with a unique `custom_user_dir_name`
  (`The Darkness Of The Grasslands-playerN`), so each writes to its own
  `%APPDATA%` user folder. The launcher seeds `session.dat` = `PlayerN`, so each
  auto-logs in as a distinct player. The server assigns each connection its own
  `player_id`, so 9 windows = 9 players online.
- **New launcher:** `run_multiplayer_test.bat` (double-click = 9 players, or pass
  a count). Opens windowed copies in a 3x3 grid; close each window to stop it.
- **Verified:** player1 boots headless + windowed with 0 errors, creates its own
  user folder, auto-logs in as `Player1`, and connects to the server.
- Replaced the old `run_parallel_instances.bat` (9 solo copies) with this.

## Session 33c — Play together with someone on the same Wi-Fi (host/join)
- **Goal:** let the user play the online game together with a specific person on
  the same internet/network (a friend or family member on the same Wi-Fi).
- **Found + fixed the real blockers:**
  1. The login screen's "Server URL" box was never actually used — whatever you
     typed was ignored. It now truly applies the URL (`apply_custom_url`) and
     saves it, so you can point the game at any server (local or online).
  2. The main "Find a Game" queue only starts a match when MANY players join, so
     2 friends could never get matched. Instead, same-network play uses the
     existing Host/Join room system.
  3. Fixed a P2P roster bug: the HOST never saw players who joined its room
     (the joiner now announces itself to the host), so the host can see the
     friend and start the match.
- **New flow:** In the start menu, "Host Game" opens the P2P room screen.
  - HOST: name your room + Create (registers it), wait for the friend to join.
  - FRIEND: Browse, select the host's room, Join.
  - HOST: presses the new "START GAME" button (enabled once a friend joined) and
    BOTH players enter the match together. game_map already auto-uses P2P sync.
- **New helper:** `start_same_wifi_server.bat` — starts the local server on one
  PC and prints the address the friend types in the login "Server URL" box.
  Host uses `ws://localhost:8080`, friend uses `ws://<host-LAN-IP>:8080`.
- **Verified:** login applies the URL; local server binds port 8080; a live
  two-process P2P host/join test shows both sides connect and the host roster =
  2 players; all affected scenes boot with 0 errors.

---

## Session 34 — Fully local game + smart survivor bots + release builds

**Commit: `bfd47aa` (P2P removal + bot AI), plus this session's build tooling.**

### 1. Removed ALL P2P — the game is now local ENTIRELY
Following your direction to drop P2P and make the game a fully local one:
- Deleted `scenes/p2p/` (p2p_lobby), `scripts/p2p/` (p2p_manager, p2p_game_sync,
  p2p_lobby_ui, p2p_server_browser) and `tests/p2p_handshake_test.gd`.
- Removed the `P2PManager` autoload from `project.godot`.
- Stripped every `/root/P2PManager` / `P2PGameSync` reference from
  `game_map.gd`, `game_map_test.gd`, `arcade_room.gd`, `gift_system.gd`,
  `pause_manager.gd`, and removed the "Host Game" button from the start menu.
- Removed online-gifting from `gift_system.gd` / `arcade_room.gd` (peer gifting
  was tied to P2P); gifting is now local-only.
- Deleted the obsolete multiplayer-test launchers (`run_multiplayer_test.bat`,
  `start_same_wifi_server.bat`, `cleanup_junctions.bat`) and the `test_instances/`
  scaffolding — no longer needed for a local game.
- **Verified:** `start_menu`, `lobby`, and `game_map` boot headlessly with 0
  script errors and no P2P references remain. The game plays fully offline
  against the AI survivor bots — no server connection, no hang.

### 2. Smart survivor bots (pathfinding, tracks, loop/kite the killer)
Ported to BOTH `ai_survivor_bot_controller.gd` (main) and
`ai_survivor_bot_controller_test.gd` (test scene):
- `map_manager.gd` now exposes `patrol_waypoints` ("tracks of lines" the bots
  walk along) and `loop_orbits` (4 points — N/E/S/W — just outside every wall
  obstacle, where a bot can safely run circles around it).
- Bots pick the nearest patrol waypoint to walk to when idle; they steer away
  from walls along these waypoint lines (pathfinding via walkable grid).
- NEW "LOOP THE KILLER" behaviour: when the killer is chasing and has line of
  sight, the bot runs to the nearest obstacle's orbit group, positions itself
  on the far side from the killer, and cycles between orbit points to kite/loop
  the killer around the obstacle.
- **Verified:** both bot scripts parse cleanly; an active match runs 25s with 0
  runtime errors.

### 3. Release builds (this session)
- **Windows** `.exe` + `.pck` (external PCK, not embedded) exported successfully.
  Root cause of the earlier failed export found & fixed: broken junctions under
  `test_instances/` were aborting the PCK pack — removed them and the pack
  completes (`The Darkness Of The Grasslands.pck`, ~80 MB). Also disabled
  safe-save (`filesystem/on_save/safe_save_on_backup_then_rename=false` in
  `editor_settings-4.7.tres`) which antivirus was blocking.
- **Android** `.apk` exported and signed with the Godot debug keystore
  (`%APPDATA%/Godot/keystores/debug.keystore`, alias `androiddebugkey`).
  Signing is wired into `export_presets.cfg` (keystore/debug + keystore/release)
  so the editor GUI signs automatically; for headless CLI exports the keystore
  is supplied via `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars.
- **Deliverables (zipped folders):**
  - `grasslands_build/The Darkness Of The Grasslands Windows.zip` — exe + pck + README.
  - `grasslands_build/The Darkness Of The Grasslands Android.zip` — signed apk + README.
- `.gitignore` updated to exclude build artifacts (`*.apk`, `*.idsig`,
  `grasslands_build/`).

### 4. Removed the dead P2P server registry (small-demo cleanup)
- Deleted the "PUBLIC P2P SERVER REGISTRY / BROWSER" block from
  `scripts/server/dedicated_server.gd` (`_handle_register_server`,
  `_handle_unregister_server`, `_handle_browse_servers`, `_unregister_peer_servers`,
  `_build_server_list`, `_broadcast_server_list`), the `_public_servers` field, the
  three dispatch cases (`register_server`/`unregister_server`/`browse_servers`),
  and the `_unregister_peer_servers()` call on disconnect.
- Removed the matching client dead code in `scripts/systems/network_manager.gd`:
  the `server_list_received` signal and its `server_list` handler (nothing else
  used it). This also removed a dangling `AddressCrypto` reference that was
  undefined — a latent bug.
- The normal online matchmaking (queue, `create_private_server`,
  `join_private_server`) is untouched. Verified: `dedicated_server.gd` passes
  `--check-only`, and `network_manager.gd` boots cleanly (NetworkManager autoload
  starts with no errors).

### 5. Gameplay fixes requested by the player (Session 34b)
- **Bots no longer stick to walls**: survivor collision is now a big, REGULAR
  circle (CircleShape2D radius 32; was a stretched 67×82 rectangle) and it still
  collides with walls ONLY (`collision_mask = 4`). Round shape slides smoothly
  around wall corners instead of catching on them. (`greengrass.tscn`, shared by
  the human survivor + all survivor bots.)
- **Earning rings NEVER makes you the killer**: `_determine_killer_by_rings()`
  now always returns false — the local player starts as a SURVIVOR against the
  AI killer bot. Use F2 (role switch) to play as the killer if you want.
  (`game_map.gd` + `game_map_test.gd`.)
- **Killer hunts the NEAREST survivor**: `_ai_find_target()` no longer uses the
  lone-wolf/injured scoring — it simply locks onto the closest alive survivor in
  aggro range, so it "goes and finds other survivors to kill that are close."
  (`ai_bot_controller.gd` + `_test.gd`.)
- **Chase theme from the survivor's perspective, muted when far**: the survivor
  chase already reflected only the human player's threat; tightened the exit
  distances (600→520 etc.) so the chase MUTES as soon as the killer moves away.
  Layers are unchanged. (`game_map.gd` + `_test.gd`.)
- **Abilities disabled near a puzzle/generator**: puzzle zones are now in the
  `"puzzles"` group, and the survivor's `_input` ignores abilities while inside
  one — block/charge-punch/spare-flower can't fire accidentally while you're
  interacting with a puzzle. Bots are unaffected (they call abilities directly).
  (`game_map.gd` + `_test.gd`; `greengrass_controller.gd`.)
- **M1 hit sound plays the instant the killer hits**: the hit sound now fires
  before the swing animation in `use_hit()`, so it never arrives late.
  (`violentgrass_controller.gd`, shared by human killer + killer bot.)
- **Killer outro plays the ENDING of the LMS, not the chase theme**: verified
  both main and test already stop every chase player and keep the LMS song's
  final ~1:33 tail playing under the killer-win outro — no change needed.
- **Dirtysweeper warning face on bomb**: the worried face now appears only while
  the player holds down on a BOMB cell (in reveal mode) — a classic minesweeper
  "am I about to step on a mine?" warning. Holding a safe cell keeps the neutral
  face. (`dirtysweeper.gd`)

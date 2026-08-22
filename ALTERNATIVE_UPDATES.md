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

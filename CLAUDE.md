# CLAUDE.md

Guidance for AI assistants and contributors working in this repository.

## What this is

**Shine Lifeform Picker** is a **Shine extension** for **Natural Selection 2**. Before a round,
aliens declare which lifeform they intend to play; the declaration shows as a scoreboard icon
visible to their own team and to spectators.

It has **no gameplay effect** — it does not reserve, gate, or force anything. Treat any proposal
that gives it mechanical consequences as out of scope.

`README.md` is the user/server-admin facing doc; this file is for development.

## Layout

Standard NS2 Launch Pad project layout, matching the author's other mods: `mod.settings` and
`preview.jpg` sit one level **above** the mod content, which lives under `source/`.

```
mod.settings                                        workshop metadata
preview.jpg                                         workshop preview
source/lua/shine/extensions/lifeformpicker/{shared,server,client}.lua
source/ui/LifeformPicker/Alien.dds
output/                                             Launch Pad build output, gitignored
```

`source/` is stripped at build time, so runtime paths are `lua/...` and `ui/...` — which is why
`PrecacheAsset( "ui/LifeformPicker/Alien.dds" )` is correct as written. **Do not** add `source/`
to any path inside the Lua.

**`output/` is gitignored and must be built before publishing.** A fresh clone has none, and
Launch Pad then reports the output directory as empty. There is no compilation step, so the build
is `rm -rf output && mkdir -p output && cp -r source/. output/`, leaving `lua/` and `ui/` at the
root of `output/`.

Because it is ignored, **`output/` does not follow branch switches** — it silently keeps whatever
was last built, which is an easy way to publish the wrong version. `.output-build-info` at the
repo root records the branch and commit it came from; check it against `git log -1` before
publishing, and rebuild after any checkout.

Three Lua files and one texture. Keep it that way — the value of this extension over the
alternatives is that it is small enough to read in one sitting.

## Two constraints that decide the architecture

**1. The files must reach clients, not just the server.** Shine loads a plugin's
`client.lua` from the *client's* filesystem (`Shine_PluginSync` tells the client to
`EnableExtension`, which then loads the file locally). A server-only install yields a server
plugin with no UI and no texture. Publishing as a workshop mod handles this — NS2 pushes server
mods to connecting clients automatically — so it only bites if someone hand-drops the extension
folder into a server's Shine directory. There is intentionally **no `lua/entry/*.entry`**: mod
content mounts into the virtual filesystem regardless, and an entry file exists only to bootstrap
ModLoader file hooks, which this does not use.

**2. The scoreboard is reached with `Shine.Hook.SetupClassHook`, never a ModLoader file hook.**
Scoreboard mods claim `lua/GUIScoreboard.lua` — Shimizu Scoreboard takes it in `replace` mode.
Hooking the file too would make this compete with whoever owns it. Patching class methods at
runtime layers cleanly on top. **Do not convert this to a file hook.**

## Design decisions worth not re-litigating

- **The wire format is an index, not a name.** `integer (0 to 4)` makes an invalid lifeform
  unrepresentable, so no normalisation or validation is needed on either side. Prior art in this
  space sends strings and pays for it with a five-branch normaliser in both VMs.
- **Absence means Skulk.** A player who never declares has no table entry and resolves to index 0.
  An explicit Skulk pick *is* stored, otherwise changing your mind back could not replicate.
- **No optimistic local application.** The client sends and waits for the server's echo. This
  deliberately omits the pending/rollback/stale-guard machinery Shimizu carries; the round trip is
  not worth that complexity for a cosmetic icon.
- **Identity comes from `Client:GetUserId()`, never the message body.** The message has no sender
  field by design.
- **Marines are filtered server-side**, per-client rather than broadcast. Client-side hiding would
  still put the data on their machine.
- **A pick is sticky; only its confirmation resets** (1.4). `Selections[ steamId ]` holds the
  lifeform value and is never wiped by a round boundary — only `ClientDisconnect` and `Cleanup`
  remove an entry. A separate `Confirmed[ steamId ]` set tracks whether that value has been
  actively (re)declared for the round in progress, and is cleared on `SetGameState( Started )`
  and `OnGameReset`. `OnSelect`'s guard is `Selections[ id ] == lifeform and Confirmed[ id ]`,
  not just an equality check — re-sending the same value you already have must still count as a
  fresh confirmation, or clicking to reconfirm a grey pick would look like "no change" and do
  nothing.
- **State resets are broadcast, not just applied locally on the server.** `UnconfirmAll` re-sends
  every remembered pick to every eligible viewer with `confirmed = false`, rather than telling
  clients to forget anything (there is no "forget everything" message any more — see 1.3's
  `LifeformPicker_ClearAll`, since removed; a client's copy is always either the true current
  state or absent, never state it must specially discard). Without this broadcast, a client that
  never performs a team-join action across a round transition keeps showing a confirmed cream icon
  from last round forever — `PostJoinTeam` is the only other point a client learns anything, and
  it only fires on an actual join. This was a live, invisible bug in 1.0/1.1, fixed in 1.1.1 by
  clearing the value outright; 1.4 replaced that clear with the sticky-value/confirm-reset split
  above so the value survives while still visually resetting.
- **Commanders neither show an icon nor can declare** (1.1). Client checks
  `Scoreboard_GetPlayerData( idx, "IsCommander" )`; the server independently rejects with
  `Player:GetIsCommander()`, which the base class defines as `false` and `Commander` overrides.
  The rejection does **not** erase a stored declaration — it is hidden while commanding and
  returns on logout, because losing it to an accidental chair-tap would be worse. Commanders
  still *see* everyone else's icons.
- **Two icon colours: grey for unconfirmed, cream for confirmed** (1.3, meaning shifted in 1.4).
  `kIconColourConfirmed` is RGB 255,225,187 — the cream of Hatta's *Lifeform Selector*, which
  never tinted anything (it applied a no-op `Color(1,1,1,1)`) and simply inherited the baked
  colour of the vanilla `ui/alien_hivestatus_commicons.dds` it drew from. Our source art is pure
  white, so `SetColor` reproduces that hue exactly and any other is a one-line change.
  `kIconColourUnconfirmed` is RGB 96,96,96, matching `kEalInactiveColor`'s convention from
  Enhanced Scoreboard / Shimizu Scoreboard. Originally (1.3) grey meant "never declared"; as of
  1.4 it means "not confirmed for this round", which includes a value carried over from a
  previous one — the shape can be non-default while the colour is still grey.
- **The icon is a child of `PlayerItem.Status`, anchored to its right edge** (1.4, on Devnull's
  suggestion). Originally it was a child of `PlayerItem.Background`, positioned to Status's
  *left* by reading `Status:GetPosition()` every frame. Enhanced Scoreboard draws its own
  upgrade icons immediately left of Status, which collided with that placement. Reparenting to
  Status directly also means position now tracks it through the engine's transform hierarchy
  rather than a per-frame read-and-recompute.
- **The icon's hover tooltip reuses vanilla's shared `badgeNameTooltip` widget** (1.41) rather
  than creating a second one. It is a genuine shared-mutable-state hazard: our hook runs
  `PassivePost`, strictly after the vanilla `Update` that drives that same widget for the comm
  badge, playtester badge, and skill icon, so whichever of us calls `Show`/`Hide`/`SetText` last
  in a frame wins the widget outright — there is no isolation between us and vanilla's own hover
  logic. `Show`ing when our icon is hovered is safe regardless; blindly `Hide`ing when it is not
  would occasionally cancel a badge tooltip vanilla legitimately showed the same frame (e.g. the
  cursor moves off our icon and onto a badge on another row in one frame — vanilla's `UpdateTeam`
  already ran and called `Show()` with the badge's text before our hook gets to run). The fix is
  `LastTooltipText`: we only call `Hide()` when the tooltip is still showing the exact text we
  last set, confirmed via `Scoreboard.badgeNameTooltip.tooltip:GetText()` — if something else
  claimed it since, we leave it alone.
- **The atlas is a set of vanilla lifeform icons**, sourced via Shimizu Scoreboard
  (ui/ShimizuScoreboard/Alien.dds), used with Shimizu's permission. The same file also ships in
  Devnull's Enhanced Scoreboard (workshop 2597529958, ui/Devnull/Alien.dds) - both point back to
  the same underlying vanilla asset rather than either having copied the other. Verified
  byte-identical by md5, which is only noted here to confirm which bytes this crop is derived
  from.
- **Prowler is excluded.** The atlas was cropped to just the five vanilla rows (340x570); the
  source had eleven more. Cropping from the bottom keeps rows 0-4 at identical coordinates, so no
  Lua changed. Regenerate mips alpha-weighted if it is ever recut - transparent areas are RGB
  0,0,0 and a naive filter produces dark halos.

## NS2 API notes

Facts verified against the game source; they are easy to get wrong from memory.

- `kGameState` is `{NotStarted, WarmUp, PreGame, Countdown, Started, Team1Won, Team2Won, Draw}`.
  "Pre-round" is the **first four**. Testing `== kGameState.WarmUp` alone hides the icons exactly
  when the round is about to start.
- `GUIScoreboard.teams` is ordered **ready room, marines, aliens** — aliens are `teams[3]`. This
  code matches on `Team.TeamNumber == kTeam2Index` instead of indexing, which is safer.
- Player items are **pooled and recycled between teams** via `reusePlayerItems`. Every row must
  have its icon visibility set on every update pass or a recycled row carries its old icon onto
  another team.
- `GUIScoreboard.kRedColor` is `Color(1, 0.4941, 0, 1)` — orange, the alien team colour, despite
  the name.
- `GUIHoverMenu` is a **singleton shared with vanilla** (`CreateGUIScriptSingle`). `AddButton`
  calls `AdjustMenuSize` itself, but `Show()` positions from the background's current size — so
  `Show()` must come *after* the buttons are added. `callback` is optional; an `AddButton` call
  with no callback (a transparent bg/highlight, e.g. `Color(0,0,0,0)`) renders as a non-clickable
  title row, since `GUIHoverMenu:SendKeyEvent` only fires entries that have one — used for the
  "Planned Lifeform" header, the same idiom Shimizu Scoreboard uses for its own lifeform menu.
- `Scoreboard.badgeNameTooltip` is a **singleton shared with vanilla**
  (`CreateGUIScriptSingle("menu/GUIHoverTooltip")`), the same widget behind the comm badge,
  playtester badge, and skill icon tooltips. API: `SetText(string)`, `Show(displayTime?)` (omit
  `displayTime` to show until explicitly hidden), `Hide(hideTime?)` (fades out; `Hide(0)` is
  instant, used when opening the pick menu). The text itself lives on `.tooltip`, a normal
  `GUIItem` — `.tooltip:GetText()` works, which is how we detect whether it is still showing text
  we set before deciding it is safe to `Hide()`. It follows the cursor and flips sides near
  screen edges entirely on its own; no positioning code is needed.
- `GetSteamIdForClientIndex` returns **nil** until the player's `PlayerInfoEntity` has replicated.
- `GUIItem.SetTextureCoordinates` accepts either four numbers or a 4-element array table
  (patched in `GUI/GUIItemExtras.lua`).
- Shine hook modes: `ActivePre` returns your value and skips the original when you return non-nil;
  `PassivePost` runs after and cannot alter the return.

## Testing

There is **no standalone Lua interpreter available** on the usual dev machine, and Shine's test
suite only runs inside an NS2 server. Changes must be verified in-game. Do not claim a change is
tested unless it was actually run in-game.

Useful checks in-game:
- Icons appear for aliens pre-round, and vanish the moment the round starts.
- A marine on the same server never receives declarations (verify server-side, not just visually).
- Clicking your own icon opens the menu **at the cursor**; clicking another player's does not.
- Switching teams mid-pre-round does not leave a stale icon on the recycled row.
- The alien commander has no icon on their own row but still sees everyone else's.
- A declaration made before taking the chair reappears after logging out of it.
- A confirmed (cream) pick turns grey, same shape, when the round starts or resets — it does not
  revert to the Skulk default.
- Clicking your own grey icon and picking the *same* lifeform turns it cream again (the "re-send
  the same value still confirms" guard in `OnSelect`).
- A player who never declares still defaults to grey Skulk, unchanged from 1.3.
- The icon sits to the **right** of the Status column, vertically aligned with it, and does not
  overlap Status's own text or (with Enhanced Scoreboard installed) its upgrade icons to the
  left. The vertical offset (`-kIconHeight * Scale`, a full height rather than the half-height
  used pre-1.4's repositioning) came from Devnull rather than being derived here — confirm it
  actually centres against Status's own height before assuming it is correct.
- Opening the menu shows a **"Planned Lifeform"** title row above the five lifeform buttons, and
  clicking that row does nothing (it has no callback).
- Hovering a lifeform icon shows a "Planned Lifeform: X" tooltip that follows the cursor and
  disappears when the cursor leaves the icon.
- **The important one:** with a mod that has its own scoreboard tooltips (badges, skill icon —
  vanilla itself qualifies), hover a badge, then move the cursor directly onto a lifeform icon,
  then back onto a *different row's* badge, watching closely each time the cursor crosses from
  our icon onto vanilla's territory. The badge tooltip must reappear correctly and must not be
  left stuck hidden or showing stale lifeform text — this is exactly the shared-widget race
  described in "Design decisions" above, and the one scenario that could not be verified without
  a live client.

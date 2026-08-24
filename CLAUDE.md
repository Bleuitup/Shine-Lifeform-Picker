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
- **State resets are broadcast, not just applied locally on the server** (1.1.1 fix).
  `LifeformPicker_ClearAll` is sent to every eligible viewer whenever `Selections` is wiped
  (round start, round reset). Without it, a client that never performs a team-join action
  across a round transition keeps its stale cache forever -- `PostJoinTeam` is the only other
  point a client learns anything, and it only fires on an actual join. This was a live,
  invisible bug in 1.0/1.1: a stale pick and a fresh default rendered identically under the
  single-colour design, so nothing looked wrong until 1.3 added a second colour and made a
  stale cream icon visibly distinguishable from a correctly-reset one.
- **Commanders neither show an icon nor can declare** (1.1). Client checks
  `Scoreboard_GetPlayerData( idx, "IsCommander" )`; the server independently rejects with
  `Player:GetIsCommander()`, which the base class defines as `false` and `Commander` overrides.
  The rejection does **not** erase a stored declaration — it is hidden while commanding and
  returns on logout, because losing it to an accidental chair-tap would be worse. Commanders
  still *see* everyone else's icons.
- **One flat icon colour, no declared-vs-default distinction.** An explicit product decision, not
  an oversight. `kIconColour` is RGB 255,225,187 — the cream of Hatta's *Lifeform Selector*, which
  never tinted anything (it applied a no-op `Color(1,1,1,1)`) and simply inherited the baked
  colour of the vanilla `ui/alien_hivestatus_commicons.dds` it drew from. Our source art is pure
  white, so `SetColor` reproduces that hue exactly and any other is a one-line change.
- **The atlas is Devnull's artwork**, from Enhanced Scoreboard (workshop 2597529958,
  ui/Devnull/Alien.dds). Shimizu Scoreboard ships a byte-identical copy and is where ours was
  taken from, but credit belongs to Devnull. Verified by md5.
- **Prowler is excluded.** The atlas was cropped to just the five vanilla rows (340x570); the
  source had eleven more. Cropping from the bottom keeps rows 0-4 at identical coordinates, so no
  Lua changed. Regenerate mips alpha-weighted if it is ever recut - transparent areas are RGB
  0,0,0 and a naive filter produces dark halos.

## Enhanced Scoreboard integration (1.2)

Devnull's Enhanced Scoreboard (workshop `2597529958`, files under `lua/Devnull_ESB/`) draws a
per-team counter bar. Shimizu Scoreboard carries a port of the same code, so both expose
`GUIScoreboard:UpdateTeam_EalIcons( teamObject )`.

**We substitute its input, never its output.** Its alien branch counts solely from
`teamObject.teamScores[i].StatusId` against `kPlayerStatus.Skulk` / `.SkulkEgg` and so on, so
during the pre-round we call it with shallow-copied records whose status fields carry each
player's declaration. Their own arithmetic then yields pick counts.

Three things force this shape, and none of them are negotiable:

- Their `EALitems` table is a **file-local**, so writing counts directly is impossible from here.
- Records are **copied, not mutated** — they come from the scoreboard's own cache and the Status
  column and player rows read them in the same frame.
- **Both** `StatusId` and `Status` are set. Enhanced Scoreboard compares `StatusId` against the
  enum; Shimizu string-matches `Status` via `GetCountByStatus`. Setting both serves either.

The hook is installed from inside the same `CallAfterFileLoad` as the others, because that is the
first moment the owning mod has finished loading and `GUIScoreboard.UpdateTeam_EalIcons` can be
tested for. Absent, nothing is hooked.

It is a `Replace` hook, so `Plugin:OnLifeformPickerEalIcons` **must always call through** to the
captured original — on every path, including the ones it declines to touch. Returning without
calling it would freeze their counter bar.

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
  `Show()` must come *after* the buttons are added.
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

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

```
lua/shine/extensions/lifeformpicker/{shared,server,client}.lua
ui/LifeformPicker/Alien.dds
```

Three Lua files and one texture. Keep it that way — the value of this extension over the
alternatives is that it is small enough to read in one sitting.

## Two constraints that decide the architecture

**1. It ships as a workshop mod, not a server-side folder drop.** Shine loads a plugin's
`client.lua` from the *client's* filesystem (`Shine_PluginSync` tells the client to
`EnableExtension`, which then loads the file locally). A server-only install yields a server
plugin with no UI and no texture. There is intentionally **no `lua/entry/*.entry`** — mod content
mounts into the virtual filesystem regardless, and an entry file only exists to bootstrap
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
- **Icons are flat `Color(1,1,1,1)`.** No tint, no declared-vs-default distinction. This was an
  explicit product decision, not an oversight.
- **Prowler is excluded** even though it is row 5 of the atlas.

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

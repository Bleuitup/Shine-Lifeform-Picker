# Shine Lifeform Picker

A [Shine](https://github.com/Person8880/Shine) extension for **Natural Selection 2**. Before a
round starts, aliens can declare which lifeform they intend to play. The declaration shows as an
icon on the scoreboard, visible to their own team and to spectators.

**It has no gameplay effect.** Nothing is reserved, spent, or enforced — you still evolve normally
during the round. It exists purely so a team can see its composition at a glance instead of
typing it into chat.

## What it does

- Every alien row on the scoreboard shows a lifeform icon during the pre-round.
- Everyone starts as **Skulk**. Undeclared players show a Skulk icon.
- Click **your own** icon on the open scoreboard to get a "Planned Lifeform" dropdown: Skulk,
  Gorge, Lerk, Fade, Onos. Pick one and your icon updates for everyone who can see it, tinted
  cream.
- Your pick **survives round transitions**. It never gets forgotten, but a round ending un-confirms
  it: the icon turns grey (the same shape, still your last choice) until you reconfirm it — click
  your icon again, whether to pick the same lifeform or a different one.
- By default icons disappear once the round starts, and reappear grey next pre-round. A server
  owner can change that with **`DisplayMode`** — see below — to keep them up until each player
  evolves, or for the whole round.
- Hovering **any** icon shows a tooltip — "Planned Lifeform: Lerk" — the same style NS2 uses for
  the comm badge, playtester badge, and skill icon on the scoreboard.

## When the icons appear

**You must be on the alien team, or spectating.** In the ready room or on marines you see nothing
— not even other aliens' icons. This is stricter than Hatta's *Lifeform Selector*, which only hid
icons from marines and so showed them to ready-room players too.

Beyond that, how long they stay up is the server's `DisplayMode` setting — see
[Server setting](#server-setting-displaymode) below. By default they are pre-round only.

If nothing appears and you expected it to, run this in the **client** console:

```bash
lifeformpicker_status
```

It reports whether the scoreboard hooks installed, the display mode in force, your team, the game
state, whether you can declare right now, and how many picks the client knows about — split into
confirmed, and how many have evolved this round.

## Server setting: DisplayMode

The one setting a server owner can change. It lives in
`config://shine/plugins/LifeformPicker.json`, created with defaults on first load:

```json
{
    "DisplayMode": 0
}
```

| Mode | Name | Behaviour |
|---|---|---|
| **0** | Pregame Only *(default)* | Icons show before the round and vanish the moment it starts. |
| **1** | Until First Lifeform | Icons carry into the round, and disappear for a player once they evolve past Skulk. |
| **2** | Full Game | Icons stay all round, picks can be changed at any time, and an evolved player's icon shows what they actually became. |

**Mode 1** hides an icon from the moment that player evolves into a Gorge, Lerk, Fade or Onos. It
is a latch, not a live reading — dying back down to a Skulk does **not** bring it back. Everything
resets when the round ends.

**Mode 2** is the only mode where picks can be changed mid-round. Once a player has evolved past
Skulk, their icon switches to showing **what they actually became**, greyed out — which is not
necessarily what they picked, since calling a Fade and getting one are different things. If they
then die back to a Skulk the icon keeps showing the last lifeform they actually reached, still
grey, until the round ends. Hovering such an icon says "Evolved: Fade" rather than "Planned
Lifeform: Fade".

In modes 1 and 2 a pick confirmed before the round **stays cream into the round** rather than
greying out at the start — the plan is still worth reading while the round is young. Everything
unconfirms when the round ends, in every mode.

Changes take effect on map change or `sh_reloadplugin lifeformpicker`; already-connected clients
are told the new mode immediately on reload.

## Who sees what

| | Sees icons | Can declare |
|---|---|---|
| Aliens | Yes | Yes |
| Alien commander | Yes | **No** |
| Spectators | Yes | No |
| Marines | **No** | No |

The commander has no lifeform to call while in the chair, so their row carries no icon and they
cannot declare. They still see everyone else's — arguably the person who most wants to know the
team's composition. An existing declaration is *hidden*, not erased: call Fade, take the chair,
log out later, and your Fade is still there.

Marines are filtered **server-side** — the data is never sent to their machine, rather than being
sent and hidden.

### Picks persist, confirmation does not

A pick is never forgotten once made — it is remembered across round transitions rather than
reverting to the Skulk default. What resets, both when a round starts and when it resets for the
next one, is only whether it counts as *confirmed*: the icon goes grey, keeping the same shape,
until you actively reconfirm it.

Reconfirming is the same action as declaring — click your icon and pick from the menu, including
picking the same lifeform you already had. There is no separate "confirm" button.

This reset is broadcast to every alien and spectator already connected, not just applied on the
server — a client that stays on the alien team across a round transition still gets told which
picks are now unconfirmed.

## Installation

This is a Shine extension and nothing else — the whole thing is
`lua/shine/extensions/lifeformpicker/` plus one texture. There is no `lua/entry/` bootstrap, no
`modEntry`, and no ModLoader file hook. Shine discovers it by scanning the virtual filesystem for
`lua/shine/extensions/*.lua`, so there is no manifest to edit, and it is enabled by default.

Enable or disable it like any Shine plugin:

```bash
sh_loadplugin lifeformpicker
```

Add it to the server's mod list like any other workshop mod. NS2 pushes it to connecting clients
automatically, which matters here because the icons and the pick menu are client-side.

## Layout

Standard NS2 Launch Pad project layout: `mod.settings` and `preview.jpg` sit one level above the
mod itself, and `output/` is the build Launch Pad publishes.

```
mod.settings                            workshop metadata: name, description, tags, publish id
preview.jpg                             workshop preview image
source/
  lua/shine/extensions/lifeformpicker/
    shared.lua                          plugin declaration + the two network messages
    server.lua                          authority, replication, round lifecycle
    client.lua                          scoreboard icons + the pick menu
  ui/LifeformPicker/
    Alien.dds                           lifeform silhouette atlas
output/                                 build output, not tracked in git
```

Paths inside `source/` are what the game sees once built, so `ui/LifeformPicker/Alien.dds` in the
Lua resolves correctly and `source/` itself never appears at runtime.

## Publishing

**`output/` is what Launch Pad uploads, and it is not in git.** A fresh clone has no `output/` at
all, and Launch Pad will report the output directory as empty until it is built.

There is no compilation step — the mod is Lua and one texture — so building is a straight copy of
`source/` into `output/`:

```bash
rm -rf output && mkdir -p output && cp -r source/. output/
```

`output/` must end up with `lua/` and `ui/` at *its* root, not `output/source/lua`.

Two things to watch:

- **`output/` does not follow branch switches.** Git leaves ignored files alone, so after
  `git checkout` it still holds whatever was last built. Rebuild before publishing or you will
  upload the wrong version.
- `.output-build-info` at the repo root records the branch and commit `output/` was built from.
  Check it against `git log -1` if you are unsure whether the build is current.

## The atlas

`ui/LifeformPicker/Alien.dds` is 340x570: a vertical strip of five 340x114 cells, in the order
Skulk, Gorge, Lerk, Fade, Onos — matching `Plugin.kLifeforms`, so a lifeform index is also its
texture row.

It was cut from the sixteen-row vanilla icon atlas shipped with *Shimizu Scoreboard*, used with
Shimizu's permission, whose remaining rows (Prowler, Shell, Spur, Veil and other structures) are
never sampled here. Cropping them off the **bottom** was deliberate: rows 0-4 keep the same
coordinates, so no Lua changed, and the visible art is not resampled. The mip chain was regenerated with an alpha-weighted filter, since the texture
stores RGB 0,0,0 in transparent areas and a naive average would drag dark halos into the
silhouette edges. That took the file from 3.3 MB to 1.0 MB.

Adding Prowler back would mean restoring its row, widening the network field's `integer (0 to 4)`
range, and appending to `kLifeforms`.

The artwork is pure white with the shape carried entirely in the alpha channel, which makes it a
clean tint target — `SetColor` multiplies, so white takes any hue exactly. `kIconColour` is set to
RGB 255,225,187, the cream of Hatta's *Lifeform Selector*: that mod applied a no-op
`Color(1,1,1,1)`, so its colour actually came from the baked pixels of the vanilla
`ui/alien_hivestatus_commicons.dds` it used. One colour for every row — no visual difference
between a declared pick and the assumed Skulk default.

Because the source art is white rather than pre-coloured, changing the whole look is a one-line
edit to `kIconColour`; `GUIScoreboard.kRedColor` (`Color(1, 0.494, 0, 1)`) gives the more
saturated alien team orange, for instance.

Within each 340-wide cell the silhouettes only span x 83-250 — the rest is transparent padding —
so the icon crops to one uniform window (`kCropLeft`/`kCropRight`) shared by every row. This is
deliberate: tight-cropping each lifeform to its own bounding box gives aspect ratios ranging from
0.90 to 1.78, and forcing those into a fixed-size box is what makes icons look stretched.

## Tuning the icon

All in `client.lua`:

| Constant | Default | Effect |
|---|---|---|
| `kIconHeight` | `19` | Icon height. `kIconWidth` must stay at ~1.474x this to keep the aspect. |
| `kIconWidth` | `28` | Icon width. |
| `kIconGap` | `4` | Gap between the icon and the Status column's right edge. |

The icon is a direct child of the Status column's own GUI item rather than positioned from
hard-coded column maths, so it tracks Status through the engine's own transform hierarchy and
follows resolution and scoreboard-width changes without adjustment. It sits to Status's **right**
so it does not collide with mods (such as Enhanced Scoreboard) that draw their own icons to the
left of it.

## Credits

The idea, and the click-your-icon-for-a-dropdown interaction, come from **Hatta's** discontinued
*Shine - Lifeform Selector*, used with his permission.

The lifeform artwork .dds file with the vanilla icons comes from *Shimizu Scoreboard*, used with
his permission.

This is an independent implementation rather than a fork of any of them.

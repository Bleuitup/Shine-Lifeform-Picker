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
- Click **your own** icon on the open scoreboard to get a dropdown: Skulk, Gorge, Lerk, Fade,
  Onos. Pick one and your icon updates for everyone who can see it.
- Icons disappear once the round starts, and all declarations are cleared for the next one.

## When the icons appear

Both conditions must hold, or the scoreboard looks completely untouched:

1. **You are on the alien team, or spectating.** In the ready room or on marines you see nothing —
   not even other aliens' icons.
2. **The round has not started.** Game state is `NotStarted`, `WarmUp`, `PreGame` or `Countdown`.

This is stricter than Hatta's *Lifeform Selector*, which only hid icons from marines and so showed
them to ready-room players too.

If nothing appears and you expected it to, run this in the **client** console:

```bash
lifeformpicker_status
```

It reports whether the scoreboard hooks installed, your team, the game state, whether icons
*should* be showing, and how many declarations the client has received.

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

## The atlas

`ui/LifeformPicker/Alien.dds` is 340x570: a vertical strip of five 340x114 cells, in the order
Skulk, Gorge, Lerk, Fade, Onos — matching `Plugin.kLifeforms`, so a lifeform index is also its
texture row.

It was cut from Shimizu Scoreboard's sixteen-row atlas, whose remaining rows (Prowler, Shell,
Spur, Veil and other structures) are never sampled here. Cropping them off the **bottom** was
deliberate: rows 0-4 keep byte-identical coordinates, so no Lua changed, and the visible art is
not resampled. The mip chain was regenerated with an alpha-weighted filter, since the texture
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
| `kIconGap` | `4` | Gap between the icon and the Status column. |

The icon is positioned off the Status column's own position rather than from hard-coded column
maths, so it follows resolution and scoreboard-width changes without adjustment.

## Credits

The idea, and the click-your-icon-for-a-dropdown interaction, come from **Hatta's** discontinued
*Shine - Lifeform Selector*. The lifeform artwork is from **Shimizu Scoreboard**. This is an
independent implementation rather than a fork of either.

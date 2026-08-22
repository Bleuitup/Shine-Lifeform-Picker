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
| Spectators | Yes | No |
| Marines | **No** | No |

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

### Getting the files to clients

Like any Shine extension with a client-side component, the extension folder has to exist on the
**clients** as well as the server: on connect the server sends `Shine_PluginSync`, and each client
then loads `client.lua` from its own filesystem. A copy that only exists on the server gives you a
working server-side plugin with no icons and no texture.

In practice that means the extension folder and `ui/` need to travel in whatever mod the server
has clients mount — the same requirement as any other client-facing Shine plugin. Dropping it into
a server's local Shine directory alone is not enough.

## Compatibility

Compatible with **Shimizu Scoreboard** and other scoreboard mods.

Most scoreboard mods claim `lua/GUIScoreboard.lua` through ModLoader — Shimizu takes it in
`replace` mode, which owns the whole file. This extension never hooks the file at all. It patches
the class methods at runtime via `Shine.Hook.SetupClassHook`, so it layers on top of whichever mod
owns the file rather than competing with it.

Shimizu has its own lifeform selector. If you run both you will get two sets of icons; disable one.

## Layout

```
lua/shine/extensions/lifeformpicker/
  shared.lua    plugin declaration + the two network messages
  server.lua    authority, replication, round lifecycle
  client.lua    scoreboard icons + the pick menu
ui/LifeformPicker/
  Alien.dds     lifeform silhouette atlas
```

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

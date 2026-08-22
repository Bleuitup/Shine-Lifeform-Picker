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

## Who sees what

| | Sees icons | Can declare |
|---|---|---|
| Aliens | Yes | Yes |
| Spectators | Yes | No |
| Marines | **No** | No |

Marines are filtered **server-side** — the data is never sent to their machine, rather than being
sent and hidden.

## Installation

This ships as a workshop mod, not as a folder dropped into a server's Shine install. That is a
hard requirement, not a preference: Shine loads a plugin's `client.lua` from the *client's own*
filesystem, so clients must physically have these files. A server-only copy would give you a
server-side plugin with no UI and no texture.

1. Publish the repository contents as an NS2 workshop mod.
2. Add the mod to the server's mod list. Clients download it automatically on connect.
3. Shine discovers the extension by scanning the virtual filesystem for
   `lua/shine/extensions/*.lua`, so there is no manifest to edit. It is enabled by default.

Enable or disable it like any Shine plugin:

```bash
sh_loadplugin lifeformpicker
```

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

`ui/LifeformPicker/Alien.dds` is 340x1824: a vertical strip of sixteen 340x114 cells. Rows 0-4 are
Skulk, Gorge, Lerk, Fade, Onos, matching the order of `Plugin.kLifeforms`, so a lifeform index is
also its texture row.

The artwork is pure white with the shape carried entirely in the alpha channel. It is drawn at
flat full opacity — no tinting, and no visual difference between a declared pick and the assumed
Skulk default.

Row 5 is Prowler. It is deliberately not exposed; adding it would mean widening the network
field's `integer (0 to 4)` range and appending to `kLifeforms`.

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

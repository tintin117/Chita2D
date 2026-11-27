# Editing the isometric arenas

The arenas are scenes in `scenes/levels/`. Open one in Godot, edit, save, then play it:
Main menu > Practice vs Bots > Arena.

| Arena | Scene |
|---|---|
| Four Quarters | `iso_arena.tscn` |
| Pillar Court | `pillar_court.tscn` |
| Three Bridges | `three_bridges.tscn` |
| The Wheel | `wheel.tscn` |
| Archipelago | `archipelago.tscn` |

The Colosseum is drawn by code (`scripts/world/colosseum.gd`) and is not editable this way.

## New arena

Duplicate a scene in `scenes/levels/`, edit it, and add a row to `Arenas.LIST` in `scripts/world/arenas.gd`.
Add rows at the end: the menu sends the row number to other players.

## Layers

Select a layer in the Scene dock, then paint in the **TileMap** panel at the bottom.

| Node | What it does in game |
|---|---|
| `Ground` | A painted tile is walkable. **No tile = deadly water.** Erase to cut holes, paint to add land. |
| `Props` | **Solid.** Blocks walking and shots; a dash goes through. One tile = one obstacle. |
| `Decor` | Looks only (flowers, grass tufts). |
| `Water` | Looks only (water, rocks in the water). |

## Hand-placed sprites (off the grid)

Drag `scenes/levels/iso_prop.tscn` onto the `FreeProps` node. In the Inspector:

- `tile`: which sprite, 0-120, counted left to right, top to bottom in `assets/isometric_tileset/spritesheet.png`
  (11 per row; some of these numbers differ from the file names in `separated_images`).
- `solid_radius`: 0 = walk-through; above 0 = a solid circle of that radius in pixels (about 20 for a rock).

Move it anywhere; duplicate with Ctrl+D. Only direct children of `FreeProps` can be solid.

## Markers

- `Spawns/*`: respawn points, 8 of them. In a team match the first four in the list are one team, the rest the other.
- `Center`: where the crown and rare drops appear. `crown_hold_radius` on the root node is how close to it a bot
  holding the crown stays.

## Rules that keep it playable

- Every spawn must be on ground that connects to `Center` (the game logs a warning otherwise).
- Keep spawns more than 400 px apart.
- Make bridges at least 3 tiles wide, or bots cannot walk them.
- A dash carries about 240 px: a water gap under about 200 px can be dashed over.
- Keep the level in positive coordinates (right of and below the origin), within 8192 x 4992 px.
- The radar shows an area of about 2450 x 1450 px around `Center`.
- After editing, run the `iso_level` test suite. It checks every arena in the list.

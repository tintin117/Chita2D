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
| Colosseum | `colosseum.tscn` |
| Brookside Village | `market_square.tscn` |
| Forest Shrine | `forest_shrine.tscn` |

Brookside’s main fight is at the market bend. A service lane skirts the back of the shops and the orchard path wraps around the south. Keep the sprite foot and cover center on the same point when placing village props. The `GroundShadow` child follows its prop. Size the shadow to the wall, trunk or legs at ground level.

Forest Shrine uses the painted `Ground` layer for walking and bot routes. The stair nodes draw on that layer’s 2:1 axes. Place columns and ruined walls as solid cover, and keep the tree line outside the routes to the crown.

Colosseum has a continuous sand floor with staggered timber barricades under `FreeProps`. Its seating, arcade walls, portcullises, bridge threshold, and hard collision rim share the ellipse in `scenes/levels/colosseum_rim.gd`. Keep the painted floor aligned with that rim when reshaping the bowl. The canyon surrounds the bowl, and both gates are barred during matches.

The scene-based arenas use a 2:1 ground grid. The original heroes stay upright and sort by their feet. Keep taller cover on the same Y-sorted plane, scale uniformly, and align its visible base to the collider. Shore faces extend down from the painted ground and are generated from the exposed front edges. They sit below the walkable surface.

Use SmallScale Interactive's [Top-Down Pixel Characters 1](https://assetstore.unity.com/packages/2d/characters/top-down-pixel-characters-1-288147) and the publisher's [2D Fantasy Tileset](https://assetstore.unity.com/packages/2d/environments/2d-fantasy-tileset-336410) as the character and environment references. For architecture, compare both ground axes on the paving and wall bases. Match door and prop scale to a standing hero at combat zoom and check the overlap when the hero walks in front of and behind the prop. The 2:1 editor grid establishes the floor angle. Material detail, shading, silhouettes, and cast shadows establish the environment style.

`arena_surfaces.png` contains the original projected floor and water tiles used for this redesign, with six variants per material. `court_pillar.png` and `court_pillar_broken.png` are original hand-drawn pixel sprites. The original prop atlas remains available in the TileSet.

## Arena Builder dock

Open **Arena Builder** in the right dock and pick an arena from the map dropdown. Switching maps opens the selected scene in the 2D editor and turns off placement. If the viewport opens on water, click **Select crown**, then press **F** over the 2D viewport to frame the arena center.

1. Turn on **Place in viewport**. Pick **Solid cover**, **Decor**, **Team spawn**, or **Crown center**.
2. Pick a prop thumbnail or the spawn to move. **Prop size** starts at 100% of the selected asset’s recommended size and can be set from 50% to 200%. The preview shows the sprite, contact point and scaled collision radius. A red marker indicates water.
3. Click the viewport to place. Props are selectable instances under `FreeProps`. **Snap to ground cell** centers props and markers on the grid. A snapped prop replaces the existing snapped prop or painted tile in its category at that cell. Turn snap off to place at the cursor. Each click is undoable.
4. Click **Validate arena** to see the bot routes and reported spawn problems. Repeat validation after terrain edits to refresh the shore and routes. Turn off **Place in viewport** to resume normal selection and TileMap painting.

For the camera reference, open [Projection Lab](../scenes/levels/projection_lab.tscn) and press **F6**. It uses the current arena tiles, Paladin, Ranger, and a tall stone. Press **1** or **2** for the game’s normal zoom endpoints, **G** for the diamond guide, and **C** to compare Purify’s ground ring with the tile grid.

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

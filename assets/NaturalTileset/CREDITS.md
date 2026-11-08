# Natural tileset

`natural_tileset.png`, 32x32 pixel-art tiles for `data/tilesets/natural_tileset.tres` (sourced for GR2-27, to replace/extend `data/tilesets/factory_tileset.tres` per GR2-21).

| Tile (atlas coords) | Content | Source |
|---|---|---|
| 0:0 | dirt | Cropped from [Grass on dirt & stone tileset](https://opengameart.org/content/grass-on-dirt-stone-tileset) (hitmanrec), CC0 |
| 1:0 | rock | Cropped from the same CC0 pack |
| 0:1 | dirt/grass edge (straight, grass above) | Cropped from the same CC0 pack |
| 1:1 | rock/grass edge (straight, grass above) | Cropped from the same CC0 pack |
| 2:0 | grass | Drawn for this project (procedural pixel fill using the grass palette sampled from the CC0 pack above) |
| 2:1 | ore deposit (minesite marker) | Drawn for this project: the rock tile (1:0) with procedural silver/copper flecks, same palette family |

Credit is not required for CC0 but is given anyway, matching the convention in `assets/items/CREDITS.md`.

Notes for whoever wires this into GR2-21:
- Only straight-edge transitions are provided (grass on top, biome below). Godot's `TileMapLayer` supports per-cell `flip_h` / `flip_v` / `transpose` on a placed tile, so the other 3 orientations of each edge tile don't need separate art — they can reuse these two transition tiles with a transform instead of new source images.
- No rock/dirt direct transition tile was made (only each paired with grass); if clustering puts rock next to dirt directly, that border will look harder-edged than the grass transitions until a rock/dirt tile is added.

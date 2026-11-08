# Natural tileset

`natural_tileset.png`, 32x32 pixel-art tiles for `data/tilesets/natural_tileset.tres` (sourced for GR2-27, to replace/extend `data/tilesets/factory_tileset.tres` per GR2-21).

| Tile (atlas coords) | Content | Source |
|---|---|---|
| 0:0 | dirt | Cropped from [Grass on dirt & stone tileset](https://opengameart.org/content/grass-on-dirt-stone-tileset) (hitmanrec), CC0 |
| 1:0 | rock | Cropped from the same CC0 pack |
| 2:0 | grass | Drawn for this project (procedural pixel fill using the grass palette sampled from the CC0 pack above) |
| 3:0 | rock/dirt straight edge (rock above, dirt below) | Composited from the 0:0 and 1:0 tiles above, using the same border shape as the 0:1 edge tile |
| 0:1 | dirt/grass straight edge (grass above, dirt below) | Cropped from the same CC0 pack |
| 1:1 | rock/grass straight edge (grass above, rock below) | Composited from the 1:0 and 2:0 tiles above, using the border shape cut from the 0:1 edge tile (the originally committed 1:1 tile was a mis-cropped plain rock tile with no grass at all — this replaces it) |
| 2:1 | dirt/grass outer corner (grass wraps the top-left corner) | Composited from the 0:0 and 2:0 tiles above, using an L-shaped border built by combining the 0:1 edge border with a 90°-rotated copy of itself |
| 3:1 | rock/grass outer corner (grass wraps the top-left corner) | Composited from the 1:0 and 2:0 tiles above, using the same L-shaped border as 2:1 |

Credit is not required for CC0 but is given anyway, matching the convention in `assets/items/CREDITS.md`.

Notes for whoever wires this into GR2-21:
- Every edge/corner tile here is drawn with grass/the "foreground" biome at the top (edges) or top-left (corners). `TileMapLayer` supports per-cell `flip_h` / `flip_v` / `transpose` on a placed tile, so the other 3 orientations of each edge and the other 3 rotations of each corner can reuse this art via a transform instead of needing more source images.
- `GridMap2D`'s current `GROUND_TILES` / `MOSSY_TILES` constants (`scripts/world/grid_map_2d.gd`) hardcode atlas coordinates from `factory_tileset.tres`'s layout (e.g. `Vector2i(3, 0)`), which do not exist in this tileset. Swapping the `TileSet` resource alone is not enough — those constants (and the per-cell random pick in `_build_ground()`) need to be updated to reference this atlas's coordinates and to use the new edge/corner tiles at biome borders. That logic is GR2-21's scope, not this ticket's.
- No corner tile exists yet for a direct rock/dirt corner (only each paired with grass, plus one straight rock/dirt edge) — if clustering ever puts a rock/dirt corner directly adjacent with no grass between, that corner will look harder-edged until one is added.

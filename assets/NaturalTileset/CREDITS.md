# Natural tileset

`natural_tileset.png`, 32x32 pixel-art tiles for `data/tilesets/natural_tileset.tres`, used by `GridMap2D` (`scenes/main.tscn`) as the ground tileset (sourced for GR2-27, replacing the old `IndustrialScifiTileset` / `data/tilesets/factory_tileset.tres` per GR2-21).

| Tile (atlas coords) | Content | Source |
|---|---|---|
| 0:0 | dirt | Cropped from [Grass on dirt & stone tileset](https://opengameart.org/content/grass-on-dirt-stone-tileset) (hitmanrec), CC0 |
| 1:0 | rock | Cropped from the same CC0 pack |
| 2:0 | grass | Drawn for this project (procedural pixel fill using the grass palette sampled from the CC0 pack above) |
| 3:0 | rock/dirt straight edge (rock above, dirt below) | Composited from the 0:0 and 1:0 tiles above, using the same border shape as the 0:1 edge tile |
| 4:0 | minesite (ore vein in rock) | Drawn for this project: the rock tile with procedural silver/copper flecks |
| 0:1 | dirt/grass straight edge (grass above, dirt below) | Cropped from the same CC0 pack |
| 1:1 | rock/grass straight edge (grass above, rock below) | Composited from the 1:0 and 2:0 tiles above, using the border shape cut from the 0:1 edge tile (the originally committed 1:1 tile was a mis-cropped plain rock tile with no grass at all — this replaces it) |
| 2:1 | dirt/grass outer corner (grass wraps the top-left corner) | Composited from the 0:0 and 2:0 tiles above, using an L-shaped border built by combining the 0:1 edge border with a 90°-rotated copy of itself |
| 3:1 | rock/grass outer corner (grass wraps the top-left corner) | Composited from the 1:0 and 2:0 tiles above, using the same L-shaped border as 2:1 |

Credit is not required for CC0 but is given anyway, matching the convention in `assets/items/CREDITS.md`.

`GridMap2D` uses the grass straight edges in four orientations. Corner and rock/dirt edge art is available for future use; those borders currently remain hard-edged.

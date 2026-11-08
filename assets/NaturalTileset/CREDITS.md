# Natural tileset

`natural_tileset.png`, 32x32 pixel-art tiles for `data/tilesets/natural_tileset.tres`, used by `GridMap2D` (`scenes/main.tscn`) as the ground tileset (sourced for GR2-27, replacing the old `IndustrialScifiTileset` / `data/tilesets/factory_tileset.tres` per GR2-21).

| Tile (atlas coords) | Content | Source |
|---|---|---|
| 0:0 | dirt | Cropped from [Grass on dirt & stone tileset](https://opengameart.org/content/grass-on-dirt-stone-tileset) (hitmanrec), CC0 |
| 1:0 | rock | Cropped from the same CC0 pack |
| 0:1 | dirt/grass edge (straight, grass above) | Cropped from the same CC0 pack |
| 1:1 | rock/grass edge (straight, grass above) | Cropped from the same CC0 pack |
| 2:0 | grass | Drawn for this project (procedural pixel fill using the grass palette sampled from the CC0 pack above) |
| 2:1 | minesite (ore vein in rock) | Drawn for this project: the rock tile's own shape (1:0) recolored to an amber/copper ore palette, so a minesite reads as "rock with embedded ore" regardless of which biome it overlays |

Credit is not required for CC0 but is given anyway, matching the convention in `assets/items/CREDITS.md`.

Notes (GR2-21, wired up in `GridMap2D._generate_ground`):
- Only straight-edge transitions are provided (grass on top, biome below). `GridMap2D` reuses these two transition tiles for all 4 orientations via the atlas's built-in `TileSetAtlasSource.TRANSFORM_FLIP_H` / `TRANSFORM_FLIP_V` / `TRANSFORM_TRANSPOSE` alternative-tile flags, passed as the `alternative_tile` argument to `set_cell`, instead of new source images.
- No rock/dirt direct transition tile was made (only each paired with grass), so a direct rock/dirt border (no grass between them) stays a harder edge than the grass transitions.

# Natural tileset

`natural_tileset.png`, 32x32 pixel-art tiles for `data/tilesets/natural_tileset.tres`, used by `GridMap2D` (`scenes/main.tscn`) as the ground tileset (sourced for GR2-21/GR2-27, swapped to Kenney art per GR2-43 after the original OpenGameArt tiles didn't read well).

| Tile (atlas coords) | Content | Source |
|---|---|---|
| 0:0 | dirt | Cropped from [Desert Shooter Pack](https://kenney.nl/assets/desert-shooter-pack) (Kenney, CC0), tile (1,3) of `PNG/Tiles/Tilemap/tilemap_packed.png`, upscaled 2x (16px source -> 32px project tiles) |
| 1:0 | rock | Same pack, tile (1,1), upscaled 2x |
| 2:0 | grass | Same pack, tile (6,1), upscaled 2x |
| 4:0 | minesite (ore vein in rock) | Same pack: the dirt tile (1,3) with the crystal prop at (3,3) composited on top, so a minesite reads as "ore sticking out of the ground" regardless of which biome it overlays |
| 0:1 | rock/dirt edge (rock above, dirt below) | Same pack, tile (1,2), upscaled 2x and flipped vertically (the source art has dirt on top; flipping once here keeps `GridMap2D`'s `EDGE_TRANSFORMS` convention of the blended-toward color sitting on top at the identity orientation) |
| 1:1 | grass/dirt edge (grass above, dirt below) | Same pack, tile (6,2), upscaled 2x and flipped vertically, same reason as above |

Kenney's CC0 tiles don't require credit but it is given anyway, matching the convention in `assets/items/CREDITS.md`. License: [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/).

Notes (GR2-43, wired up in `GridMap2D._generate_ground`):
- Kenney's sheet pairs each ground color (rock, grass) with its own dirt transition tile, rather than every biome transitioning into one shared "overlay" biome. So unlike the previous art, dirt is the common tile both rock and grass blend toward: a rock or grass cell touching dirt gets the matching edge tile (`ROCK_DIRT_EDGE` / `GRASS_DIRT_EDGE`), oriented toward the dirt side; dirt cells are never edge-tiled.
- Only straight-edge transitions are provided (one biome on top, dirt below in the baked art). `GridMap2D` reuses these two transition tiles for all 4 orientations via the atlas's built-in `TileSetAtlasSource.TRANSFORM_FLIP_H` / `TRANSFORM_FLIP_V` / `TRANSFORM_TRANSPOSE` alternative-tile flags, passed as the `alternative_tile` argument to `set_cell`, instead of new source images.
- No direct rock/grass transition tile was made (only each paired with dirt), so a direct rock/grass border (no dirt between them) stays a harder edge than the dirt transitions.
- No corner tiles were carried over from the previous tileset revision: they were unused by `GridMap2D` (a corner cell just blends toward the first direction checked, see `EDGE_DIRECTIONS`), so they weren't worth sourcing again.

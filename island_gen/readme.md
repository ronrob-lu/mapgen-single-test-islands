# Island Gen

A Minetest/Luanti mod that generates a specific island map configuration when the world starts.

## Features

- Generates exactly 4 natural-looking islands centered around 0,0,0
- Water level is exactly at 0
- Maximum island width is approximately 150 blocks
- Fixed maximum island height of 17 blocks
- Coastlines are approximately between 20 and 75 blocks from the center
- Biome Distribution:
  - Island 1: Sandy beach biome
  - Island 2: Grasslands/dirt with trees, sandy beaches at coastlines
  - Islands 3 & 4: Two random biomes selected from available Minetest biomes at mod load
- No underwater structures or underground caves. Islands sit on a sea floor extending to depth y=-30.
- Everything outside the islands is water extending to map boundaries, with a stone floor at y=-30.

## Installation
Drop the `island_gen` directory into your `mods` folder in Minetest/Luanti and enable it for your world.

## Usage Notes
This mod sets the mapgen to `flat` to cleanly generate the ocean.
The map generation logic will only generate the 4 islands around the center (0,0,0) exactly once when a player joins. All other map areas will be sea level water with air above.

## Source Mods Referenced
This mod references patterns from `lvm_example` and `aqua_world` for chunk-based voxel manipulation.

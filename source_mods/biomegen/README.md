# Biome Generator (`biomegen`)
Mod for Luanti 5.12+, created by gaelysam (Gaël de Sailly) in November 2020, licensed under LGPLv3.0.
Version 2.3.0 (March 2026)

Biome Generator is a library reproducing closely the biome generator provided by Luanti's core, but in Lua. Also includes an optional elevation adjustment parameter (*Lapse rate*).

It allows to use the biome systems on Lua mapgens (that have no access to core biome system *yet*). Since it reads registered biomes and decorations, it should be compatible with all mods adding biomes/decos.

It now supports both server and mapgen environment.

# Include it in your mapgen

`biomegen` should be triggered during mapgen function, after the loop, but before writing to the map.

Your mapgen should generate only these 4 nodes:

- Stone (`mapgen_stone`)
- Water (`mapgen_water_source`)
- River water (`mapgen_river_water_source`)
- `air`

It is recommended to use these mapgen aliases, instead of `default:stone`, `default:water`... Mapgen aliases are recognized by all games and thus are much better for game-wise compatibility.

All other nodes will be ignored, no biome will be placed ontop of them.

You should add `biomegen` as a dependancy of your mod (optional or mandatory).

## API
Description of usual function parameters:

- `data`: Data containing the generated mapchunk
- `area`: VoxelArea helper object for data. `area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})`
- `vm`: VoxelManip object
- `minp`: minimal coordinates of the chunk being generated, e.g. `{x=48, y=-32, z=208}`
- `maxp`: maximal coordinates of the chunk being generated, e.g. `{x=127, y=47, z=287}`
- `seed`: world-specific seed

All functions are available in both *Server* and *Mapgen* environments.

### `biomegen.generate_all(data, area, vm, minp, maxp, seed)`
All-in-one function to generate *biomes*, *decorations*, *ores* and *dust*. Includes a call to `vm:set_data` so no need to do it again. Using core function `core.generate_ores` for ores, so does not support biome-specific ores.

### `biomegen.generate_biomes(data, area, minp, maxp)`
Generates biomes in `data`, according to biomes that have been registered using `core.register_biome`.

### `biomegen.place_all_decos(data, area, vm, minp, maxp, seed)`
Generates decorations directly in `vm` (but reads `data` to know where to place them), according to decorations that have been registered using `core.register_decoration`.

### `biomegen.dust_top_nodes(data, area, vm, minp, maxp)`
Drops 'dust' (usually snow) on biomes that require it. Like above, generates directly in `vm` but reads from `data`. If you used `place_all_decos` to generate decorations, you should update `data` from the `vm`:

```lua
vm:get_data(data)
```

### `biomegen.gennotify(feature, pos)`
Adds an entry in gen notify in the field `feature` (`dungeon`, `cave_begin`, ..., also `decoration#id`). No effect if the feature is not requested in `core.set_gen_notify`.

### `biomegen.set_lapse_rate(lr)`
Sets lapse rate parameter, that is, how much temperature decreases with elevation for every node. `0` is default value and means temperature does not depend on elevation (behaviour of core's biomegen). Usual values `0`-`0.5`. Should be called **only at init time!**

### `biomegen.get_lapse_rate()`
Returns lapse rate parameter.

### `biomegen.skip_chunk(minp, maxp)`
Does not generate biomes but updates mapgen objects (`biomemap`, `heatmap`, `humiditymap`, `heightmap` and `gennotify`) so that other mods can use them without crashing. Use this function in the mapgen loop when skipping an empty chunk.

### `core.get_mapgen_object(objname)`
The following objects are updated to take into account what Biomegen generates:

- `biomemap`
- `heatmap`
- `humiditymap`
- `heightmap`
- `gennotify`

The behaviour of the function is otherwise unchanged.

### `core.get_biome_data(pos)`
Takes into account elevation if lapse rate is non-zero. The behaviour of the function is otherwise unchanged.

## Examples
These examples would run under the mapgen environment.

### Using `biomegen.generate_all`
```lua
local data = {}

core.register_on_generated(function(vm, minp, maxp, seed)
	local emin, emax = vm:get_emerged_area()
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	vm:get_data(data)

	local c_stone = core.get_content_id("mapgen_stone")
	local c_water = core.get_content_id("mapgen_water_source")

	------------------------
	-- [MAPGEN LOOP HERE] --
	------------------------

	-- Generate biomes, decorations, ores and dust
	biomegen.generate_all(data, area, vm, minp, maxp, seed)

	-- Calculate lighting for what has been created.
	vm:calc_lighting()
	-- Liquid nodes were placed so set them flowing.
	vm:update_liquids()
end)
```

### Equivalent with all functions
```lua
local data = {}

core.register_on_generated(function(vm, minp, maxp, seed)
	local emin, emax = vm:get_emerged_area()
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	vm:get_data(data)

	local c_stone = core.get_content_id("mapgen_stone")
	local c_water = core.get_content_id("mapgen_water_source")

	------------------------
	-- [MAPGEN LOOP HERE] --
	------------------------

	-- Generate biomes in 'data', using biomegen mod
	biomegen.generate_biomes(data, area, minp, maxp)

	-- Write content ID data back to the voxelmanip.
	vm:set_data(data)
	-- Generate ores using core's function
	core.generate_ores(vm, minp, maxp)
	-- Generate decorations in VM (needs 'data' for reading)
	biomegen.place_all_decos(data, area, vm, minp, maxp, seed)
	-- Update data array to have ores/decorations
	vm:get_data(data)
	-- Add biome dust in VM (needs 'data' for reading)
	biomegen.dust_top_nodes(data, area, vm, minp, maxp)

	-- Calculate lighting for what has been created.
	vm:calc_lighting()
	-- Liquid nodes were placed so set them flowing.
	vm:update_liquids()
end)
```

### Mapgen example
[`lvm_example`](https://content.luanti.org/packages/ROllerozxa/lvm_example/) provides a minimal working example of a mapgen using `biomegen`. Try it!

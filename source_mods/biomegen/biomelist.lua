-- biomelist.lua

local core_cid = core.get_content_id
local function cid(name)
	if not name then
		return
	end
	local result
	pcall(function() --< try
		result = core_cid(name)
	end)
	if not result then
		print("[biomegen] Node " .. name .. " not found!")
	end
	return result
end

local function fix_biome(a)
	local b = {}
	b.name = a.name or ""
	b.id = core.get_biome_id(b.name) or 0

	if a.node_dust then
		b.node_dust_name = a.node_dust
		b.node_dust = cid(a.node_dust)
	end

	b.node_top = cid(a.node_top) or cid("mapgen_stone")
	b.depth_top = tonumber(a.depth_top or 0)

	b.node_filler = cid(a.node_filler) or cid("mapgen_stone")
	b.depth_filler = tonumber(a.depth_filler or 0)

	b.node_stone = cid(a.node_stone) or cid("mapgen_stone")

	b.node_water_top = cid(a.node_water_top) or cid("mapgen_water_source")
	b.depth_water_top = tonumber(a.depth_water_top or 0)

	b.node_water = cid(a.node_water) or cid("mapgen_water_source")
	b.node_river_water = cid(a.node_river_water) or cid("mapgen_river_water_source")

	b.node_riverbed = cid(a.node_riverbed) or cid("mapgen_stone")
	b.depth_riverbed = tonumber(a.depth_riverbed or 0)

	-- b.node_cave_liquid = ...
	-- b.node_dungeon = ...
	-- b.node_dungeon_alt = ...
	-- b.node_dungeon_stair = ...

	b.min_pos = a.min_pos
			and {x=tonumber(a.min_pos.x), y=tonumber(a.min_pos.y), z=tonumber(a.min_pos.z)}
			or {x=-31000, y=-31000, z=-31000}
	if a.y_min then
		b.min_pos.y = math.max(b.min_pos.y, tonumber(a.y_min))
	end
	b.max_pos = a.max_pos
			and {x=tonumber(a.min_pos.x), y=tonumber(a.min_pos.y), z=tonumber(a.min_pos.z)}
			or {x=31000, y=31000, z=31000}
	if a.y_max then
		b.max_pos.y = math.min(b.max_pos.y, tonumber(a.y_max))
	end

	b.vertical_blend = tonumber(a.vertical_blend or 0)

	b.heat_point = tonumber(a.heat_point or 50)
	b.humidity_point = tonumber(a.humidity_point or 50)
	b.weight = a.weight and tonumber(a.weight)

	return b
end

local biomes = {}
local biome_none -- biomes: list of all biomes ; biome_none: default biome
local biome_ybounds = {} -- Set of Y positions that can be biome boundaries (keys of the table). Associated values are the list of possible biomes at this position, or boolean "false" if not calculated yet.
-- biome_lookup[y] is a list of possible biomes at position y (memoization)
local biome_lookup = setmetatable({}, {
	__index = function(t, y)
		local closest_bound = -math.huge
		local ybiomes
		for ybound, blist in pairs(biome_ybounds) do
			if ybound <= y and ybound > closest_bound then
				closest_bound = ybound
				ybiomes = blist
			end
		end

		if not ybiomes then -- Generate biome list at y=ybound
			ybiomes = {}
			biome_ybounds[closest_bound] = ybiomes
			for id, b in pairs(biomes) do
				if closest_bound >= b.min_pos.y and closest_bound <= b.max_pos.y+b.vertical_blend then
					ybiomes[id] = b
				end
			end
		end

		t[y] = ybiomes
		return ybiomes
	end,
})

local function make_biomelist()
	local nbiomes = 0
	for id, biome_raw in pairs(core.registered_biomes) do
		local biome = fix_biome(biome_raw)
		biomes[id] = biome
		nbiomes = nbiomes + 1

		biome_ybounds[math.ceil(biome.min_pos.y)] = false
		biome_ybounds[math.floor(biome.max_pos.y+biome.vertical_blend+1)] = false
	end

	biome_none = fix_biome({}) -- For default biome
	core.log("info", "[biomegen] Loaded " .. nbiomes .. " biomes.")
end

local function calc_biome_from_noise(heat, humid, pos)
	local biome_closest = nil
	local biome_closest_blend = nil
	local dist_min = 31000
	local dist_min_blend = 31000

	for _, biome in pairs(biome_lookup[math.floor(pos.y)]) do
		local min_pos, max_pos = biome.min_pos, biome.max_pos
		if pos.x >= min_pos.x and pos.x <= max_pos.x
				and pos.z >= min_pos.z and pos.z <= max_pos.z then
			local d_heat = heat - biome.heat_point
			local d_humid = humid - biome.humidity_point
			local dist = d_heat*d_heat + d_humid*d_humid -- Pythagorean distance
			if biome.weight then
				dist = dist / biome.weight
			end

			if pos.y <= max_pos.y then -- Within y limits of biome
				if dist < dist_min then
					dist_min = dist
					biome_closest = biome
				end
			elseif dist < dist_min_blend then -- Blend area above biome
				dist_min_blend = dist
				biome_closest_blend = biome
			end
		end
	end

	if biome_closest_blend and dist_min_blend <= dist_min then
		-- Carefully tune pseudorandom seed variation to avoid single node dither
		-- and create larger scale blending patterns similar to horizontal biome
		-- blend.
		local seed = math.floor(pos.y + (heat+humid) * 0.9)
		local rng = PseudoRandom(seed)
		if rng:next(0, biome_closest_blend.vertical_blend) >= pos.y - biome_closest_blend.max_pos.y then
			return biome_closest_blend
		end
	end

	return biome_closest or biome_none
end

return make_biomelist, calc_biome_from_noise

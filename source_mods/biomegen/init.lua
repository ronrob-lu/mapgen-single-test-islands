-- biomegen/init.lua

local modpath = core.get_modpath(core.get_current_modname())
local thread
if core.register_mapgen_script then
	core.register_mapgen_script(modpath .. "/init.lua")
	thread = "main"
else
	thread = "mapgen"
end

local make_biomelist, calc_biome_from_noise = dofile(core.get_modpath(core.get_current_modname()) .. "/biomelist.lua")
local make_decolist = dofile(core.get_modpath(core.get_current_modname()) .. "/decorations.lua")

local np_filler_depth = {
	offset = 0,
	scale = 1.2,
	spread = {x=150, y=150, z=150},
	seed = 261,
	octaves = 3,
	persist = 0.7,
	lacunarity = 2.0,
}

local nobj_filler_depth, nobj_heat, nobj_heat_blend, nobj_humid, nobj_humid_blend
local nvals_filler_depth = {}
local nvals_heat = {}
local nvals_heat_blend = {}
local nvals_humid = {}
local nvals_humid_blend = {}

local water_level = tonumber(core.get_mapgen_setting('water_level'))
local lapse_rate = 0
local function set_lapse_rate(lr)
	if type(lr) ~= "number" then
		return
	end
	lapse_rate = lr
	core.ipc_set("biomegen:lapse_rate", lr)
end

local function get_lapse_rate()
	return core.ipc_get("biomegen:lapse_rate") or lapse_rate
end

local init_mapgen = false
local init_biomes = false

local c_ignore
local c_air
local c_stone
local c_water
local c_rwater

local biomes, decos

local gennotify_flags = {}

if thread == "main" then
	core.set_gen_notify('custom', nil, {
		"biomegen:biomemap",
		"biomegen:heightmap",
		"biomegen:heatmap",
		"biomegen:humidmap",
		"biomegen:gennotify",
	})
end

local walkable = {}
local liquid = {}
local dustable = {}

local function initialize_biome_data()
	core.log("info", "[biomegen] Initializing")

	init_biomes = true

	lapse_rate = get_lapse_rate()

	local gennotify_flagstr, gennotify_decolist = core.get_gen_notify()
	local notify_decos = false
	for _, v in ipairs(gennotify_flagstr:split(',')) do
		v = v:trim()
		if v == "decoration" then
			notify_decos = true
		else
			gennotify_flags[v] = true
		end
	end

	if notify_decos then
		for _, v in ipairs(gennotify_decolist) do
			gennotify_flags["decoration#" .. v] = true
		end
	end

	make_biomelist()
	decos = make_decolist(notify_decos and gennotify_decolist or {})

	for name, ndef in pairs(core.registered_nodes) do
		if ndef.walkable then
			local cid = core.get_content_id(name)
			walkable[cid] = true
			local dtype = ndef.drawtype
			if dtype == "normal" or dtype == "allfaces"
					or dtype == "allfaces_optional" or dtype == "glasslike"
					or dtype == "glasslike_framed" or dtype == "glasslike_framed_optional" then
				dustable[cid] = true
			end
		end
		if ndef.liquidtype and ndef.liquidtype ~= "none" then
			liquid[core.get_content_id(name)] = true
		end
	end
end

local function initialize_mapgen_data(chulens)
	init_mapgen = true

	if not init_biomes then
		initialize_biome_data()
	end

	local noiseparams = core.get_mapgen_setting_noiseparams

	local chulens2d = {x=chulens.x, y=chulens.z, z=1}
	local np_heat = noiseparams('mg_biome_np_heat')
	np_heat.offset = np_heat.offset + water_level*lapse_rate
	nobj_filler_depth = core.get_value_noise_map(np_filler_depth,                           chulens2d)
	nobj_heat         = core.get_value_noise_map(np_heat,                                   chulens2d)
	nobj_heat_blend   = core.get_value_noise_map(noiseparams('mg_biome_np_heat_blend'),     chulens2d)
	nobj_humid        = core.get_value_noise_map(noiseparams('mg_biome_np_humidity'),       chulens2d)
	nobj_humid_blend  = core.get_value_noise_map(noiseparams('mg_biome_np_humidity_blend'), chulens2d)

	c_ignore = core.get_content_id("ignore")
	c_air = core.get_content_id("air")
	c_stone = core.get_content_id("mapgen_stone")
	c_water = core.get_content_id("mapgen_water_source")
	c_rwater = core.get_content_id("mapgen_river_water_source")
end

local biomemap = {}
local biomemap_raw = {}
local heatmap = {}
local heatmap_adjusted = {}
local humidmap = {}
local heightmap = {}
local gennotify = {}

local function add_gennotify(feature, pos)
	if feature == 'custom' then
		return
	end

	if not init_biomes then
		initialize_biome_data()
	end

	if not gennotify_flags[feature] then
		return
	end
	gennotify[feature] = gennotify[feature] or {}
	table.insert(gennotify[feature], pos)
end

local function calculate_noises(minp)
	local minp2d = {x=minp.x, y=minp.z}
	nobj_filler_depth:get_2d_map_flat(minp2d, nvals_filler_depth)

	nobj_heat:get_2d_map_flat(minp2d, nvals_heat)
	nobj_heat_blend:get_2d_map_flat(minp2d, nvals_heat_blend)

	nobj_humid:get_2d_map_flat(minp2d, nvals_humid)
	nobj_humid_blend:get_2d_map_flat(minp2d, nvals_humid_blend)

	for i, heat in ipairs(nvals_heat) do -- use nvals_heat to iterate, could have been another one
		heatmap[i] = heat + nvals_heat_blend[i]
		humidmap[i] = nvals_humid[i] + nvals_humid_blend[i]
	end
end

local function get_biome_at_index(i, pos)
	local heat = heatmap[i] - math.max(pos.y, water_level)*lapse_rate
	if lapse_rate ~= 0 and not biomemap[i] then
		heatmap_adjusted[i] = heat
	end
	local humid = humidmap[i]
	return calc_biome_from_noise(heat, humid, pos)
end

local chunk_biomes = {}
local function generate_biomes(data, a, minp, maxp)
	if not init_mapgen then
		local chulens = {x=maxp.x-minp.x+1, y=maxp.y-minp.y+1, z=maxp.z-minp.z+1}
		initialize_mapgen_data(chulens)
	end

	calculate_noises(minp)

	chunk_biomes = {}
	local index = 1
	for z=minp.z, maxp.z do
	for x=minp.x, maxp.x do
		local biome = nil
		local water_biome = nil
		local biome_stone = c_stone

		local depth_top = 0
		local base_filler = 0
		local depth_water_top = 0
		local depth_riverbed = 0

		local biome_y_min = -31000
		local y_start = maxp.y
		local vi = a:index(x, maxp.y, z)
		local ystride = a.ystride

		local c_above = data[vi+ystride]
		if c_above == c_ignore then
			y_start = y_start - 1
			c_above = data[vi]
			vi = vi - ystride
		end
		local air_above = c_above == c_air
		local river_water_above = c_above == c_rwater
		local water_above = c_above == c_water or river_water_above

		biomemap[index] = nil
		biomemap_raw[index] = nil
		heightmap[index] = -31000

		local nplaced = (air_above or water_above) and 0 or 31000

		for y=y_start, minp.y-1, -1 do
			local c = data[vi]
			if heightmap[index] == -31000 and walkable[c] then
				heightmap[index] = y
			end

			local is_stone_surface = (c == c_stone) and
					(air_above or water_above or not biome or y < biome_y_min)
			local is_water_surface = (c == c_water or c == c_rwater) and
					(air_above or not biome or y < biome_y_min)

			if is_stone_surface or is_water_surface then
				biome = get_biome_at_index(index, {x=x, y=y, z=z})
				biome_stone = biome.node_stone

				if not biomemap[index] and is_stone_surface and biome then
					biomemap[index] = biome
					chunk_biomes[biome.name] = true
					biomemap_raw[index] = biome and biome.id or 0
				end

				if not water_biome and is_water_surface then
					water_biome = biome
				end

				depth_top = biome.depth_top
				base_filler = math.max(depth_top + biome.depth_filler + nvals_filler_depth[index], 0)
				depth_water_top = biome.depth_water_top
				depth_riverbed = biome.depth_riverbed
				biome_y_min = biome.min_pos.y
			end

			if c == c_stone or c == biome_stone then
				local c_below = data[vi-ystride]
				if c_below == c_air or c_below == c_rwater or c_below == c_water then
					nplaced = 31000
				end
				if river_water_above then
					if nplaced < depth_riverbed then
						data[vi] = biome.node_riverbed
						nplaced = nplaced + 1
					else
						nplaced = 31000
						river_water_above = false
					end
				elseif nplaced < depth_top then
					data[vi] = biome.node_top
					nplaced = nplaced + 1
				elseif nplaced < base_filler then
					data[vi] = biome.node_filler
					nplaced = nplaced + 1
				else
					data[vi] = biome_stone
					nplaced = 31000
				end

				air_above = false
				water_above = false
			elseif c == c_water then
				if y > water_level-depth_water_top then
					data[vi] = biome.node_water_top
				else
					data[vi] = biome.node_water
				end
				nplaced = 0
				air_above = false
				water_above = true
			elseif c == c_rwater then
				data[vi] = biome.node_river_water
				nplaced = 0
				air_above = false
				water_above = true
				river_water_above = true
			elseif c == c_air then
				nplaced = 0
				air_above = true
				water_above = false
			else
				nplaced = 31000
				air_above = false
				water_above = false
			end

			vi = vi - ystride
		end

		if not biomemap[index] and water_biome then
			biomemap[index] = water_biome
			chunk_biomes[water_biome.name] = true
			biomemap_raw[index] = water_biome and water_biome.id or 0
		end

		index = index + 1
	end
	end
end

local function skip_chunk(minp, maxp)
	if not init_mapgen then
		local chulens = {x=maxp.x-minp.x+1, y=maxp.y-minp.y+1, z=maxp.z-minp.z+1}
		initialize_mapgen_data(chulens)
	end

	calculate_noises(minp)

	local index = 1
	for z=minp.z, maxp.z do
		for x=minp.x, maxp.x do
			biomemap[index] = nil
			biomemap_raw[index] = nil
			heightmap[index] = -31000
			index = index + 1
		end
	end
end

local function can_place_deco(deco, data, vi, pattern)
	if not deco.place_on[data[vi]] then
		return false
	elseif deco.num_spawn_by <= 0 then
		return true
	end

	local spawn_by = deco.spawn_by
	local nneighs = deco.num_spawn_by
	local ncheck = deco.check_offset==0 and 8 or 16
	for i=1, ncheck do
		vi = vi + pattern[i]
		if spawn_by[data[vi]] then
			nneighs = nneighs - 1
			if nneighs < 1 then
				return true
			end
		end
	end

	return false
end

local mrand = math.random
local function place_deco(deco, data, a, vm, minp, maxp, blockseed)
	math.randomseed(blockseed + 53)
	local carea_size = maxp.x - minp.x + 1

	local sidelen = deco.sidelen
	if carea_size % sidelen > 0 then
		sidelen = carea_size
	end
	local divlen = carea_size / sidelen - 1
	local area = sidelen*sidelen
	local ystride, zstride = a.ystride, a.zstride
	local pattern = {ystride+1, zstride, -1, -1, -zstride, -zstride, 1, 1, ystride*deco.check_offset, zstride, zstride, -1, -1, -zstride, -zstride, 1} -- Successive increments to iterate over 16 neighbouring nodes

	local gennotify_list = {}
	if deco.gennotify then
		gennotify[deco.gennotify] = nil
	end

	local y_min = math.max(deco.y_min, minp.y)
	local y_max = math.min(deco.y_max, maxp.y)

	for z0=0, divlen do
	for x0=0, divlen do
		local x_min, z_min = minp.x+sidelen*x0, minp.z+sidelen*z0
		local x_max, z_max = x_min+sidelen-1, z_min+sidelen-1

		local cover = false
		local nval = deco.use_noise and deco.noise:get_2d({x=x_min+sidelen*0.5,y=z_min+sidelen*0.5}) or deco.fill_ratio
		local deco_count = 0

		if nval >= 10 then
			cover = true
			deco_count = area
		else
			local deco_count_f = area * nval
			if deco_count_f >= 1 then
				deco_count = deco_count_f
			elseif deco_count_f > 0 and mrand() <= deco_count_f then
				deco_count = 1
			end
		end

		local x = x_min - 1
		local z = z_min

		for i=1, deco_count do
			if not cover then
				x = mrand(x_min, x_max)
				z = mrand(z_min, z_max)
			else
				x = x + 1
				if x == x_max + 1 then
					z = z + 1
					x = x_min
				end
			end
			local mapindex = carea_size * (z - minp.z) + (x - minp.x) + 1

			if deco.flags.all_floors or deco.flags.all_ceilings then
				local biome_ok = true
				if deco.use_biomes then
					local biome_here = biomemap[mapindex]
					if biome_here and not deco.biomes[biome_here.name] then
						biome_ok = false
					end
				end

				if biome_ok then
					local is_walkable = false
					local vi = a:index(x, y_max, z)
					local walkable_above = walkable[data[vi]]
					for y = y_max-1, y_min, -1 do
						vi = vi - ystride
						is_walkable = walkable[data[vi]]
						if is_walkable and not walkable_above then -- We are on a floor
							if deco.flags.all_floors and can_place_deco(deco, data, a:index(x,y,z), pattern) then
								local pos = {x=x, y=y, z=z}
								local gen = deco:generate(vm, pos, false)
								if gen > 0 and deco.gennotify then
									gennotify_list[#gennotify_list+1] = pos
								end
							end
						elseif walkable_above and not is_walkable then -- We are under a ceiling
							if deco.flags.all_ceilings and can_place_deco(deco, data, a:index(x,y+1,z), pattern) then
								local pos = {x=x, y=y+1, z=z}
								local gen = deco:generate(vm, pos, true)
								if gen > 0 and deco.gennotify then
									gennotify_list[#gennotify_list+1] = pos
								end
							end
						end

						walkable_above = is_walkable
					end
				end
			else
				local y = nil
				if deco.flags.liquid_surface then
					local vi = a:index(x, y_max, z)
					for yi=y_max, y_min, -1 do
						local c = data[vi]
						if walkable[c] then
							break
						elseif liquid[c] then
							y = yi
							break
						end
						vi = vi - ystride
					end
				else
					local vi = a:index(x, y_max, z)
					for yi=y_max, y_min, -1 do
						if walkable[data[vi]] then
							y = yi
							break
						end
						vi = vi - ystride
					end
				end

				if y then
					local biome_ok = true
					if deco.use_biomes then
						local biome_here = biomemap[mapindex]
						if biome_here and not deco.biomes[biome_here.name] then
							biome_ok = false
						end
					end

					if biome_ok then
						local pos = {x=x, y=y, z=z}
						if can_place_deco(deco, data, a:index(x,y,z), pattern) then
							local gen = deco:generate(vm, pos, false)
							if gen > 0 and deco.gennotify then
								gennotify_list[#gennotify_list+1] = pos
							end
						end
					end
				end
			end
		end
	end
	end

	if #gennotify_list > 0 then
		gennotify[deco.gennotify] = gennotify_list
	end

	return 0
end

local function get_blockseed(p, seed)
	return seed + p.z * 38134234 + p.y * 42123 + p.x * 23
end

local function place_all_decos(data, a, vm, minp, maxp, seed)
	local emin = vm:get_emerged_area()
	local blockseed = get_blockseed(emin, seed)

	local nplaced = 0

	for i, deco in pairs(decos) do
		if deco.y_min <= maxp.y and deco.y_max >= minp.y then
			local biome_ok = not deco.use_biomes
			if deco.use_biomes then
				for name, _ in pairs(deco.biomes) do
					if chunk_biomes[name] then
						biome_ok = true
						break
					end
				end
			end
			if biome_ok then
				nplaced = nplaced + place_deco(deco, data, a, vm, minp, maxp, blockseed)
			end
		end
	end

	return nplaced
end

local function dust_top_nodes(data, a, vm, minp, maxp)
	if maxp.y < water_level then
		return
	end

	local full_maxp = a.MaxEdge

	local index = 1
	local ystride = a.ystride

	for z = minp.z, maxp.z do
	for x = minp.x, maxp.x do
		local biome = biomemap[index]

		if biome and biome.node_dust then
			local vi = a:index(x, full_maxp.y, z)
			local c_full_max = data[vi]
			local y_start

			if c_full_max == c_air then
				y_start = full_maxp.y - 1
			elseif c_full_max == c_ignore then
				vi = a:index(x, maxp.y, z)
				local c_max = data[vi]

				if c_max == c_air then
					y_start = maxp.y
				end
			end

			if y_start then -- workaround for the 'continue' statement
				vi = a:index(x, y_start, z)
				local y = y_start
				for y0=y_start, minp.y-1, -1 do
					if data[vi] ~= c_air then
						y = y0
						break
					end
					vi = vi - ystride
				end
				local c = data[vi]
				if dustable[c] and c ~= biome.node_dust then
					local pos = {x=x, y=y+1, z=z}
					vm:set_node_at(pos, {name=biome.node_dust_name})
				end
			end
		end
		index = index + 1
	end
	end
end

local vcopy = vector.copy

local orig_get_mapgen_object = core.get_mapgen_object
function core.get_mapgen_object(objname)
	local core_gennotify = orig_get_mapgen_object("gennotify") or {}
	core_gennotify.custom = core_gennotify.custom or {}

	if objname == "biomemap" then
		return core_gennotify.custom["biomegen:biomemap"] or table.copy(biomemap_raw)
	end

	if objname == "heatmap" then
		return core_gennotify.custom["biomegen:heatmap"] or table.copy((lapse_rate == 0) and heatmap or heatmap_adjusted)
	end

	if objname == "humiditymap" then
		return core_gennotify.custom["biomegen:humidmap"] or table.copy(humidmap)
	end

	if objname == "heightmap" then
		return core_gennotify.custom["biomegen:heightmap"] or table.copy(heightmap)
	end

	if objname == "gennotify" then
		local b_gennotify = core_gennotify.custom["biomegen:gennotify"] or {}
		for k, v in pairs(b_gennotify) do
			if core_gennotify[k] == nil then
				core_gennotify[k] = v
			end
			if k ~= "custom" then
				for i, pos in pairs(v) do
					v[i] = vcopy(pos)
				end
			end
		end
		for k, v in pairs(gennotify) do
			if core_gennotify[k] == nil then
				core_gennotify[k] = table.copy(v)
			end
			if k ~= "custom" then
				for i, pos in pairs(v) do
					v[i] = vcopy(pos)
				end
			end
		end

		return core_gennotify
	end

	return orig_get_mapgen_object(objname)
end

local orig_get_heat = core.get_heat
local function get_heat(pos)
	return orig_get_heat(pos) - math.max(pos.y-water_level, 0)*lapse_rate
end
core.get_heat = get_heat

local orig_get_biome_data = core.get_biome_data
function core.get_biome_data(pos)
	if not init_biomes then
		initialize_biome_data()
	end

	if lapse_rate == 0 then
		return orig_get_biome_data(pos)
	end

	local heat = get_heat(pos)
	local humidity = core.get_humidity(pos)
	local biome = calc_biome_from_noise(heat, humidity, pos)
	if biome then
		return {
			heat = heat,
			humidity = humidity,
			biome = biome.id,
		}
	end
end

-- Reset gennotify after mapgen (ensure it is called last)
core.register_on_mods_loaded(function()
	table.insert(core.registered_on_generateds,
		function()
			if thread == "mapgen" then
				core.save_gen_notify("biomegen:biomemap", biomemap_raw)
				core.save_gen_notify("biomegen:heatmap", (lapse_rate == 0) and heatmap or heatmap_adjusted)
				core.save_gen_notify("biomegen:humidmap", humidmap)
				core.save_gen_notify("biomegen:heightmap", heightmap)
				core.save_gen_notify("biomegen:gennotify", gennotify)
			end
			gennotify = {}
		end
	)
end)

biomegen = {
	set_lapse_rate = set_lapse_rate,
	set_elevation_chill = set_lapse_rate, --compatibility
	get_lapse_rate = get_lapse_rate,
	calculate_noises = calculate_noises,
	get_biome_at_index = get_biome_at_index,
	calc_biome_from_noise = calc_biome_from_noise,
	generate_biomes = generate_biomes,
	place_all_decos = place_all_decos,
	dust_top_nodes = dust_top_nodes,
	skip_chunk = skip_chunk,
	gennotify = add_gennotify,
}

function biomegen.generate_all(data, a, vm, minp, maxp, seed)
	generate_biomes(data, a, minp, maxp)
	vm:set_data(data)
	place_all_decos(data, a, vm, minp, maxp, seed)
	core.generate_ores(vm, minp, maxp)
	vm:get_data(data)
	dust_top_nodes(data, a, vm, minp, maxp)
end

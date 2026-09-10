-- Set v7 mapgen so biomes/decorations are registered properly by default mod.
minetest.set_mapgen_setting("mg_name", "v7", true)
minetest.set_mapgen_setting("mg_flags", "nocaves, nodungeons, nodecorations", true)
minetest.set_mapgen_setting("mg_flags", "nolight", true)
minetest.set_mapgen_setting("water_level", "0", true)

-- Island spacing increased and radius increased by ~20%
local island_centers = {
    {id=1, x=100, z=100, r=100, name="Grassland/Coniferous", heat=35, humid=65}, -- Mixed
    {id=2, x=-90, z=90, r=70, name="Savanna shore", heat=85, humid=20}, -- Savanna
    {id=3, x=-80, z=-80, r=50, name="Deciduous forest", heat=50, humid=80}, -- Deciduous
    {id=4, x=80, z=-80, r=30, name="Rainforest", heat=85, humid=80} -- Rainforest
}

-- Get the content IDs for the nodes used.
local c_stone, c_water, c_air
minetest.register_on_mods_loaded(function()
    c_stone = minetest.get_content_id("mapgen_stone")
    c_water = minetest.get_content_id("mapgen_water_source")
    c_air = minetest.get_content_id("air")

    if biomegen then
        local orig_calc = biomegen.calc_biome_from_noise
        biomegen.calc_biome_from_noise = function(heat, humid, pos)
            local best_island = nil
            local best_dist_ratio = 1.0

            for _, ic in ipairs(island_centers) do
                local dx = pos.x - ic.x
                local dz = pos.z - ic.z
                local dist = math.sqrt(dx*dx + dz*dz)
                if dist <= ic.r * 1.5 then
                    local ratio = dist / ic.r
                    if ratio < best_dist_ratio then
                        best_dist_ratio = ratio
                        best_island = ic
                    end
                end
            end

            if best_island then
                return orig_calc(best_island.heat, best_island.humid, pos)
            end

            return orig_calc(heat, humid, pos)
        end
    end
end)

local np_terrain = {
    offset = 0,
    scale = 0.4,
    spread = {x = 200, y = 100, z = 200},
    seed = 5900033,
    octaves = 5,
    persist = 0.63,
    lacunarity = 2.0,
}
local nobj_terrain = nil
local nvals_terrain = {}

-- Localise data buffer table outside the loop
local data = {}

minetest.register_on_generated(function(minp, maxp, seed)
    local voxelmanip, emin, emax = minetest.get_mapgen_object("voxelmanip")
    local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
    voxelmanip:get_data(data)

    local sidelen_x = emax.x - emin.x + 1
    local sidelen_y = emax.y - emin.y + 1
    local sidelen_z = emax.z - emin.z + 1
    local permapdims3d = {x = sidelen_x, y = sidelen_y, z = sidelen_z}
    nobj_terrain = nobj_terrain or minetest.get_perlin_map(np_terrain, permapdims3d)
    nobj_terrain:get_3d_map_flat(emin, nvals_terrain)

    local ni = 1
    for z = emin.z, emax.z do
        for y = emin.y, emax.y do
            local voxel_index = area:index(emin.x, y, z)
            for x = emin.x, emax.x do
                local island_id = 0
                local best_dist_ratio = 1.0

                for _, ic in ipairs(island_centers) do
                    local dx = x - ic.x
                    local dz = z - ic.z
                    local dist = math.sqrt(dx*dx + dz*dz)
                    if dist <= ic.r * 1.5 then
                        local ratio = dist / ic.r
                        if ratio < best_dist_ratio then
                            best_dist_ratio = ratio
                            island_id = ic.id
                        end
                    end
                end

                if island_id > 0 then
                    local density_noise = nvals_terrain[ni]

                    -- Gradient: highest point around y=15, goes to 0 at water (y=1)
                    local density_gradient = (12 - y) / 12.0

                    -- Penalize density heavily as we get further from center to create a conical/island shape
                    local shape_penalty = (best_dist_ratio * best_dist_ratio) * 2.5

                    local density = density_noise + density_gradient - shape_penalty

                    if density > 0 then
                        data[voxel_index] = c_stone
                    elseif y <= 0 then
                        data[voxel_index] = c_water
                    else
                        data[voxel_index] = c_air
                    end
                else
                    -- Solid stone floor at y=-30
                    if y <= -30 then
                        data[voxel_index] = c_stone
                    elseif y <= 0 then
                        data[voxel_index] = c_water
                    else
                        data[voxel_index] = c_air
                    end
                end

                ni = ni + 1
                voxel_index = voxel_index + 1
            end
        end
    end

    -- Call biomegen to generate biomes, decorations, etc.
    if biomegen then
        biomegen.generate_all(data, area, voxelmanip, minp, maxp, seed)
    else
        voxelmanip:set_data(data)
    end

    voxelmanip:calc_lighting()
    voxelmanip:update_liquids()
    voxelmanip:write_to_map()
    voxelmanip:update_map()
end)

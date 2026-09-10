-- Set v7 mapgen so biomes/decorations are registered properly by default mod.
minetest.set_mapgen_setting("mg_name", "v7", true)
minetest.set_mapgen_setting("mg_flags", "nolight", false)

-- Get the content IDs for the nodes used.
local c_stone, c_water, c_air
minetest.register_on_mods_loaded(function()
    c_stone = minetest.get_content_id("mapgen_stone")
    c_water = minetest.get_content_id("mapgen_water_source")
    c_air = minetest.get_content_id("air")

    if biomegen then
        local orig_calc = biomegen.calc_biome_from_noise
        biomegen.calc_biome_from_noise = function(heat, humid, pos)
            local wx = pos.x
            local wz = pos.z

            -- Island 1 (x=100, z=100): Grassland (left), Coniferous (right)
            if wx >= 0 and wx <= 200 and wz >= 0 and wz <= 200 then
                if wx < 100 then
                    return orig_calc(50, 50, pos) -- Grassland (med heat, med humid)
                else
                    return orig_calc(25, 80, pos) -- Coniferous (low heat, high humid)
                end
            -- Island 2 (x=-90, z=90): Savanna shore
            elseif wx >= -160 and wx <= -20 and wz >= 20 and wz <= 160 then
                return orig_calc(85, 20, pos) -- Savanna (high heat, low humid)
            -- Island 3 (x=-80, z=-80): Deciduous forest
            elseif wx >= -130 and wx <= -30 and wz >= -130 and wz <= -30 then
                return orig_calc(50, 80, pos) -- Deciduous (med heat, high humid)
            -- Island 4 (x=80, z=-80): Savanna
            elseif wx >= 50 and wx <= 110 and wz >= -110 and wz <= -50 then
                return orig_calc(85, 20, pos) -- Savanna (high heat, low humid)
            end

            return orig_calc(heat, humid, pos)
        end
    end
end)

local np_terrain = {
    offset = 0,
    scale = 1,
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

    -- Island spacing increased and radius increased by ~20%
    local island_centers = {
        {id=1, x=100, z=100, r=100, name="Grassland/Coniferous"},
        {id=2, x=-90, z=90, r=70, name="Savanna shore"},
        {id=3, x=-80, z=-80, r=50, name="Deciduous forest"},
        {id=4, x=80, z=-80, r=30, name="Savanna"}
    }

    local sidelen = maxp.x - minp.x + 1
    local permapdims3d = {x = sidelen, y = sidelen, z = sidelen}
    nobj_terrain = nobj_terrain or minetest.get_perlin_map(np_terrain, permapdims3d)
    nobj_terrain:get_3d_map_flat(minp, nvals_terrain)

    local ni = 1
    for z = minp.z, maxp.z do
        for y = minp.y, maxp.y do
            local voxel_index = area:index(minp.x, y, z)
            for x = minp.x, maxp.x do
                local island_id = 0
                local best_dist_ratio = 1.0

                for _, ic in ipairs(island_centers) do
                    local dx = x - ic.x
                    local dz = z - ic.z
                    local dist = math.sqrt(dx*dx + dz*dz)
                    if dist <= ic.r then
                        local ratio = dist / ic.r
                        if ratio < best_dist_ratio then
                            best_dist_ratio = ratio
                            island_id = ic.id
                        end
                    end
                end

                if island_id > 0 then
                    local density_noise = nvals_terrain[ni]

                    -- Gradient: highest point around y=25, goes to 0 at water (y=1)
                    local density_gradient = (5 - y) / 30.0

                    -- Penalize density heavily as we get further from center to create a conical/island shape
                    local shape_penalty = (best_dist_ratio * best_dist_ratio) * 1.5

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
    voxelmanip:write_to_map()
    voxelmanip:update_liquids()

    -- Place center structures
    for _, ic in ipairs(island_centers) do
        if ic.x >= minp.x and ic.x <= maxp.x and ic.z >= minp.z and ic.z <= maxp.z then
            -- Find surface Y
            local surface_y = -31000
            for y = maxp.y, minp.y, -1 do
                local node = minetest.get_node({x=ic.x, y=y, z=ic.z})
                if node.name ~= "air" and node.name ~= "ignore" then
                    surface_y = y
                    break
                end
            end

            if surface_y >= minp.y then
                local pos = {x=ic.x, y=surface_y, z=ic.z}
                minetest.set_node(pos, {name="default:meselamp"})

                local sign_pos = {x=ic.x, y=surface_y+1, z=ic.z}
                minetest.set_node(sign_pos, {name="default:sign_wall_steel"})
                local meta = minetest.get_meta(sign_pos)
                meta:set_string("text", ic.name)
            end
        end
    end
end)

-- Set singlenode mapgen (air nodes only).
minetest.set_mapgen_setting("mg_name", "singlenode", true)
minetest.set_mapgen_setting("mg_flags", "nolight", true)

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

            if wx >= 20 and wx <= 120 and wz >= 20 and wz <= 120 then
                -- Island 1: Grassland dunes (left), Coniferous forest dunes (right)
                if wx < 70 then
                    return minetest.registered_biomes["grassland_dunes"] or orig_calc(heat, humid, pos)
                else
                    return minetest.registered_biomes["coniferous_forest_dunes"] or orig_calc(heat, humid, pos)
                end
            elseif wx >= -90 and wx <= -20 and wz >= 20 and wz <= 90 then
                -- Island 2: Savanna shore
                return minetest.registered_biomes["savanna_shore"] or orig_calc(heat, humid, pos)
            elseif wx >= -70 and wx <= -20 and wz >= -70 and wz <= -20 then
                -- Island 3: Deciduous forest
                return minetest.registered_biomes["deciduous_forest"] or orig_calc(heat, humid, pos)
            elseif wx >= 20 and wx <= 50 and wz >= -50 and wz <= -20 then
                -- Island 4: Savanna
                return minetest.registered_biomes["savanna"] or orig_calc(heat, humid, pos)
            end

            return orig_calc(heat, humid, pos)
        end
    end
end)

-- Localise data buffer table outside the loop
local data = {}

minetest.register_on_generated(function(minp, maxp, seed)
    local voxelmanip, emin, emax = minetest.get_mapgen_object("voxelmanip")
    local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
    voxelmanip:get_data(data)

    local island_centers = {
        {id=1, x=70, z=70, r=50, name="Grassland/Coniferous"},
        {id=2, x=-55, z=55, r=35, name="Savanna shore"},
        {id=3, x=-45, z=-45, r=25, name="Deciduous forest"},
        {id=4, x=35, z=-35, r=15, name="Savanna"}
    }

    local island_heightmap = {}

    for z = minp.z, maxp.z do
        for x = minp.x, maxp.x do
            local max_h = -1
            local island_id = 0

            for _, ic in ipairs(island_centers) do
                local dx = x - ic.x
                local dz = z - ic.z
                local dist = math.sqrt(dx*dx + dz*dz)

                -- Create square islands based on radius
                if math.abs(dx) <= ic.r and math.abs(dz) <= ic.r then
                    -- Smooth falloff for square
                    local nx = math.abs(dx) / ic.r
                    local nz = math.abs(dz) / ic.r
                    local max_n = math.max(nx, nz)
                    local shape = 1.0 - (max_n * max_n)

                    if shape > 0 then
                        island_id = ic.id
                        local height_mult = 17
                        if island_id == 2 then height_mult = 3 end -- lower for shore

                        max_h = shape * height_mult
                        -- Add slight noise
                        local noise = math.sin(x/5.0) + math.cos(z/5.0)
                        max_h = max_h + noise

                        if max_h < 1 then max_h = 1 end
                        if max_h > 17 then max_h = 17 end
                    end
                end
            end

            island_heightmap[z * 10000 + x] = {id = island_id, h = max_h}
        end
    end

    -- Apply to terrain
    for z = minp.z, maxp.z do
        for y = minp.y, maxp.y do
            local voxel_index = area:index(minp.x, y, z)
            for x = minp.x, maxp.x do
                local info = island_heightmap[z * 10000 + x]
                local island_id = info.id
                local max_h = info.h

                if island_id > 0 then
                    if y <= math.floor(max_h) then
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
                local pos = {x=ic.x, y=surface_y+1, z=ic.z}
                minetest.set_node(pos, {name="default:meselamp"})

                local sign_pos = {x=ic.x+1, y=surface_y+1, z=ic.z}
                minetest.set_node(sign_pos, {name="default:sign_wall_steel", param2=2})
                local meta = minetest.get_meta(sign_pos)
                meta:set_string("text", ic.name)
            end
        end
    end
end)

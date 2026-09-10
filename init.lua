-- Set singlenode mapgen (air nodes only).
minetest.set_mapgen_setting("mg_name", "singlenode", true)
minetest.set_mapgen_setting("mg_flags", "nolight", true)

-- Get the content IDs for the nodes used.
local c_stone, c_water, c_air
minetest.register_on_mods_loaded(function()
    c_stone = minetest.get_content_id("mapgen_stone")
    c_water = minetest.get_content_id("mapgen_water_source")
    c_air = minetest.get_content_id("air")
end)

local function get_2d_noise(n, x, z)
    return math.sin(x / 10.0 + n) + math.cos(z / 10.0 - n)
end

-- Localise data buffer table outside the loop, to be re-used for all
-- mapchunks, therefore minimising memory use.
local data = {}

minetest.register_on_generated(function(minp, maxp, seed)
    -- Only generate islands if the chunk is near 0,0
    local is_island_area = not (minp.x > 160 or maxp.x < -160 or minp.z > 160 or maxp.z < -160)

    local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
    local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
    vm:get_data(data)

    local island_heightmap = {}

    if is_island_area then
        -- pre-calculate heightmap and island shapes to apply
        for z = minp.z, maxp.z do
            for x = minp.x, maxp.x do
                local r = math.sqrt(x*x + z*z)
                local inner_r = 20 + 5 * get_2d_noise(1, x, z)
                local outer_r = 75 + 10 * get_2d_noise(2, x, z)

                local angle = math.atan2(z, x)
                local abs_a = math.abs(angle)
                local d_a1 = math.abs(abs_a - math.pi/4)
                local d_a2 = math.abs(abs_a - 3*math.pi/4)
                local dist_a = math.min(d_a1, d_a2)
                local channel_width = 0.2 + 0.1 * get_2d_noise(3, x, z)

                local island_id = 0
                if r >= inner_r and r <= outer_r and dist_a >= channel_width then
                    if angle > -math.pi/4 and angle <= math.pi/4 then island_id = 1
                    elseif angle > math.pi/4 and angle <= 3*math.pi/4 then island_id = 2
                    elseif angle > 3*math.pi/4 or angle <= -3*math.pi/4 then island_id = 3
                    else island_id = 4 end
                end

                local max_h = 0
                if island_id > 0 then
                    local n_dist = (r - inner_r) / (outer_r - inner_r)
                    local shape = math.sin(n_dist * math.pi)
                    max_h = 80 * shape -- Make it more like a mountain, less flat

                    local noise2d = get_2d_noise(4, x, z)
                    max_h = max_h + noise2d * 5
                    if max_h < 1 then max_h = 1 end
                    if max_h > 80 then max_h = 80 end
                end

                -- store negative value if no island, just to be safe
                if island_id == 0 then
                    island_heightmap[z * 1000 + x] = {id = 0, h = -1}
                else
                    island_heightmap[z * 1000 + x] = {id = island_id, h = max_h}
                end
            end
        end
    end

    -- Apply to terrain
    for z = minp.z, maxp.z do
        for y = minp.y, maxp.y do
            local vi = area:index(minp.x, y, z)
            for x = minp.x, maxp.x do
                local island_id = 0
                local max_h = -1

                if is_island_area then
                    local info = island_heightmap[z * 1000 + x]
                    island_id = info.id
                    max_h = info.h
                end

                if island_id > 0 then
                    if y <= math.floor(max_h) then
                        data[vi] = c_stone
                    elseif y <= 0 then
                        data[vi] = c_water
                    else
                        data[vi] = c_air
                    end
                else
                    -- Outside islands or channels between islands
                    -- Solid stone floor at y=-30
                    if y <= -30 then
                        data[vi] = c_stone
                    elseif y <= 0 then
                        data[vi] = c_water
                    else
                        data[vi] = c_air
                    end
                end

                vi = vi + 1
            end
        end
    end

    -- Call biomegen to generate biomes, decorations, etc.
    -- It will automatically call vm:set_data(data)
    if biomegen then
        biomegen.generate_all(data, area, vm, minp, maxp, seed)
    else
        vm:set_data(data)
    end

    vm:calc_lighting()
    vm:write_to_map()
    vm:update_liquids()
end)

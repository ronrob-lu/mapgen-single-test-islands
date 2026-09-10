-- island_gen/init.lua

-- Set mapgen to flat
minetest.set_mapgen_setting("mg_name", "flat", true)
-- Ocean floor at -30
minetest.set_mapgen_setting("mgflat_ground_level", "-30", true)
-- Ensure water level is 0
minetest.set_mapgen_setting("water_level", "0", true)

local c_stone, c_air, c_sand, c_dirt, c_grass, c_tree, c_leaves
local random_biome_1_nodes = nil
local random_biome_2_nodes = nil
local is_generated = false
local generation_started = false

-- Storage path to keep track if we generated the islands
local world_path = minetest.get_worldpath()
local generated_file = world_path .. "/island_gen_done.txt"

local function load_generated_state()
    local file = io.open(generated_file, "r")
    if file then
        is_generated = true
        file:close()
    end
end

local function save_generated_state()
    local file = io.open(generated_file, "w")
    if file then
        file:write("done")
        file:close()
    end
    is_generated = true
end

load_generated_state()

minetest.register_on_mods_loaded(function()
    c_stone = minetest.get_content_id("default:stone")
    c_air = minetest.get_content_id("air")
    c_sand = minetest.get_content_id("default:sand")
    c_dirt = minetest.get_content_id("default:dirt")
    c_grass = minetest.get_content_id("default:dirt_with_grass")
    c_tree = minetest.get_content_id("default:tree")
    c_leaves = minetest.get_content_id("default:leaves")

    local available_biomes = {}
    for name, def in pairs(minetest.registered_biomes) do
        table.insert(available_biomes, def)
    end

    if #available_biomes > 0 then
        -- pseudo-random selection based on table size to avoid overriding math.randomseed
        local b1 = available_biomes[1]
        local b2 = available_biomes[#available_biomes]

        local node_top_1 = minetest.get_content_id(b1.node_top or "default:dirt_with_grass")
        local node_filler_1 = minetest.get_content_id(b1.node_filler or "default:dirt")
        local node_top_2 = minetest.get_content_id(b2.node_top or "default:sand")
        local node_filler_2 = minetest.get_content_id(b2.node_filler or "default:sandstone")

        random_biome_1_nodes = { top = node_top_1, filler = node_filler_1 }
        random_biome_2_nodes = { top = node_top_2, filler = node_filler_2 }
    else
        random_biome_1_nodes = { top = c_grass, filler = c_dirt }
        random_biome_2_nodes = { top = minetest.get_content_id("default:snowblock"), filler = minetest.get_content_id("default:dirt_with_snow") }
    end
end)

local function get_2d_noise(n, x, z)
    return math.sin(x / 10.0 + n) + math.cos(z / 10.0 - n)
end

local function generate_islands()
    if is_generated or generation_started then return end
    generation_started = true

    -- Area big enough to fit the 150 blocks max width centered around 0,0
    local minp = {x = -160, y = -30, z = -160}
    local maxp = {x = 160, y = 30, z = 160}

    minetest.emerge_area(minp, maxp, function(blockpos, action, calls_remaining, callbacks)
        if calls_remaining == 0 then
            -- all blocks are emerged, we can now manipulate them
            local vm = minetest.get_voxel_manip(minp, maxp)
            local emin, emax = vm:get_emerged_area()
            local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
            local data = vm:get_data()

            local island_heightmap = {}

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
                        max_h = 17 * shape

                        local noise2d = get_2d_noise(4, x, z)
                        max_h = max_h + noise2d * 2
                        if max_h < 1 then max_h = 1 end
                        if max_h > 17 then max_h = 17 end
                    end

                    island_heightmap[z * 1000 + x] = {id = island_id, h = max_h}
                end
            end

            -- Apply to terrain
            for z = minp.z, maxp.z do
                for y = minp.y, maxp.y do
                    for x = minp.x, maxp.x do
                        local idx = area:index(x, y, z)
                        local info = island_heightmap[z * 1000 + x]
                        local island_id = info.id
                        local max_h = info.h

                        if island_id > 0 then
                            local is_surface = (y == math.floor(max_h))
                            local is_near_surface = (y >= math.floor(max_h) - 3 and y < math.floor(max_h))

                            if y <= math.floor(max_h) then
                                if island_id == 1 then
                                    if is_surface or is_near_surface then
                                        data[idx] = c_sand
                                    else
                                        data[idx] = c_stone
                                    end
                                elseif island_id == 2 then
                                    if is_surface then
                                        if y <= 2 then
                                            data[idx] = c_sand
                                        else
                                            data[idx] = c_grass

                                            -- Trees
                                            if y > 2 and math.random() < 0.02 and x > minp.x+2 and x < maxp.x-2 and z > minp.z+2 and z < maxp.z-2 then
                                                local idx_above = area:index(x, y+1, z)
                                                data[idx_above] = c_tree
                                                local idx_above2 = area:index(x, y+2, z)
                                                data[idx_above2] = c_tree
                                                local idx_above3 = area:index(x, y+3, z)
                                                data[idx_above3] = c_tree
                                                for lx = x-1, x+1 do
                                                    for lz = z-1, z+1 do
                                                        for ly = y+3, y+4 do
                                                            local lidx = area:index(lx, ly, lz)
                                                            if data[lidx] == c_air then
                                                                data[lidx] = c_leaves
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    elseif is_near_surface then
                                        if y <= 2 then
                                            data[idx] = c_sand
                                        else
                                            data[idx] = c_dirt
                                        end
                                    else
                                        data[idx] = c_stone
                                    end
                                elseif island_id == 3 then
                                    if is_surface then
                                        data[idx] = random_biome_1_nodes.top
                                    elseif is_near_surface then
                                        data[idx] = random_biome_1_nodes.filler
                                    else
                                        data[idx] = c_stone
                                    end
                                elseif island_id == 4 then
                                    if is_surface then
                                        data[idx] = random_biome_2_nodes.top
                                    elseif is_near_surface then
                                        data[idx] = random_biome_2_nodes.filler
                                    else
                                        data[idx] = c_stone
                                    end
                                end
                            else
                                data[idx] = c_air
                            end
                        else
                            -- Override default flat generation here just in case, but default mapgen already creates ocean
                            if y > 0 then
                                data[idx] = c_air
                            end
                        end
                    end
                end
            end

            vm:set_data(data)
            vm:calc_lighting()
            vm:write_to_map()
            vm:update_liquids()

            save_generated_state()
        end
    end)
end

-- Wait until a player joins to start generation
minetest.register_on_joinplayer(function(player)
    generate_islands()
end)

minetest.register_on_generated(function(minp, maxp, seed)
    if maxp.y < -22 or minp.y > 0 then return end  -- Solo dove serve

    local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
    local data = vm:get_data()
    local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

    local c_air = minetest.get_content_id("air")
    local c_water = minetest.get_content_id("default:water_source")
    local c_sand = minetest.get_content_id("default:sand")
    local c_sandstone = minetest.get_content_id("default:sandstone")

    for z = minp.z, maxp.z do
        for y = minp.y, maxp.y do
            for x = minp.x, maxp.x do
                local vi = area:index(x, y, z)

                if y >= 1 then
                    data[vi] = c_air
                elseif y >= -19 then
                    data[vi] = c_water
                elseif y >= -21 then
                    data[vi] = c_sand
                elseif y == -22 then
                    data[vi] = c_sandstone
                else
                    data[vi] = c_air
                end
            end
        end
    end

    vm:set_data(data)
    vm:write_to_map()
end)

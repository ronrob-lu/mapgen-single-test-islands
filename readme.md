# 🏝️ Island Gen 🏝️

A Minetest/Luanti mod that generates a specific island map configuration when the world starts! 🌊

> ⚠️ **GitHub Note**: This mod is still in testing, it's not intended for a a real gameplay, although you can do this! 🚧

## ✨ Features

- 🗺️ Generates exactly 4 natural-looking islands centered around `0,0,0`
- 📏 Water level is exactly at `0`
- 🏝️ Maximum island width is approximately `150` blocks
- ⛰️ Islands are less flat, generating more like mountains!
- 🏖️ Coastlines are approximately between `20` and `75` blocks from the center
- 🌳 **Biome Distribution** handled seamlessly by `biomegen` to avoid random weird structures!
- 🤿 No underwater structures or underground caves. Islands sit on a sea floor extending to depth `y=-30`.
- 🌊 Everything outside the islands is water extending to map boundaries, with a stone floor at `y=-30`.

## 📦 Installation

Drop the repository directory into your `mods` folder in Minetest/Luanti and enable it for your world! 🎮

## 🎮 Usage Notes

This mod natively handles terrain and biome generation cleanly!
The map generation logic will only generate the 4 islands around the center (`0,0,0`). All other map areas will be sea level water with air above.

## 📚 Source Mods Referenced

This mod references patterns from `lvm_example`, `aqua_world`, and heavily utilizes `biomegen` for chunk-based voxel manipulation. See `LICENSE.md` for credits!

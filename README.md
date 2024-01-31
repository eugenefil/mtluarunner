This mod is supposed to work in tandem with [mtluakernel](https://github.com/eugenefil/mtluakernel) - Jupyter kernel for Lua in Minetest.

How to run:

- Start a Jupyter notebook using aforementioned Lua kernel.

- Add mtluarunner mod to `secure.http_mods` in `minetest.conf`.

- Start Minetest world with this mod enabled.

- Lua code from notebook cells is sent to this mod for execution. See Minetest Lua Modding API [Reference](https://github.com/minetest/minetest/blob/master/doc/lua_api.md) to do something useful.

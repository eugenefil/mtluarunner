local http = minetest.request_http_api()
if not http then
	minetest.log("error", "mtluarunner mod can't access http api, please add it to secure.http_mods")
	return
end

local E = {}
setmetatable(E, {__index = _G})

mtluarunner = {}

local stdout = ""

local fetch_code

local load_mode = "local"

-- Loads mod depending on the load mode chosen. If mode is "local",
-- which is default, main.lua from mod's directory is loaded into
-- separate environment. If mode is "remote", mtluarunner's
-- environment is used for the mod and its code is not loaded from
-- files, but expected to be run through remote interaction.
--
-- To inject some variables into the mod's environment, pass them in
-- vars.
function mtluarunner.loadmod(vars)
	local env
	if load_mode == "remote" then
		env = E
	elseif load_mode == "local" then
		env = {}
		setmetatable(env, {__index = _G})
	else
		assert(nil, "unknown load mode: " .. load_mode)
	end

	if vars then
		for k, v in pairs(vars) do env[k] = v end
	end

	if load_mode == "local" then
		local mod = minetest.get_current_modname()
		local path = minetest.get_modpath(mod)
		local chunk = assert(loadfile(path .. "/main.lua"))
		setfenv(chunk, env)()
	end
end

function E.load_mode(mode)
	if mode == "remote" then load_mode = mode end
end

local function tostr(o)
	if type(o) == "string" then return o
	else return dump(o) end
end

function E.print(...)
	local out = ""
	local args = {...}
	for i = 1, select("#", ...) do
		if i > 1 then out = out .. "\t" end
		out = out .. tostr(args[i])
	end
	stdout = stdout .. out .. "\n"
end

local function parse_code(s)
	local obj = minetest.parse_json(s)
	if not obj then
		-- return no error msg, since json parser does its own
		-- error output
		return nil, nil
	end

	if type(obj) ~= "table" then
		return nil, "json is not an object"
	end

	if obj.code == nil then
		return nil, "missing 'code' key"
	end

	if type(obj.code) ~= "string" then
		return nil, "'code' value is not a string"
	end

	return obj.code, nil
end

local function on_replysent(res)
	assert(res.succeeded, dump(res))
	fetch_code()
end

local function errhandler(err)
	return debug.traceback(err, 1)
end

local function get_result(status, ...)
	local res = {status = status}
	local out = stdout
	stdout = "" -- flush stdout
	local n, results = select("#", ...), {...}
	if status and n > 0 then
		local value = ""
		for i = 1, n do
			if i > 1 then value = value .. "\t" end
			value = value .. dump(results[i])
		end
		res.value = value
	elseif not status then
		assert(n == 1) -- error handler must return message
		out = out .. results[1]
	end
	if out ~= "" then res.stdout = out end
	return res
end

local function preprocess(code)
	if code:sub(1,1) == "=" then
		code = "return " .. code:sub(2)
	end
	return code
end

local function run(code)
	local result
	code = preprocess(code)
	local chunk, err = loadstring(code)
	if not chunk then
		result = {status = false, stdout = err}
	else
		setfenv(chunk, E)
		result = get_result(xpcall(chunk, errhandler))
	end

	return {
		url = "http://127.0.0.1:2468/result",
		post_data = minetest.write_json(result),
	}
end

local function handle_codefetch(res)
	if not res.succeeded then return end

	local code, err = parse_code(res.data)
	if not code or #code == 0 then
		if err then
			minetest.log("error", "Failed to validate json data")
			minetest.log("error", " " .. err)
		end
		return
	end

	return run(code)
end

local function on_codefetch(res)
	local reply = handle_codefetch(res)
	if not reply then return fetch_code() end
	http.fetch(reply, on_replysent)
end

function fetch_code()
	http.fetch({url = "http://127.0.0.1:2468/code"}, on_codefetch)
end

local function send_sync(req)
	local handle = http.fetch_async(req)
	while true do
		local res = http.fetch_async_get(handle)
		if res.completed then return res end
	end
end

local function fetch_init_code()
	local req = {url = "http://127.0.0.1:2468/code"}
	local reply = handle_codefetch(send_sync(req))
	if reply then send_sync(reply) end
end

fetch_init_code()
fetch_code()

-- TODO resend result on http error
-- TODO pretty traceback like in python w/ code lines etc

local http = minetest.request_http_api()
if not http then
	minetest.log("error", "mtluarunner mod can't access http api, please add it to secure.http_mods")
	return
end

local E = {}
setmetatable(E, {__index = _G})

local stdout = ""

local fetch_code

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

local function on_resultsent(res)
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

	local req = {
		url = "http://127.0.0.1:2468/result",
		post_data = minetest.write_json(result),
	}
	http.fetch(req, on_resultsent)
end

local function on_codefetch(res)
	if not res.succeeded then return fetch_code() end

	local code, err = parse_code(res.data)
	if not code or #code == 0 then
		if err then
			minetest.log("error", "Failed to validate json data")
			minetest.log("error", " " .. err)
		end
		return fetch_code()
	end

	return run(code)
end

function fetch_code()
	http.fetch({url = "http://127.0.0.1:2468/code"}, on_codefetch)
end

fetch_code()

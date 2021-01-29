-- TODO resend result on http error

local http = minetest.request_http_api()
if not http then
	minetest.log("error", "mtluarunner mod can't access http, please add it to secure.http_mods")
	return
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

local fetch_code

local function on_resultsent(res)
	assert(res.succeeded, dump(res))
	fetch_code()
end

local function errhandler(err)
	return debug.traceback(err, 1)
end

local function get_result(status, res1_or_err, ...)
	local value = res1_or_err
	if status then
		value = dump(value)
		local results = {...}
		for i = 1, select("#", ...) do
			value = value .. "\t" .. dump(results[i])
		end
	end
	return {status = status, value = value}
end

local function run(code)
	local result
	local chunk, err = loadstring(code)
	if not chunk then
		result = {status = false, value = err}
	else
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

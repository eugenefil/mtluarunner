local http = minetest.request_http_api()
if not http then
	minetest.log("error", "mtluarunner mod can't access http, please add it to secure.http_mods")
	return
end

local state = "start_request"
local requests = {}

local function parse_requests(s)
	local reqs = minetest.parse_json(s)
	if not reqs then
		-- return no error msg, since json parser does its own
		-- error output
		return nil, nil
	end

	if type(reqs) ~= "table" then
		return nil, "json is not a list"
	end

	local out_reqs = {}
	for _, req in ipairs(reqs) do
		if type(req) ~= "table" then
			return nil, "request is not an object"
		end

		local id = req["id"]
		if not id then
			return nil, "missing 'id' key"
		end
		if type(id) ~= "string" then
			return nil, "'id' key is not a string"
		end

		local code = req["code"]
		if not code then
			return nil, "missing 'code' key"
		end
		if type(code) ~= "string" then
			return nil, "'code' key is not a string"
		end

		table.insert(out_reqs, {id = id, code = code})
	end
	return out_reqs, nil
end

local function handle_http_result(res)
	state = "start_request" -- go back to http fetch on error
	if not res.succeeded then return end

	local reqs, err = parse_requests(res.data)
	if not reqs or #reqs == 0 then
		if err then
			minetest.log("error", "Failed to validate json data")
			minetest.log("error", " " .. err)
			end
		return
	end

	minetest.debug(dump(reqs))
	state = "execute"
	assert(#requests == 0, "undone requests while adding new ones")
	requests = reqs
end

local time = 0
minetest.register_globalstep(function(dtime)
	time = time + dtime
	if time < 5 then return end
	time = 0

	minetest.debug(state)
	if state == "start_request" then
		state = "wait_reply"
		http.fetch({url = "http://127.0.0.1:4444/exec_requests"},
			handle_http_result)
	elseif state == "execute" then
		minetest.debug("executing smth")
		state = "start_request"
	end
end)

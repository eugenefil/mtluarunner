-- TODO resend result on http error
-- TODO pretty traceback like in python w/ code lines etc
-- TODO disable catch_stdout on error

local insecure_env = minetest.request_insecure_environment()
if not insecure_env then
	minetest.log("error", "mtluarunner mod can't access insecure environment, please add it to secure.trusted_mods")
	return
end

local http = minetest.request_http_api()
if not http then
	minetest.log("error", "mtluarunner mod can't access http api")
	return
end

mtluarunner = {}
mtluarunner.locals = {}

local stdout = ""
local catch_stdout = false

local fetch_code

local function tostr(o)
	if type(o) == "string" then return o
	else return dump(o) end
end

local orig_print = print
print = function(...)
	if catch_stdout then
		local args = {...}
		local out = ""
		for i = 1, select("#", ...) do
			if i > 1 then out = out .. "\t" end
			out = out .. tostr(args[i])
		end
		stdout = stdout .. out .. "\n"
	end
	return orig_print(...)
end

-- level is from caller's pov (i.e. 0 means save caller's locals)
function mtluarunner.save_locals(level)
	if not level then level = 0 end
	local i = 1
	while true do
		local name, val = insecure_env.debug.getlocal(level + 2, i)
		if not name then return end
		if name:sub(1, 1) ~= "(" then -- skip special vars
			-- note: wrap var's value in table to keep nils
			mtluarunner.locals[name] = {val}
		end
		i = i + 1
	end
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

local function errhandler(root_chunk, err)
	-- find root chunk on stack and save its local vars
	local lvl = 0
	while true do
		local info = debug.getinfo(lvl + 2, "f")
		if not info then
			-- We looked through whole stack, but root
			-- chunk was not found. That means its frame
			-- was destroyed by tail call.
			break
		end
		if info.func == root_chunk then
			-- note: +1 below accounts for handler itself
			mtluarunner.save_locals(lvl + 1)
			break
		end
		lvl = lvl + 1
	end

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

local function transform(code)
	local orig_code = code
	-- Original code is valid, now let's try to append an
	-- instruction to save local vars before exiting chunk.
	--
	-- The other considered alternative to appending code is using
	-- debug.sethook() w/ return hook, which is executed right
	-- before exiting every function being called. The problem was
	-- you can access locals of the called function from inside
	-- the hook *only* when the function returns some value. If it
	-- has no 'return' statement, debug.getlocal() won't see any
	-- locals. Even worse, in special case when function ends w/
	-- plain empty 'return', debug.getlocal() sees all the locals,
	-- but their values are some random garbage. Also using the
	-- hook could be a performance hit w/ lots of calls, but no
	-- measurements were done.
	code = code .. '\n' .. "mtluarunner.save_locals()"
	local chunk = loadstring(code)
	if not chunk then
		-- Modified code is invalid, which means the last
		-- statement was non-empty return, in which case we
		-- don't save locals and fall back to original code.
		--
		-- When last statement is plain empty 'return', it
		-- will return the value of the appended save_locals()
		-- call, which returns nothing, so no problem here.
		code = orig_code
	end

	-- prepend declarations of locals, saved after running
	-- all previous codes, i.e. our local state
	local decls = ""
	for name in pairs(mtluarunner.locals) do
		local decl = string.format(
			"local %s = mtluarunner.locals.%s[1]",
			name, name)
		decls = decls .. decl .. "\n"
	end
	return decls .. code
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
		code = transform(code)
		chunk, err = loadstring(code)
		assert(chunk, err) -- transformed code must be valid

		catch_stdout = true
		result = get_result(xpcall(chunk, function(err)
			return errhandler(chunk, err) end))
		catch_stdout = false
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

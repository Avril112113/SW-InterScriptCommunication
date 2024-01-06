local ISC_Code_Gen = {}


--- tables are not deterministic, this is used to be deterministic.
---@param spec table
---@return string[]
local function _get_sorted_spec_keys(spec)
	local sorted_keys = spec._sorted_keys
	if sorted_keys == nil then
		sorted_keys = {}
		for key, _ in pairs(spec) do
			table.insert(sorted_keys, key)
		end
		table.sort(sorted_keys, function(a, b)
			local t1, t2 = type(a), type(b)
			return (t1 == t2 and a < b) or t1 < t2
		end)
		spec._sorted_keys = sorted_keys
	end
	return sorted_keys
end

---@param spec table
function ISC_Code_Gen._gen_encode_code(spec)
	local tmp_names, tmp_name_idx = {}, 1
	local function _get_tmp_name()
		local tmp_name = "_" .. tmp_name_idx
		table.insert(tmp_names, tmp_name)
		tmp_name_idx = tmp_name_idx + 1
		return tmp_name
	end
	local result_parts = {}
	local pack_fmt, pack_args = {}, {}
	local type_parts = {}
	local function _gen(_spec, path)
		if type(_spec) == "table" then
			table.insert(result_parts, "{")
			table.insert(type_parts, "{")
			local sorted_keys = _get_sorted_spec_keys(_spec)
			for _, key in ipairs(sorted_keys) do
				local value_spec = _spec[key]
				local key_index, key_path
				if type(key) == "string" then
					if key:match("^[%w_][%w%d_]*$") then
						key_index = ("%s"):format(key:gsub("\n", "\\n"):gsub("\r", "\\r"))
						key_path = ("%s.%s"):format(path, key_index)
					else
						key_index = ("[\"%s\"]"):format(key:gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"))
						key_path = ("%s%s"):format(path, key_index)
					end
				elseif type(key) == "number" then
					key_index = ("[%s]"):format(key)
					key_path = ("%s%s"):format(path, key_index)
				else
					error(("Unsupported ISC table key spec type '%s'"):format(_spec))
				end
				table.insert(result_parts, key_index)
				table.insert(type_parts, key_index)
				table.insert(result_parts, "=")
				table.insert(type_parts, ":")
				_gen(value_spec, key_path)
				table.insert(result_parts, ",")
				table.insert(type_parts, ",")
			end
			table.insert(result_parts, "}")
			table.insert(type_parts, "}")
		elseif _spec == "string" then
			table.insert(pack_fmt, "z")
			table.insert(pack_args, path)
			table.insert(result_parts, _get_tmp_name())
			table.insert(type_parts, "string")
		elseif _spec == "number" then
			table.insert(pack_fmt, "n")
			table.insert(pack_args, path)
			table.insert(result_parts, _get_tmp_name())
			table.insert(type_parts, "number")
		elseif _spec == "boolean" then
			table.insert(pack_fmt, "B")
			table.insert(pack_args, ("%s and 1 or 0"):format(path))
			table.insert(result_parts, ("%s ~= 0"):format(_get_tmp_name()))
			table.insert(type_parts, "boolean")
		else
			error(("Unsupported ISC spec type '%s'"):format(_spec))
		end
	end
	_gen(spec, "data")
	local encode_code = ("function(data) return string.pack(\"%s\", %s) end"):format(table.concat(pack_fmt), table.concat(pack_args, ", "))
	local decode_code = ("function(packed_data) local %s = string.unpack(\"%s\", packed_data) return %s end"):format(table.concat(tmp_names, ", "), table.concat(pack_fmt), table.concat(result_parts))
	local type_comment = table.concat(type_parts)
	return encode_code, decode_code, type_comment
end

---@param s string|any
---@return boolean
function ISC_Code_Gen._validate_name(s)
	return type(s) == "string" and s:match("^[%w%d_]+$")
end

function ISC_Code_Gen.gen_event(feature_id, name, data_spec)
	if not ISC_Code_Gen._validate_name(feature_id) then
		return nil, "Invalid feature_id"
	elseif not ISC_Code_Gen._validate_name(name) then
		return nil, "Invalid event name"
	end
	local encode_data_code, decode_data_code, type_data_comment = ISC_Code_Gen._gen_encode_code(data_spec)
	return ("---@type ISC_Event<%s>\n%s = ISC.registerEvent(\"%s\", \"%s\", %s, %s)"):format(type_data_comment, name, feature_id, name, encode_data_code, decode_data_code)
end

function ISC_Code_Gen.gen_request(feature_id, name, data_spec, result_spec)
	if not ISC_Code_Gen._validate_name(feature_id) then
		return nil, "Invalid feature_id"
	elseif not ISC_Code_Gen._validate_name(name) then
		return nil, "Invalid request name"
	end
	local encode_data_code, decode_data_code, type_data_comment = ISC_Code_Gen._gen_encode_code(data_spec)
	local encode_result_code, decode_result_code, type_result_comment = ISC_Code_Gen._gen_encode_code(result_spec)
	return ("---@type ISC_Request<%s,%s>\n%s = ISC.registerRequest(\"%s\", \"%s\", %s, %s, %s, %s)"):format(type_data_comment, type_result_comment, name, feature_id, name, encode_data_code, decode_data_code, encode_result_code, decode_result_code)
end


local args = {...}
if #args > 0 then
	local feature_id = args[1]
	local name = args[2]

	io.write("  Data spec: ")
	local data_spec = io.read()
	if data_spec:find("{") then
		data_spec = load("return " .. data_spec, "data_spec", "t", {})()  -- I am Lazy
	end

	io.write("Result spec: ")
	local result_spec = io.read()
	if result_spec:find("{") then
		result_spec = load("return " .. result_spec, "result_spec", "t", {})()  -- I am Lazy
	end

	if type(result_spec) == "table" or #result_spec > 0 then
		print()
		print("~~ Request code ~~")
		print(ISC_Code_Gen.gen_request(feature_id, name, data_spec, result_spec))
	else
		print()
		print("~~ Event code ~~")
		print(ISC_Code_Gen.gen_event(feature_id, name, data_spec))
	end
end


return ISC_Code_Gen


-- cls && lua isc_code_gen.lua ISC discovery
-- { isc_version="string", feature_id="string", version="string", }
-- print(ISC_Code_Gen.gen_event(
-- 	"ISC", "discovery",
-- 	{
-- 		isc_version="string",
-- 		feature_id="string",
-- 		version="string",
-- 	}
-- ))

-- test_feature test_event
-- { foo="string", bar="string", baz={ a="number", b="number", c="number", }, on="boolean", off="boolean", }
-- print(ISC_Code_Gen.gen_event(
-- 	"test_feature", "test_event",
-- 	{
-- 		foo="string",
-- 		bar="string",
-- 		baz={
-- 			a="number",
-- 			b="number",
-- 			c="number",
-- 		},
-- 		on="boolean",
-- 		off="boolean",
-- 	}
-- ))

-- test_feature test_request
-- string
-- number
-- print(ISC_Code_Gen.gen_request(
-- 	"test_feature", "test_request",
-- 	"string",
-- 	"number"
-- ))

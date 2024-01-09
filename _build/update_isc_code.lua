local ISC_CodeGen = require "_build.isc_code_gen"


---@param s string
---@return table
local function parse_luals_table(s)
	local i = 2
	local obj = {}
	while true do
		local key, value, ni
		key, value, ni = s:match("^[ ]*([%w_][%d%w_]*)[ ]*:[ ]*(%b{})[ ]*[,;]?[ ]*}?()", i)
		if ni then
			i = ni
			obj[key] = parse_luals_table(value)
		else
			key, value, ni = s:match("^[ ]*([%w_][%d%w_]*)[ ]*:[ ]*(%w+)[ ]*[,;]?[ ]*}?()", i)
			if ni then
				i = ni
				obj[key] = value
			else
				break
			end
		end
	end
	return obj
end


---@param spec_info string
---@return (string|table)[]
local function parse_spec_info(spec_info)
	local specs = {}
	local i = 0
	while true do
		local match, array, ni = spec_info:match("^[ ]*(%b{})(%[?%]?)[ ]*,?()", i)
		if match then
			i = ni
			if #array ~= 0 then
				table.insert(specs, ISC_CodeGen.array(parse_luals_table(match)))
			else
				table.insert(specs, parse_luals_table(match))
			end
		else
			match, array, ni = spec_info:match("^[ ]*([%w_][%d%w_]*)(%[?%]?)[ ]*,?()", i)
			if match then
				i = ni
				if #array ~= 0 then
					table.insert(specs, ISC_CodeGen.array(match))
				else
					table.insert(specs, match)
				end
			else
				break
			end
		end
	end
	return specs
end


---@param workspaceRoot Filepath
---@param inputFile Filepath
return function(workspaceRoot, inputFile)
	local FSUtils = LifeBoatAPI.Tools.FileSystemUtils
	local Filepath = LifeBoatAPI.Tools.Filepath

	local text = FSUtils.readAllText(inputFile)

	local replaceCount
	text, replaceCount = text:gsub(
		"(\n[ \t]*)%-%-%-@type[ ]+ISC_(%w+)<([^\n]-)>(.-)\n([^\n]-\n)",
		---@param isc_type string
		---@param spec_info string
		---@param next_line string
		function(preprefix, isc_type, spec_info, type_comment, next_line)
			if isc_type ~= "Event" and isc_type ~= "Request" then return end
			local feature_id, name
			local specs = parse_spec_info(spec_info)
			local prefix, prefix_end = next_line:match("^(.-[=\n][ \t]*)()")
			local middle, suffix = next_line:match("(.+)([,;}])\n", prefix_end)
			if middle == nil then
				middle = next_line:match("(.+)\n", prefix_end)
			end
			if suffix == nil and prefix:sub(-1) == "\n" then
				prefix = prefix:sub(1, -2) .. " = "
				suffix = ""
			end
			if middle ~= nil then
				feature_id = feature_id or middle:match("%([ \t]*\"(.-)\"")
				name = name or middle:match(",[ \t]*\"(.-)\"")
			end
			feature_id = feature_id or "<FEATURE_ID>"
			name = name or "<NAME>"
			local code
			if isc_type == "Event" and #specs == 1 then
				local encode_data_code, decode_data_code = ISC_CodeGen._gen_encode_code(specs[1])
				code = ("ISC.registerEvent(\"%s\", \"%s\", --[[@diagnostic disable-line]]%s, %s)"):format(feature_id, name, encode_data_code, decode_data_code)
			elseif isc_type == "Request" and #specs == 2 then
				local encode_data_code, decode_data_code = ISC_CodeGen._gen_encode_code(specs[1])
				local encode_result_code, decode_result_code = ISC_CodeGen._gen_encode_code(specs[2])
				code = ("ISC.registerRequest(\"%s\", \"%s\", --[[@diagnostic disable-line]]%s, %s, %s, %s)"):format(feature_id, name, encode_data_code, decode_data_code, encode_result_code, decode_result_code)
			else
				return
			end
			return assert(("%s---@type ISC_%s<%s> # %s:%s\n%s%s%s\n"):format(preprefix, isc_type, spec_info, feature_id, name, prefix or "", code, suffix or ""))
		end
	)

	if replaceCount > 0 then
		FSUtils.writeAllText(inputFile, text)
	end
end

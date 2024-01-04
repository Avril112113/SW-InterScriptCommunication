---@alias ISC_ObjSpec "string"|"number"|"boolean"|table<string,ISC_ObjSpec>|"dynamic"
---@alias ISC_SupportedTypes string|number|boolean|table<string,ISC_SupportedTypes>
---@alias ISC_DiscoveredFeature {isc_version:string, feature_id:string, version:string}


local ISC_CMD_PAT = "^ISC_(%w+):([%w_]+):([%w_]+) (.*)$"
local ISC_EVENT_FMT = "ISC_EVENT:%s:%s %s"
local ISC_REQUEST_FMT = "ISC_REQUEST:%s:%s %s"
local ISC_RESULT_FMT = "ISC_RESULT:%s:%s %s"


---@class ISC
ISC = {}
ISC.VERSION = "0.1.0"
ISC.VERBOSE_LOG = true

---@type table<string, {}>
ISC.discovered_features = {}

---@type table<string, table<string, ISC_Event>>
ISC.events = {}
---@type table<string, table<string, ISC_Request>>
ISC.requests = {}

---@type boolean # Weather or not we are waiting for a result.
ISC._awaiting_result = false
---@type ISC_SupportedTypes # Temporary value used for results of requests.
ISC._tmp_result = nil


---@param msg string
function ISC._error(msg)
	local addon_name = server.getAddonData((server.getAddonIndex())).name
	server.announce("ISC "..addon_name, msg)
	debug.log(("[SW-%s-ISC] [error]: %s"):format(addon_name, msg))
	error()  -- This function doesn't exist, but it works for stopping execution.
end

---@param msg string
function ISC._warn(msg)
	local addon_name = server.getAddonData((server.getAddonIndex())).name
	server.announce("ISC "..addon_name, msg)
	debug.log(("[SW-%s-ISC] [warn]:  %s"):format(addon_name, msg))
end

---@param msg string
function ISC._verbose(msg)
	local addon_name = server.getAddonData((server.getAddonIndex())).name
	debug.log(("[SW-%s-ISC] [debug]: %s"):format(addon_name, msg))
end

--- tables are not deterministic, this is used to be deterministic.
---@param spec table
function ISC._get_sorted_spec_keys(spec)
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

local _dynaimic_type_ids = {
	number=1,
	string=2,
	boolean=3,
	table=4,
	dynamic=255,
}
local _dynaimic_id_types = {}
for i, v in pairs(_dynaimic_type_ids) do
	_dynaimic_id_types[v] = i
end
---@param spec ISC_ObjSpec
---@param data ISC_SupportedTypes
---@return string
function ISC._encode_data(spec, data)
	local pack_fmt, pack_data = {}, {}
	---@param _spec ISC_ObjSpec
	---@param _data ISC_SupportedTypes
	---@param path string
	local function _processes_spec(_spec, _data, path)
		if type(_spec) == "string" then
			if _spec == "string" then
				if type(_data) ~= "string" then
					ISC._error(("Invalid pack data at %s, expected %s but got %s"):format(path, _spec, type(_data)))
				end
				table.insert(pack_fmt, "z")
				table.insert(pack_data, _data)
			elseif _spec == "number" then
				if type(_data) ~= "number" then
					ISC._error(("Invalid pack data at %s, expected %s but got %s"):format(path, _spec, type(_data)))
				end
				table.insert(pack_fmt, "n")
				table.insert(pack_data, _data)
			elseif _spec == "boolean" then
				if type(_data) ~= "boolean" then
					ISC._error(("Invalid pack data at %s, expected %s but got %s"):format(path, _spec, type(_data)))
				end
				table.insert(pack_fmt, "I1")
				table.insert(pack_data, _data and 1 or 0)
			elseif _spec == "dynamic" then
				local data_type = type(_data)
				table.insert(pack_fmt, "I1")
				table.insert(pack_data, _dynaimic_type_ids[data_type])
				---@diagnostic disable-next-line: param-type-mismatch
				_processes_spec(data_type, _data, path)
			elseif _spec == "table" then
				-- dynamic table
				---@cast _data table
				table.insert(pack_fmt, "J")
				table.insert(pack_data, 0)  -- Will be replaced.
				local count_idx = #pack_data
				local count = 0
				for i, v in pairs(_data) do
					count = count + 1
					_processes_spec("dynamic", i, path.."["..tostring(i).."]")
					_processes_spec("dynamic", v, path.."."..tostring(i))
				end
				pack_data[count_idx] = count
			end
		elseif type(_spec) == "table" then
			for _, key in ipairs(ISC._get_sorted_spec_keys(_spec)) do
				_processes_spec(_spec[key], _data[key], path.."."..tostring(key))
			end
		else
			ISC._error(("Invalid encode spec type %s"):format(tostring(_spec)))
		end
	end
	_processes_spec(spec, data, "data")
	-- server.command doesn't like null bytes, so we hack around it and hope it doesn't mess with the data.
	-- The only case this would mess with the data is if there was 3 bytes equal to `\\x0`
	local pack_data_str = string.pack(table.concat(pack_fmt), table.unpack(pack_data))
	if pack_data_str:find("\\x0") then
		-- Oh no...
		ISC._error("Spesific 3 byte sequence was found in the packed data.")
	end
	if ISC.VERBOSE_LOG then
		local parts = {}
		for i=1,#pack_data_str do
			table.insert(parts, ("0x%X "):format(pack_data_str:byte(i)))
		end
		ISC._verbose(("Encoded: %s"):format(table.concat(parts)))
	end
	return (pack_data_str:gsub("\x00", "\\x00"))
end

---@param spec ISC_ObjSpec
---@param packed_data string
---@return ISC_SupportedTypes
function ISC._decode_data(spec, packed_data)
	packed_data = packed_data:gsub("\\x00", "\x00")
	---@param _spec ISC_ObjSpec
	---@param path string
	---@param offset integer
	---@return ISC_SupportedTypes, integer
	local function _processes_spec(_spec, path, offset)
		if type(_spec) == "string" then
			if _spec == "string" then
				return string.unpack("z", packed_data, offset)
			elseif _spec == "number" then
				return string.unpack("n", packed_data, offset)
			elseif _spec == "boolean" then
				local value, new_offset = string.unpack("I1", packed_data, offset)
				return value ~= 0, new_offset
			elseif _spec == "dynamic" then
				local type_id, new_offset = string.unpack("I1", packed_data, offset)
				return _processes_spec(_dynaimic_id_types[type_id], path, new_offset)
			elseif _spec == "table" then
				local count, new_offset = string.unpack("J", packed_data, offset)
				local tbl = {}
				local key, value
				for i=1,count do
					key, new_offset = _processes_spec("dynamic", path.."["..i.."]", new_offset)
					value, new_offset = _processes_spec("dynamic", path.."."..tostring(key), new_offset)
					tbl[key] = value
				end
				return tbl, new_offset
			end
		elseif type(_spec) == "table" then
			local tbl = {}
			for _, key in ipairs(ISC._get_sorted_spec_keys(_spec)) do
				local value, new_offset = _processes_spec(_spec[key], path.."."..tostring(key), offset)
				tbl[key] = value
				offset = new_offset
			end
			return tbl, offset
		end
		---@diagnostic disable-next-line: missing-return
		ISC._error(("Invalid decode spec type %s"):format(tostring(_spec)))
	end
	return (_processes_spec(spec, "data", 1))
end

---@param name string
---@param s string|any
function ISC._validate_cmd_name_part(name, s)
	if type(s) ~= "string" or not s:match("^[%w%d_]+$") then
		ISC._error(name.." is invalid "..tostring(s))
	end
end

---@param full_message string
---@return boolean
function ISC.onCustomCommand(full_message)
	local isc_type, feature_id, name, data = full_message:match(ISC_CMD_PAT)
	if isc_type == nil or feature_id == nil or name == nil or data == nil then
		return false
	end
	if isc_type == "EVENT" then
		local isc_events = ISC.events[feature_id]
		if isc_events == nil then
			if ISC.VERBOSE_LOG then
				ISC._verbose(("Skipping event '%s:%s', non-registered event."):format(feature_id, name))
			end
			return false
		end
		local event = isc_events[name]
		if event == nil then
			if ISC.VERBOSE_LOG then
				ISC._verbose(("Skipping event '%s:%s', non-registered event."):format(feature_id, name))
			end
			return false
		end
		if ISC.VERBOSE_LOG then
			ISC._verbose(("Running event handlers for '%s:%s'."):format(feature_id, name))
		end
		event._run_handlers(ISC._decode_data(event.data_spec, data))
		return true
	elseif isc_type == "REQUEST" then
		local isc_requests = ISC.requests[feature_id]
		if isc_requests == nil then
			if ISC.VERBOSE_LOG then
				ISC._verbose(("Skipping request '%s:%s', non-registered event."):format(feature_id, name))
			end
			return false
		end
		local request = isc_requests[name]
		if request == nil then
			if ISC.VERBOSE_LOG then
				ISC._verbose(("Skipping request '%s:%s', non-registered event."):format(feature_id, name))
			end
			return false
		end
		if ISC.VERBOSE_LOG then
			ISC._verbose(("Running request handler for '%s:%s'."):format(feature_id, name))
		end
		request._run_handler(ISC._decode_data(request.data_spec, data))
		return true
	elseif isc_type == "RESULT" then
		if ISC._awaiting_result then
			local isc_requests = ISC.requests[feature_id]
			if isc_requests == nil then
				if ISC.VERBOSE_LOG then
					ISC._verbose(("Skipping result '%s:%s', non-registered event."):format(feature_id, name))
				end
				return false
			end
			local request = isc_requests[name]
			if request == nil then
				if ISC.VERBOSE_LOG then
					ISC._verbose(("Skipping result '%s:%s', non-registered event."):format(feature_id, name))
				end
				return false
			end
			if ISC.VERBOSE_LOG then
				ISC._verbose(("Setting result '%s' from '%s:%s'."):format(feature_id, name, tostring(data)))
			end
			ISC._tmp_result = ISC._decode_data(request.result_spec, data)
		end
		return true
	else
		-- Ignore if it's not a valid ISC type, but do log it.
		ISC._warn(("Got invalid ISC type '%s' from feature_id '%s' and name '%s'"):format(tostring(isc_type), tostring(feature_id), tostring(name)))
	end
	return false
end

---@generic TData  # Actually does nothing for us here, since functions can't take a generic at call.
---@param feature_id string
---@param name string
---@param data_spec ISC_ObjSpec
---@return ISC_Event<TData>
function ISC.registerEvent(feature_id, name, data_spec)
	ISC._validate_cmd_name_part("event feature_id", feature_id)
	ISC._validate_cmd_name_part("event name", name)

	local handlers = {}
	-- Typing must be a inherited table for generics to work correctly :/
	---@class ISC_Event<TData> : {feature_id:string, name:string, data_spec:ISC_ObjSpec, trigger:fun(data:TData), handle:fun(cb:fun(data:TData)), _run_handlers:fun(data:TData)}
	local event = {
		feature_id=feature_id,
		name=name,
		data_spec=data_spec,
		---@param data TData
		trigger=function(data)
			server.command(ISC_EVENT_FMT:format(feature_id, name, ISC._encode_data(data_spec, data)))
		end,
		handle=function(cb)
			table.insert(handlers, cb)
		end,
		_run_handlers=function(data)
			for _, handler in ipairs(handlers) do
				handler(data)
			end
		end,
	}
	ISC.events[feature_id] = ISC.events[feature_id] or {}
	if ISC.events[feature_id][name] ~= nil then
		ISC._error("Attempt to override already registered event "..name)
	end
	ISC.events[feature_id][name] = event
	return event
end

--- Requests must send a result on the same tick.
---@generic TData  # Actually does nothing for us here, since functions can't take a generic at call.
---@generic TResult  # Actually does nothing for us here, since functions can't take a generic at call.
---@param feature_id string
---@param name string
---@param data_spec ISC_ObjSpec
---@param result_spec ISC_ObjSpec
---@return ISC_Request<TData,TResult>
function ISC.registerRequest(feature_id, name, data_spec, result_spec)
	ISC._validate_cmd_name_part("event feature_id", feature_id)
	ISC._validate_cmd_name_part("event name", name)

	local handler
	-- Typing must be a inherited table for generics to work correctly :/
	---@class ISC_Request<TData,TResult> : {feature_id:string, name:string, data_spec:ISC_ObjSpec, result_spec:ISC_ObjSpec, request:(fun(data:TData):TResult), handle:fun(cb:fun(data:TData):TResult), _run_handler:fun(data:TData)}
	local request = {
		feature_id=feature_id,
		name=name,
		data_spec=data_spec,
		result_spec=result_spec,
		---@param data TData
		request=function(data)
			ISC._awaiting_result = true
			server.command(ISC_REQUEST_FMT:format(feature_id, name, ISC._encode_data(data_spec, data)))
			ISC._awaiting_result = false
			local result = ISC._tmp_result
			ISC._tmp_result = nil
			return result
		end,
		handle=function(cb)
			handler = cb
		end,
		_run_handler=function(data)
			if handler ~= nil then
				local result = handler(data)
				server.command(ISC_RESULT_FMT:format(feature_id, name, ISC._encode_data(result_spec, result)))
			end
		end,
	}
	ISC.requests[feature_id] = ISC.requests[feature_id] or {}
	if ISC.requests[feature_id][name] ~= nil then
		ISC._error("Attempt to override already registered request "..name)
	end
	ISC.requests[feature_id][name] = request
	return request
end

---@param feature_id string
---@param version string
function ISC.sendFeatureDiscoveryEvent(feature_id, version)
	ISC._feature_discovery_event.trigger({
		isc_version=ISC.VERSION,
		feature_id=feature_id,
		version=version
	})
end


---@type ISC_Event<ISC_DiscoveredFeature>
ISC._feature_discovery_event = ISC.registerEvent("ISC", "discovery", {
	isc_version="string",
	feature_id="string",
	version="string",
})

ISC._feature_discovery_event.handle(function(data)
	ISC.discovered_features[data.feature_id] = data
	if ISC.VERBOSE_LOG then
		ISC._verbose(("Recived feature discovery: isc_version=%s feature_id=%s version=%s"):format(data.isc_version, data.feature_id, data.version))
	end
end)

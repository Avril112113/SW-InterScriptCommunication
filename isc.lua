---@alias ISC_SupportedTypes string|number|boolean|table<string,ISC_SupportedTypes>
---@alias ISC_DiscoveredFeature {isc_version:string, feature_id:string, version:string}


local ISC_CMD_PAT = "^\xFC(.):([%w_]+):([%w_]+) (.*)$"
local ISC_EVENT_FMT = "\xFC\x01:%s:%s %s"
local ISC_REQUEST_FMT = "\xFC\x02:%s:%s %s"
local ISC_RESULT_FMT = "\xFC\x03:%s:%s %s"


---@class ISC
ISC = {}
ISC.VERSION = "0.1.0"
ISC.VERBOSE_LOG = false

---@type table<string, ISC_DiscoveredFeature>
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
	if isc_type == "\x01" then  -- Event
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
		event._run_handlers(data)
		return true
	elseif isc_type == "\x02" then  -- Request
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
		request._run_handler(data)
		return true
	elseif isc_type == "\x03" then  -- Result
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
			ISC._tmp_result = data
		end
		return true
	else
		-- Ignore if it's not a valid ISC type, but do log it.
		ISC._warn(("Got invalid ISC type '%s' from '%s:%s'"):format(tostring(isc_type), tostring(feature_id), tostring(name)))
	end
	return false
end

---@generic TData  # Actually does nothing for us here, since functions can't take a generic at call.
---@param feature_id string
---@param name string
---@param encode_data fun(data:TData):string
---@param decode_data fun(packed_data:string):TData
---@return ISC_Event<TData>
function ISC.registerEvent(feature_id, name, encode_data, decode_data)
	ISC._validate_cmd_name_part("event feature_id", feature_id)
	ISC._validate_cmd_name_part("event name", name)

	local handlers = {}
	-- Typing must be a inherited table for generics to work correctly :/
	---@class ISC_Event<TData> : {feature_id:string, name:string, trigger:fun(data:TData), handle:fun(cb:fun(data:TData)), _run_handlers:fun(data:TData)}
	local event = {
		feature_id=feature_id,
		name=name,
		---@param data TData
		trigger=function(data)
			local packed_data = encode_data(data)
			if ISC.VERBOSE_LOG then
				local parts = {}
				for i=1,#packed_data do
					table.insert(parts, ("0x%X"):format(string.byte(packed_data:sub(i, i))))
				end
				ISC._verbose(table.concat(parts, " "))
			end
			server.command(ISC_EVENT_FMT:format(feature_id, name, packed_data:gsub("\x00", "\x15\x15\x15")))
		end,
		handle=function(cb)
			table.insert(handlers, cb)
		end,
		_run_handlers=function(packed_data)
			local data = decode_data(packed_data:gsub("\x15\x15\x15", "\x00"))
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
---@param encode_data fun(data:TResult):string
---@param decode_data fun(packed_data:string):TResult
---@param encode_result fun(data:TResult):string
---@param decode_result fun(packed_data:string):TResult
---@return ISC_Request<TData,TResult>
function ISC.registerRequest(feature_id, name, encode_data, decode_data, encode_result, decode_result)
	ISC._validate_cmd_name_part("event feature_id", feature_id)
	ISC._validate_cmd_name_part("event name", name)

	local handler
	-- Typing must be a inherited table for generics to work correctly :/
	---@class ISC_Request<TData,TResult> : {feature_id:string, name:string, request:(fun(data:TData):TResult), handle:fun(cb:fun(data:TData):TResult), _run_handler:fun(data:TData)}
	local request = {
		feature_id=feature_id,
		name=name,
		---@param data TData
		request=function(data)
			ISC._awaiting_result = true
			server.command(ISC_REQUEST_FMT:format(feature_id, name, encode_data(data):gsub("\x00", "\x15\x15\x15")))
			ISC._awaiting_result = false
			if ISC._tmp_result == nil then
				ISC._error(("Request '%s:%s' was never handled!"):format(feature_id, name))
			end
			local result = decode_result(ISC._tmp_result:gsub("\x15\x15\x15", "\x00"))
			ISC._tmp_result = nil
			return result
		end,
		handle=function(cb)
			handler = cb
		end,
		_run_handler=function(packed_data)
			local data = decode_data(packed_data:gsub("\x15\x15\x15", "\x00"))
			if handler ~= nil then
				local result = handler(data)
				local packed_result = encode_result(result):gsub("\x00", "\x15\x15\x15")
				server.command(ISC_RESULT_FMT:format(feature_id, name, packed_result))
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
ISC._feature_discovery_event = ISC.registerEvent("ISC", "discovery", function(data) return string.pack("zzz", data.feature_id, data.isc_version, data.version) end, function(packed_data) local _1, _2, _3 = string.unpack("zzz", packed_data) return {feature_id=_1,isc_version=_2,version=_3,} end)


ISC._feature_discovery_event.handle(function(data)
	ISC.discovered_features[data.feature_id] = data
	if ISC.VERBOSE_LOG then
		ISC._verbose(("Recived feature discovery: isc_version=%s feature_id=%s version=%s"):format(data.isc_version, data.feature_id, data.version))
	end
end)

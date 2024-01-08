---@alias ISC_SupportedTypes string|number|boolean|table<string,ISC_SupportedTypes>
---@alias ISC_DiscoveredFeature {isc_version:string, feature_id:string, version:string}


local ISC_CMD_PAT = "^\xFC(.):([%w_]+):([%w_]+) (.*)$"
local ISC_EVENT_FMT = "\xFC\x01:%s:%s %s"
local ISC_REQUEST_FMT = "\xFC\x02:%s:%s %s"
local ISC_RESULT_FMT = "\xFC\x03:%s:%s %s"
local ISC_PLAYER_CMD_PAT = "^%?ISC ([%w_]+) ([%w_]+)(.*)$"


local ADDON_NAME = server.getAddonData((server.getAddonIndex())).name


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
	server.announce("ISC "..ADDON_NAME, msg)
	debug.log(("[SW-%s-ISC] [error]: %s"):format(ADDON_NAME, msg))
	error()  -- This function doesn't exist, but it works for stopping execution.
end

---@param msg string
function ISC._warn(msg)
	server.announce("ISC "..ADDON_NAME, msg)
	debug.log(("[SW-%s-ISC] [warn]:  %s"):format(ADDON_NAME, msg))
end

---@param msg string
function ISC._verbose(msg)
	debug.log(("[SW-%s-ISC] [debug]: %s"):format(ADDON_NAME, msg))
end

---@param name string
---@param s string|any
function ISC._validate_cmd_name_part(name, s)
	if type(s) ~= "string" or not s:match("^[%w%d_]+$") then
		ISC._error(name.." is invalid "..tostring(s))
	end
end

---@param tbl_str string
---@return any, string?
function ISC._parse_tbl_str(tbl_str)
	local tbl = {}
	local i = tbl_str:sub(1, 1) == "{" and 2 or 1
	while i <= #tbl_str do
		local key, value, ni, err
		key, ni = tbl_str:match("^%s*,?%s*(%w-)%s*=()", i)
		if key == nil then
			break
		end
		if not key:match("^%w+$") then
			key, _, err = ISC._parse_value_str(tbl_str, i)
			if err ~= nil then return nil, err end
		end
		value, ni, err = ISC._parse_value_str(tbl_str, ni)
		if err ~= nil then return nil, err end
		tbl[key] = value
		i = ni
	end
	if i ~= #tbl_str+1 and not tbl_str:match("%s*,?%s*}", i) then
		return nil, "Failed to parse table."
	end
	return tbl
end

---@param data_str string
---@param i integer?
---@return any, integer, string?
function ISC._parse_value_str(data_str, i)
	i = i or 1
	data_str = data_str:match("^%s*(.*)", i)
	local data, ni

	data, ni = data_str:match("^(%b{})()")
	if data then
		local data, err = ISC._parse_tbl_str(data)
		return data, i+ni, err
	end

	data, ni = data_str:match("^(%b\"\")()")
	if data then return data:sub(2, -2), i+ni end

	data, ni = data_str:match("^(%b\'\')()")
	if data then return data:sub(2, -2), i+ni end

	data, ni = data_str:match("^(%d[%d%w]*)()")
	data = tonumber(data)
	if data then
		return data, i+ni
	end

	data, ni = data_str:match("^(true)()")
	if data then return true, i+ni end

	data, ni = data_str:match("^(false)()")
	if data then return false, i+ni end

	data, ni = data_str:match("^(nil)()")
	if data then return nil, i+ni end

	return nil, i, "Parse fail."
end

---@param value any
---@param depth integer?
---@param nl string?
---@return string
function ISC._repr_value(value, depth, nl, indent)
	depth = depth or 0
	nl = nl or ""
	indent = indent or ""
	if type(value) == "string" then
		return ("\"%s\""):format(value)
	elseif type(value) == "table" then
		local parts = {}
		for i, v in pairs(value) do
			if not i:match("[%w_][%w%d_]*") then
				i = ("[%s]"):format(ISC._repr_value(i, depth+1, nl, indent))
			end
			table.insert(parts, i .. "=" .. ISC._repr_value(v, depth+1, nl, indent))
		end
		if #parts == 0 then return "{}" end
		return ("{%s%s%s}"):format(nl..string.rep(indent, depth), table.concat(parts, ","..nl..string.rep(indent, depth)), nl)
	end
	return tostring(value)
end

---@param full_message string
---@param player_allowed boolean
---@param peer_id integer
---@return boolean
function ISC.onCustomCommand(full_message, peer_id, player_allowed)
	local isc_type, feature_id, name, data = full_message:match(ISC_CMD_PAT)
	if isc_type == nil or feature_id == nil or name == nil or data == nil then
		if player_allowed then
			local player_name = server.getPlayerName(peer_id)
			feature_id, name, data = full_message:match(ISC_PLAYER_CMD_PAT)
			if feature_id == nil or name == nil or data == nil then return false end

			if #(data:match("^%s*(.*)%s*$")) <= 0 then
				server.announce("ISC-"..ADDON_NAME, "Data parse fail: argument missing.", peer_id)
				return true
			end
			local parsed_data, err_pos, err = ISC._parse_value_str(data:gsub("%(", "{"):gsub("%)", "}"))
			if err then
				server.announce("ISC-"..ADDON_NAME, ("Data parse fail at %s: %s"):format(err_pos, err), peer_id)
				return true
			end

			local event = ISC.events[feature_id] and ISC.events[feature_id][name]
			if event ~= nil then
				event._run_handlers(event._encode_data(parsed_data):gsub("\x00", "\x15\x15\x15"))
				ISC._verbose(("Handled event '%s:%s' ran by '%s' with data %s"):format(feature_id, name, player_name, ISC._repr_value(parsed_data)))
				server.announce("ISC-"..ADDON_NAME, ("Event %s:%s handled"):format(feature_id, name), peer_id)
			end

			local request = ISC.requests[feature_id] and ISC.requests[feature_id][name]
			if request ~= nil and request.has_handler() then
				ISC._awaiting_result = true
				request._run_handler(request._encode_data(parsed_data):gsub("\x00", "\x15\x15\x15"))
				ISC._awaiting_result = false
				if ISC._tmp_result == nil then
					server.announce("ISC-"..ADDON_NAME, ("Request %s:%s was not handled."):format(feature_id, name), peer_id)
					return true
				end
				local result = request._decode_result(ISC._tmp_result:gsub("\x15\x15\x15", "\x00"))
				ISC._tmp_result = nil
				ISC._verbose(("Handled request '%s:%s' ran by '%s' with data %s and result %s"):format(feature_id, name, player_name, ISC._repr_value(parsed_data), ISC._repr_value(result)))
				server.announce("ISC-"..ADDON_NAME, ("Request %s:%s handled"):format(feature_id, name) .. "\n" .. ISC._repr_value(result), peer_id)
			end

			return true
		end
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
---@param decode_data fun(encoded_data:string):TData
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
		_encode_data=encode_data, _decode_data=decode_data,
		---@param data TData
		trigger=function(data)
			local encoded_data = encode_data(data)
			if ISC.VERBOSE_LOG then
				local parts = {}
				for i=1,#encoded_data do
					table.insert(parts, ("0x%X"):format(string.byte(encoded_data:sub(i, i))))
				end
				ISC._verbose(table.concat(parts, " "))
			end
			server.command(ISC_EVENT_FMT:format(feature_id, name, encoded_data:gsub("\x00", "\x15\x15\x15")))
		end,
		handle=function(cb)
			table.insert(handlers, cb)
		end,
		_run_handlers=function(encoded_data)
			local data = decode_data(encoded_data:gsub("\x15\x15\x15", "\x00"))
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
---@param decode_data fun(encoded_data:string):TResult
---@param encode_result fun(data:TResult):string
---@param decode_result fun(encoded_data:string):TResult
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
		_encode_data=encode_data, _decode_data=decode_data,
		_encode_result=encode_result, _decode_result=decode_result,
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
		_run_handler=function(encoded_data)
			local data = decode_data(encoded_data:gsub("\x15\x15\x15", "\x00"))
			if handler ~= nil then
				local result = handler(data)
				local encoded_result = encode_result(result):gsub("\x00", "\x15\x15\x15")
				server.command(ISC_RESULT_FMT:format(feature_id, name, encoded_result))
			end
		end,
		has_handler=function()
			return handler ~= nil
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

--                 \/ Copied from ISC_DiscoveredFeature
---@type ISC_Event<{isc_version:string, feature_id:string, version:string}> # ISC:discovery
ISC._feature_discovery_event = ISC.registerEvent("ISC", "discovery", function(data) return string.pack("zzz", data.feature_id, data.isc_version, data.version) end, function(encoded_data) local _1, _2, _3 = string.unpack("zzz", encoded_data) return {feature_id=_1,isc_version=_2,version=_3,} end)


ISC._feature_discovery_event.handle(function(data)
	ISC.discovered_features[data.feature_id] = data
	if ISC.VERBOSE_LOG then
		ISC._verbose(("Recived feature discovery: isc_version=%s feature_id=%s version=%s"):format(data.isc_version, data.feature_id, data.version))
	end
end)

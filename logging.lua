-- Version: 1.1

do
	local SCRIPT_PREFIX = server.getAddonData((server.getAddonIndex())).name

	---@generic T
	---@param v? T
	---@param message? any
	---@return T
	---@return any ...
	local function assert(v, message, ...)
		if not v then
			debug.log("[SW-"..SCRIPT_PREFIX.."-logging] [error] " .. (message or "assertion failed!"))
			error(message or "assertion failed!")
		end
		return v, message, ...
	end

	local LOG_LEVEL_NAMES = {
		"error",
		"warn",
		"info",
		"debug",
	}
	local LOG_LEVEL_INDICES = {}
	for i, name in ipairs(LOG_LEVEL_NAMES) do
		LOG_LEVEL_INDICES[name] = i
	end

	---@type table<any, string>
	local additionalGlobalContext = {}


	local function _argsToStrTable(...)
		local args = {...}
		for i=1, #args do
			args[i] = tostring(args[i])
		end
		return args
	end


	---@param tbl {level:number|string?, peer_id:number?, additionalContext:string[]?}
	function _log(tbl)
		g_savedata.log_level = g_savedata.log_level or DEFAULT_LOG_LEVEL

		local level = tbl.level or -1
		local peer_id = tbl.peer_id or -1
		local additionalContext = tbl.additionalContext or {}

		if type(level) == "string" then
			level = assert(LOG_LEVEL_INDICES[level], "Invalid log level '" .. level .. "'")
		end

		local args = _argsToStrTable(table.unpack(tbl))
		local msg = table.concat(args, " "):gsub("\x00", "\\x00")

		if level <= 0 or level <= g_savedata.log_level then
			local nameParts = {
				SCRIPT_PREFIX,
				level <= 0 and "" or " - " .. assert(LOG_LEVEL_NAMES[level], "Invalid log level " .. tostring(level)),
			}
			server.announce(table.concat(nameParts), msg, peer_id)
		end
		local debugLogLinePrefix = "[SW-" .. SCRIPT_PREFIX .. "] " .. (level <= 0 and "" or ("%-8s"):format("[" .. assert(LOG_LEVEL_NAMES[level], "Invalid log level " .. tostring(level)) .. "]"))
		local debugLogPartsPrefixParts = {
			peer_id < 0 and "" or "[->" .. server.getPlayerName(peer_id) .. "] ",
		}
		for _, s in pairs(additionalGlobalContext) do
			table.insert(debugLogPartsPrefixParts, ("[%s] "):format(s))
		end
		for _, s in ipairs(additionalContext) do
			table.insert(debugLogPartsPrefixParts, ("[%s] "):format(s))
		end
		local debugLogPrefix = table.concat(debugLogPartsPrefixParts)
		local debugLogParts = {
			debugLogLinePrefix,
			debugLogPrefix,
			msg,
		}
		local debugLog = table.concat(debugLogParts):gsub("\n", "\n" .. debugLogLinePrefix .. string.rep(" ", #debugLogPrefix))
		debug.log(debugLog)
	end

	---@param id any
	---@param s string|nil
	function log_setContext(id, s)
		additionalGlobalContext[id] = s
	end

	function log_debug(...)
		_log({level=4, ...})
	end

	function log_info(...)
		_log({level=3, ...})
	end
	log = log_info

	function log_warn(...)
		_log({level=2, ...})
	end

	function log_error(...)
		_log({level=1, ...})
	end

	function log_call(name, ...)
		_log({level=4, name .. "(" .. table.concat(_argsToStrTable(...), ", ") .. ")"})
	end

	function log_sendPeer(peer_id, ...)
		_log({peer_id=peer_id, ...})
	end

	function log_cmdResponse(command, peer_id, ...)
		_log({peer_id=peer_id, additionalContext={command}, ...})
	end
end
DEFAULT_LOG_LEVEL = 4  -- Only affects what is put into chat, not the debug logs.
require("logging")
require("isc")

g_savedata = {}


local ADDON_NAME = server.getAddonData((server.getAddonIndex())).name


---@type ISC_Event<{bar:string,baz:{a:number,b:number,c:number},foo:string,off:boolean,on:boolean}> # test_feature:test_event
test_event = ISC.registerEvent("test_feature", "test_event", --[[@diagnostic disable-line]]function(data) return string.pack("znnnzBB", data.bar, data.baz.a, data.baz.b, data.baz.c, data.foo, data.off and 1 or 0, data.on and 1 or 0) end, function(encoded_data, offset) local _1, _2, _3, _4, _5, _6, _7, offset = string.unpack("znnnzBB", encoded_data, offset) return {bar=_1,baz={a=_2,b=_3,c=_4,},foo=_5,off=_6 ~= 0,on=_7 ~= 0,}, offset end)

-- This handler will also handle locally triggered events.
test_event.handle(function(data)
	log_info("test_event", data.foo, data.bar, data.baz.a, data.baz.b, data.baz.c, data.on, data.off)
end)


---@type ISC_Request<string,number> # test_feature:test_request
test_request = ISC.registerRequest("test_feature", "test_request", --[[@diagnostic disable-line]]function(data) return string.pack("z", data) end, function(encoded_data, offset) local _1, offset = string.unpack("z", encoded_data, offset) return _1, offset end, function(data) return string.pack("n", data) end, function(encoded_data, offset) local _1, offset = string.unpack("n", encoded_data, offset) return _1, offset end)

if ADDON_NAME ~= "TestAddon2" then
	-- This handler will also handle locally triggered requests.
	test_request.handle(function(data)
		-- log_info("test_request", data)
		return tonumber(data:match("%d+")) or -1
	end)
end

---@type ISC_Event<number[]> # test_feature:test_array_event
test_array_event = ISC.registerEvent("test_feature", "test_array_event", --[[@diagnostic disable-line]]function(data) return string.pack("I2s2", #data, ISC._encode_array(function(data) return string.pack("n", data) end, data)) end, function(encoded_data, offset) local _1, _2, offset = string.unpack("I2s2", encoded_data, offset) return ISC._decode_array(function(encoded_data, offset) local _1, offset = string.unpack("n", encoded_data, offset) return _1, offset end, _2, _1), offset end)

-- This handler will also handle locally triggered events.
test_array_event.handle(function(data)
	local parts = {}
	for i, v in ipairs(data) do
		table.insert(parts, ("%s=%s"):format(i, v))
	end
	log_info("test_array_event", table.concat(parts, ", "))
end)


function onCreate()
	log_debug("onCreate()")

	if ADDON_NAME == "TestAddon2" then
		for _, feature in pairs(ISC.discovered_features) do
			log_debug(("Feature %s ISC_Ver=%s Ver=%s"):format(feature.feature_id, feature.isc_version, feature.version))
		end
		return
	end

	ISC.sendFeatureDiscoveryEvent("test_feature", "0.0.1")

	-- ?ISC test_feature test_event (foo="foo",bar="bar",baz=(a=1, b=2, c=3,),on=true,off=false,)
	-- test_event.trigger({
	-- 	foo="foo",
	-- 	bar="bar",
	-- 	baz={
	-- 		a=1,
	-- 		b=2,
	-- 		c=3,
	-- 	},
	-- 	on=true,
	-- 	off=false,
	-- })

	-- ?ISC test_feature test_request "foo123bar456"
	-- local result = test_request.request("abc123")
	-- log_info("test_request.request(\"abc123\")", result)
end

function onDestroy()
	log_info("onDestroy()")
end

---@param full_message string
---@param peer_id number
---@param is_admin boolean
---@param is_auth boolean
---@param command string
---@param ... string
function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, ...)
	if is_admin and ISC.onCustomCommand(full_message, peer_id, is_admin) then return end

	if full_message == "?t" then
		if ADDON_NAME == "TestAddon2" then return end
		test_event.trigger({
			foo="foo",
			bar="bar",
			baz={
				a=1,
				b=2,
				c=3,
			},
			on=true,
			off=false,
		})
		log_debug("test_request", test_request.request(ADDON_NAME))
		test_array_event.trigger({1, 2, 3, 4, 5, 6, 7, 8, 9})
	-- elseif full_message == "?p" then
	-- 	if ADDON_NAME == "TestAddon2" then return end
	-- 	-- local test_data = {
	-- 	-- 	foo="foo",
	-- 	-- 	bar="bar",
	-- 	-- 	baz={
	-- 	-- 		a=1,
	-- 	-- 		b=2,
	-- 	-- 		c=3,
	-- 	-- 	},
	-- 	-- 	on=true,
	-- 	-- 	off=false,
	-- 	-- }
	-- 	local start = server.getTimeMillisec()
	-- 	for i=1,100000 do
	-- 		-- test_event.trigger(test_data)
	-- 		test_request.request(ADDON_NAME)
	-- 	end
	-- 	local finish = server.getTimeMillisec()
	-- 	log_debug(("Took %dms (%sms per call)"):format(finish-start, (finish-start)/100000))
	else
		log_warn("COMMAND", peer_id, is_admin, is_auth, full_message)
	end
end

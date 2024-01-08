DEFAULT_LOG_LEVEL = 4  -- Only affects what is put into chat, not the debug logs.
require("logging")
require("isc")

g_savedata = {}


local ADDON_NAME = server.getAddonData((server.getAddonIndex())).name


---@type ISC_Event<{bar:string,baz:{a:number,b:number,c:number},foo:string,off:boolean,on:boolean}> # test_feature:test_event
test_event = ISC.registerEvent("test_feature", "test_event", function(data) return string.pack("znnnzBB", data.bar, data.baz.a, data.baz.b, data.baz.c, data.foo, data.off and 1 or 0, data.on and 1 or 0) end, function(packed_data) local _1, _2, _3, _4, _5, _6, _7 = string.unpack("znnnzBB", packed_data) return {bar=_1,baz={a=_2,b=_3,c=_4,},foo=_5,off=_6 ~= 0,on=_7 ~= 0,} end)

-- This handler will also handle locally triggered events.
test_event.handle(function(data)
	log_info("test_event", data.foo, data.bar, data.baz.a, data.baz.b, data.baz.c, data.on, data.off)
end)


---@type ISC_Request<string,number> # test_feature:test_request
test_request = ISC.registerRequest("test_feature", "test_request", function(data) return string.pack("z", data) end, function(packed_data) local _1 = string.unpack("z", packed_data) return _1 end, function(data) return string.pack("n", data) end, function(packed_data) local _1 = string.unpack("n", packed_data) return _1 end)

if ADDON_NAME ~= "TestAddon2" then
	-- This handler will also handle locally triggered requests.
	test_request.handle(function(data)
		-- log_info("test_request", data)
		return tonumber(data:match("%d+")) or -1
	end)
end


function onCreate()
	log_debug("onCreate()")

	if ADDON_NAME == "TestAddon2" then
		for _, feature in pairs(ISC.discovered_features) do
			log_debug(("Feature %s ISC_Ver=%s Ver=%s"):format(feature.feature_id, feature.isc_version, feature.version))
		end
		return
	end

	ISC.sendFeatureDiscoveryEvent("test_feature", "0.0.1")

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

	-- local result = test_request.request("abc123")
	-- log_info("test_request.request(ADDON_NAME)", result)
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
	if is_admin and ISC.onCustomCommand(full_message) then return end

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

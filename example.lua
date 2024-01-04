-- This example is not tested, it's stuff from script.lua put here to easier viewing.

require("isc")  -- Using `require()` requires LifeBoatAPI.


---- Event ----
---@type ISC_Event<{foo:string,bar:string,baz:{a:number,b:number,c:number}}>
local test_event = ISC.registerEvent("test_feature", "test_event", {
	foo="string",
	bar="string",
	baz={
		a="number",
		b="number",
		c="number",
	},
})

-- This handler will also handle locally triggered events.
test_event.handle(function(data)
	server.announce("ISC example", ("test_event %s %s %s %s %s %s"):format(data.foo, data.bar, data.baz, data.baz.a, data.baz.b, data.baz.c))
end)


---- Request ----
---@type ISC_Request<string,number>
local test_request = ISC.registerRequest("test_feature", "test_request", "string", "number")

-- This handler will also handle locally triggered requests.
test_request.handle(function(data)
	server.announce("ISC example", ("test_request %s"):format(data))
	return tonumber(data:match("%d+")) or -1
end)


function onCreate()
	server.announce("ISC example", "onCreate()")

	ISC.sendFeatureDiscoveryEvent("test_feature", "0.0.1")

	test_event.trigger({
		foo="foo",
		bar="bar",
		baz={
			a=1,
			b=2,
			c=3,
		}
	})

	local result = test_request.request("abc123")
	server.announce("ISC example", ("test_request.request(ADDON_NAME) %s"):format(result))
end

---@param full_message string
---@param peer_id number
---@param is_admin boolean
---@param is_auth boolean
---@param command string
---@param ... string
function onCustomCommand(full_message, peer_id, is_admin, is_auth, command, ...)
	if is_admin and ISC.onCustomCommand(full_message) then return end
end

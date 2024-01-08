# Inter-Script Communication for StormWorks
This was mostly an experiment to see how well Inter-Script Communication could be done for StormWorks.  
[`isc.lua`](isc.lua) is the library for Inter-Script Communication.  
[`_build/isc_code_gen.lua`](_build/isc_code_gen.lua) is used to generate the code for events and requests (this can be run directly as a CLI).  
[`_build/update_isc_code.lua`](_build/update_isc_code.lua) generates event/request source code with specific type comment.  

This library works because when `server.command` is called, the current execution is paused and `onCustomCommand` gets called for every addon.  
Once all `onCustomCommand` has been called, execution is resumed in the original addon that called `server.command`.  

The rest is rather simple, define an event or request in both addons and trigger/handle that event or request as necessary.  


## update_isc_code.lua
Check [_build/_buildactions.lua](_build/_buildactions.lua) for setup example.  
This file will automatically generate/update ISC event or request code based on a type comment upon building with LifeBoatAPI.  
Examples:
```lua
---@type ISC_Event<nil>
local some_event

---@type ISC_Request<string,number>
local some_request

---@type ISC_Request<string,number> # test_feature:test_request
local existing_request = ISC.registerRequest("test_feature", "test_request", <SHORTENED_FOR_READABILITY...>)

local t = {
	---@type ISC_Event<nil>
	event_in_table=nil,
}
```
Note: Update the feature_id and event/request name in the generated strings, not the type comment.  


## Notes
Request handlers should only have only 1 handler across all addons.  
It's possible to add multiple handlers to a request with in different addons.  


## TODO
Variable length arrays.  
Check for `server.command` max command length, if so, split data into multiple calls.  

# Inter-Script Communication for StormWorks
This was mostly an experiment to see how well Inter-Script Communication could be done for StormWorks.  
[`isc.lua`](isc.lua) is the library for Inter-Script Communication.  
[`isc_code_gen.lua`](isc_code_gen.lua) is used to generate the code for events and requests.  

This library works because when `server.command` is called, the current execution is paused and `onCustomCommand` gets called for every addon.  
Once all `onCustomCommand` has been called, execution is resumed in the original addon that called `server.command`.  

The rest is rather simple, define an event or request in both addons and trigger/handle that event or request as necessary.  


## Notes
Request handlers should only have only 1 handler across all addons.  
It's possible to add multiple handlers to a request with in different addons.  


## TODO
Commands to trigger events and requests.  

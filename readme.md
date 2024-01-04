# Inter-Script Communication for StormWorks
This was mostly an experiment to see how well Inter-Script Communication could be done for StormWorks.  
[`isc.lua`](isc.lua) is the library for Inter-Script Communication.  

This library works because when `server.command` is called, the current execution is paused and `onCustomCommand` gets called for every addon.  
Once all `onCustomCommand` has been called, execution is resumed in the original addon that called `server.command`.  

The rest is rather simple, define an event or request in both addons and trigger/handle that event or request as necessary.  

See [`example.lua`](example.lua) for simple usage example.  


## Notes
Request handlers should only have only 1 handler across all addons.  
It's possible to add multiple handlers to a request with in different addons.  

Using `dynamic` for data and result specs is very slow compared to providing proper typing, with over 2x difference.  


## TODO
Commands to trigger events and requests.  

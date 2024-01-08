--- Developed using LifeBoatAPI - Stormworks Lua plugin for VSCode - https://code.visualstudio.com/download (search "Stormworks Lua with LifeboatAPI" extension)
--- If you have any issues, please report them here: https://github.com/nameouschangey/STORMWORKS_VSCodeExtension/issues - by Nameous Changey

-- Callbacks for handling the build process
-- Allows for running external processes, or customising the build output to how you prefer
-- Recommend using LifeBoatAPI.Tools.FileSystemUtils to simplify life

-- Note: THIS FILE IS NOT SANDBOXED. DO NOT REQUIRE CODE FROM LIBRARIES YOU DO NOT 100% TRUST.


package.path = package.path .. ";../AvrilsSWTools/AddonUpdater/?.lua"
local update_addon = require "update_addon"

package.path = package.path .. ";../AvrilsSWTools/CodeGen_RequireFolder/?.lua"
local require_folder = require "require_folder"

local update_isc_code = require "_build.update_isc_code"


local startTime

---@param builder Builder           builder object that will be used to build each file
---@param params MinimizerParams    params that the build process usees to control minification settings
---@param workspaceRoot Filepath    filepath to the root folder of the project
function onLBBuildStarted(builder, params, workspaceRoot)
	startTime = os.clock()
	builder.filter = "script%.lua"
end

--- Runs just before each file is built
---@param builder Builder           builder object that will be used to build each file
---@param params MinimizerParams    params that the build process usees to control minification settings
---@param workspaceRoot Filepath    filepath to the root folder of the project
---@param name string               "require"-style name of the script that's about to be built
---@param inputFile Filepath        filepath to the file that is about to be built
function onLBBuildFileStarted(builder, params, workspaceRoot, name, inputFile)
	require_folder(workspaceRoot, inputFile)
	update_isc_code(workspaceRoot, inputFile)
end

---@param builder Builder           builder object that will be used to build each file
---@param params MinimizerParams    params that the build process usees to control minification settings
---@param workspaceRoot Filepath    filepath to the root folder of the project
function onLBBuildComplete(builder, params, workspaceRoot)
	update_addon(builder, workspaceRoot, {
		addon_name="TestAddon1",
	})
	update_addon(builder, workspaceRoot, {
		addon_name="TestAddon2",
	})

	print("Build took: ", os.clock() - startTime)
	startTime = nil
end

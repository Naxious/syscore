local RunService = game:GetService("RunService")

local INIT_FUNCTION_NAME = "Init"
local METHOD_TIMEOUT_SECONDS = 5

export type Syscore = {
	Icon: string?,
	Name: string,
	Priority: number,
	[any]: any,
}

local addedModules: { { sysModule: Syscore, failedOnce: boolean } } = {}
local errors: { [string]: { { sysModule: Syscore, response: string } } } = {}
local isInitialized = false

--[=[
	@class Syscore

	- Wally Package: [Syscore](https://wally.run/package/naxious)

	Syscore is a module that allows you to easily manage the initialization of your modules in a specific order.
	This is useful for when you have modules that depend on each other and need to be initialized in a specific order.
	You can enable/disable debug mode to see the load order of your modules.

	`Any module that you have can be loaded with Syscore! No special requirements needed inside your modules.`

	If you have a Init() method in your module, Syscore will call it when initializing your module.
	If you do not have an Init() method, Syscore will skip it.

	You can also specfiy a Prioty, Name, and Icon for your module.
	This is useful for debugging purposes.

	Here is a few examples of how a module could look like with Syscore:
	```lua
	local module = {
		Name = "Module1",
		Priority = 1,
		Icon = "😁"
	}

	function module:Init()
		print("Module1 initialized!")
	end

	return module
	```

	```lua
	local module = {}
	module.Priority = 2

	return module
	```

	```lua
	local module = {}

	return module
	```

	Here is an example of how to use Syscore to initialize a folder of modules:
	```lua
	local Syscore = require(path.to.Syscore)
	local folder = game:GetService("ReplicatedStorage").Modules

	Syscore:AddFolderOfModules(folder)
	Syscore:Start()
	```

	:::note
		When using Syscore you will need to require it from a local script, or server script.
		Once you have added all of your modules, you can call `Syscore:Start()` to initialize them.
	:::
]=]

--[=[
	@within Syscore
	@prop ShowLoadOrder boolean
	@tag Boolean

	Determines whether or not to show the load order of your modules when initializing them.
	This debug print is useful for debugging purposes.
	Default, this is set to true.
	```lua
	local Syscore = require(path.to.Syscore)
	Syscore.ShowLoadOrder = true
	```
]=]

local Syscore = {
	ShowLoadOrder = true,
}

local function prioritySortAddedModules()
	table.sort(addedModules, function(a, b)
		return a.sysModule.Priority < b.sysModule.Priority
	end)

	if Syscore.ShowLoadOrder then
		warn(`[Syscore] {RunService:IsServer() and "Server" or "Client"} load order:`)
		for loadOrder, module in addedModules do
			local iconString = module.sysModule.Icon and `{module.sysModule.Icon} ` or "🔴"
			warn(`{loadOrder} - [{iconString}{module.sysModule.Name}] :: {module.sysModule.Priority}`)
		end
	end
end

local function initializeSyscore(methodName: string)
	methodName = if typeof(methodName) == "string" then methodName else INIT_FUNCTION_NAME

	if not errors[methodName] then
		errors[methodName] = {}
	end

	for _, data in addedModules do
		if data.failedOnce then
			continue
		end

		local success, errorMessage = pcall(function()
			local yieldCoroutine = coroutine.create(function()
				task.spawn(function()
					if typeof(data.sysModule[methodName]) == "function" then
						data.sysModule[methodName](data.sysModule)
					end
				end)
			end)

			local yieldTime = 0

			local executed, message = coroutine.resume(yieldCoroutine)
			if not executed then
				error(message, 2)
			end

			while coroutine.status(yieldCoroutine) == "suspended" do
				yieldTime += task.wait(1)

				if yieldTime > METHOD_TIMEOUT_SECONDS then
					warn(
						`[Syscore] Module {data.sysModule.Name}:{methodName} took more than {METHOD_TIMEOUT_SECONDS} seconds to initialize.`
					)
					data.failedOnce = true
					return
				end
			end

			if coroutine.status(yieldCoroutine) == "dead" and not executed then
				error(message)
			end
		end)

		if not success then
			table.insert(errors[methodName], { sysModule = data.sysModule, response = errorMessage })
			warn(
				`[Syscore] Module {data.sysModule.Name}:{methodName} failed to initialize: {errorMessage}\n{debug.traceback()}`
			)
		end
	end
end

local function ModuleWithSameNameExists(module: ModuleScript)
	for _, data in addedModules do
		if data.sysModule.Name == module.Name or data.sysModule.Name == module:GetFullName() then
			warn(`[Syscore] {data.sysModule.Name} is already in the sysModules list.`)
			return true
		end
	end

	return false
end

local function addModule(module: ModuleScript)
	if isInitialized then
		warn(`[Syscore] Cannot add {module.Name} after Syscore has started.`)
		return
	end

	if not module:IsA("ModuleScript") then
		return
	end

	if ModuleWithSameNameExists(module) then
		return
	end

	local success, errorMessage = pcall(function()
		local newModule = require(module)

		newModule.Icon = newModule.Icon or "🔴"
		newModule.Name = newModule.Name or `{module:GetFullName()}`
		newModule.Priority = newModule.Priority or math.huge

		table.insert(addedModules, { sysModule = newModule, failedOnce = false})
	end)

	if not success then
		warn(`[Syscore] Failed to add "{module.Name}" ModuleScript: {errorMessage}\n{debug.traceback()}`)
	end
end

--[=[
	Requires all modules that are direct children of the folder.

	```lua
	local Syscore = require(path.to.Syscore)
	local folder = game:GetService("ReplicatedStorage").Modules

	Syscore:AddFolderOfModules(folder)
	```
]=]
function Syscore:AddFolderOfModules(folder: Folder)
	assert(folder and folder:IsA("Folder"), `[Syscore] {folder.Name} is not a folder.`)

	if isInitialized then
		warn(`[Syscore] Cannot add {folder.Name} after Syscore has started.`)
		return
	end

	for _, module in folder:GetChildren() do
		addModule(module)
	end
end

--[=[
	Add a module to be initialized.

	```lua
	local Syscore = require(path.to.Syscore)
	local module = require(path.to.module)

	Syscore:AddModule(module)
	```
]=]
function Syscore:AddModule(module: ModuleScript)
	assert(module and module:IsA("ModuleScript"), `[Syscore] {module.Name} is not a ModuleScript.`)

	if isInitialized then
		warn(`[Syscore] Cannot add {module.Name} after Syscore has started.`)
		return
	end

	addModule(module)
end

--[=[
	Add a table of modules to be initialized.

	```lua
	local Syscore = require(path.to.Syscore)
	local modules = {
		require(path.to.module1),
		require(path.to.module2),
		require(path.to.module3),
	}

	Syscore:AddTableOfModules(modules)
	```
]=]
function Syscore:AddTableOfModules(modules: { ModuleScript })
	if type(modules) ~= "table" then
		error(`[Syscore] {modules} is not a table.`)
	end

	if isInitialized then
		warn(`[Syscore] Cannot add {#modules} after Syscore has started.`)
		return
	end

	for _, systemModule in modules do
		addModule(systemModule)
	end
end

--[=[
	Initializes all modules based on their priority.
	Returns a table of errors that occured during initialization.

	```lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Syscore = require(path.to.Syscore)
	Syscore:AddFolderOfModules(ReplicatedStorage.ModulesFolder)
	Syscore:Start()
	```
]=]
function Syscore:Start(): { [string]: { { sysModule: Syscore, response: string } } }
	local runtimeStart = os.clock()

	prioritySortAddedModules()

	initializeSyscore(INIT_FUNCTION_NAME)

	for _, methodErrorGroup in errors do
		if #methodErrorGroup > 0 then
			for methodName, errorMessage in methodErrorGroup do
				warn(`[Syscore] {errorMessage.sysModule.Name}:{methodName} failed to initialize: {errorMessage.response}`)
			end
		end
	end

	if Syscore.ShowLoadOrder then
		local loadTime = string.format("%.6f", os.clock() - runtimeStart)
		warn(`[Syscore] {RunService:IsClient() and "Client" or "Server"} Modules loaded in {loadTime} seconds`)
	end

	isInitialized = true

	return errors
end

return Syscore

local RunService = game:GetService("RunService")

local INIT_FUNCTION_NAME = "Init"
local METHOD_TIMEOUT_SECONDS = 5

export type Syscore = {
	Icon: string?,
	Name: string,
	Priority: number,
	[any]: any,
}

local addedModules: { { system: Syscore, failedOnce: boolean } } = {}
local errors: { [string]: { { system: Syscore, response: string } } } = {}

--[=[
    @class Syscore

    - Wally Package: [Syscore](https://wally.run/package/naxious)

    Syscore is a module that allows you to easily manage the initialization of your modules in a specific order.
    This is useful for when you have modules that depend on each other and need to be initialized in a specific order.
    You can enable/disable debug mode to see the load order of your modules.
]=]

local Syscore = {}
Syscore.ShowLoadOrder = true
Syscore.RuntimeStart = 0

local function prioritySortAddedModules()
	table.sort(addedModules, function(a, b)
		return a.system.Priority < b.system.Priority
	end)

	if Syscore.ShowLoadOrder then
		warn(`[Syscore] {RunService:IsServer() and "Server" or "Client"} load order:`)
		for loadOrder, module in addedModules do
			local iconString = module.system.Icon and `{module.system.Icon} ` or "🔴"
			warn(`{loadOrder} - [{iconString}{module.system.Name}] :: {module.system.Priority}`)
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
					if typeof(data.system[methodName]) == "function" then
						data.system[methodName](data.system)
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
						`[Syscore] Module {data.system.Name}:{methodName} took more than {METHOD_TIMEOUT_SECONDS} seconds to initialize.`
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
			table.insert(errors[methodName], { system = data.system, response = errorMessage })
			warn(
				`[Syscore] Module {data.system.Name}:{methodName} failed to initialize: {errorMessage}\n{debug.traceback()}`
			)
		end
	end
end

local function ModuleWithSameNameExists(module: ModuleScript)
	for _, data in addedModules do
		if data.system.Name == module.Name  or data.system.Name == module:GetFullName() then
			warn(`[Syscore] {data.system.Name} is already in the systems list.`)
			return true
		end
	end
	
	return false
end

local function AddSystem(module: ModuleScript)
	if Syscore.RuntimeStart > 0 then
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

		table.insert(addedModules, { system = newModule, failedOnce = false, module = module })
	end)

	if not success then
		warn(`[Syscore] Failed to add "{module.Name}" ModuleScript: {errorMessage}\n{debug.traceback()}`)
	end
end

--[=[
	Add a folder that contains children that are systems to be initialized.
	Note that modules without a priority are processed last.

	@param folder Folder should contain children that are modules.
]=]
function Syscore:AddFolderOfModules(folder: Folder)
    assert(folder and folder:IsA("Folder"), `[Syscore] {folder.Name} is not a folder.`)

	if Syscore.RuntimeStart > 0 then
		warn(`[Syscore] Cannot add {folder.Name} after Syscore has started.`)
		return
	end

	for _, module in folder:GetChildren() do
		AddSystem(module)
	end
end

--[=[
    Add a module to be initialized.
    Note that modules without a priority are processed last.

    @param module Module to be initialized.
]=]
function Syscore:AddModule(module: ModuleScript)
    assert(module and module:IsA("ModuleScript"), `[Syscore] {module.Name} is not a ModuleScript.`)

    if Syscore.RuntimeStart > 0 then
        warn(`[Syscore] Cannot add {module.Name} after Syscore has started.`)
        return
    end

    AddSystem(module)
end

--[=[
	Add a table of systems to be initialized.
	Note that systems without a priority are processed last.

	@param systems Table of modules.
]=]
function Syscore:AddTableOfModules(systems: { ModuleScript })
    if type(systems) ~= "table" then
        error(`[Syscore] {systems} is not a table.`)
    end

	if Syscore.RuntimeStart > 0 then
		warn(`[Syscore] Cannot add {#systems} after Syscore has started.`)
		return
	end

	for _, systemModule in systems do
		AddSystem(systemModule)
	end
end

--[=[
	Call only after you've added any folders containing modules that you wish to become systems.

	@return table errors can return a table of errors thrown during initialization.
]=]
function Syscore:Start()
	Syscore.RuntimeStart = os.clock()

	prioritySortAddedModules()

	initializeSyscore(INIT_FUNCTION_NAME)

	for _, methodErrorGroup in errors do
		if #methodErrorGroup > 0 then
			for methodName, errorMessage in methodErrorGroup do
				warn(`[Syscore] {errorMessage.system.Name}:{methodName} failed to initialize: {errorMessage.response}`)
			end
		end
	end

	if Syscore.ShowLoadOrder then
		local loadTime = string.format("%.6f", os.clock() - Syscore.RuntimeStart)
		warn(`[Syscore] {RunService:IsClient() and "Client" or "Server"} Modules loaded in {loadTime} seconds`)
	end

	return errors
end

return Syscore

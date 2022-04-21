--[[
	READ ME
	This is a forked version of EasyNetwork, credits to the original creator:
	https://devforum.roblox.com/t/-/571258

	-- Server API

	Grid:BindFunctions(functions)
	Grid:BindEvents(events)

	Grid:FireClient(client, name, ...)
	Grid:FireAllClients(name, ...)
	Grid:FireOtherClients(ignoreclient, name, ...)
	Grid:FireOtherClientsWithinDistance(ignoreclient, distance, name, ...)
	Grid:FireAllClientsWithinDistance(position, distance, name, ...)

	Grid:InvokeClient(client, name, ...)  (same as below with timeout = 60)
	Grid:InvokeClientWithTimeout(timeout, client, name, ...)

	Grid:LogTraffic(duration)

	-- Internal overrideable methods, used for custom AllClients/OtherClients/WithinDistance selectors

	Grid:GetPlayers()
	Grid:GetPlayerPosition(player)

	-- Client API

	Grid:BindFunctions(functions)
	Grid:BindEvents(events)

	Grid:FireServer(name, ...)

	Grid:InvokeServer(name, ...)
	Grid:InvokeServerWithTimeout(timeout, name, ...)



	Notes:
	- The first return value of InvokeClient (but not InvokeServer) is bool success, which is false if the invocation timed out
	  or the handler errored.

	- InvokeServer will error if it times out or the handler errors

	- InvokeServer/InvokeClient do not return instantly on an error, but instead check for failure every 0.5 seconds. This is
	  because it is not possible to both instantly detect errors and have them be logged in the output with full stacktraces.
]]


--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")


--// Constants
local Grid = {}
local KickTemplate = "\n[Grid]\n%s"
local IsStudio = RunService:IsStudio()
local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()
local YieldBindable = Instance.new("BindableEvent")


--// Variables
local loggingGrid: {} = nil
local createdCommunications = false
local handlers = {
	Events = {},
	Functions = {},
	Deferred = {}
}
local counters = {
	Received = 0,
	Invoked = 0
}


--// Local functions

-- Gets all parameters from inserted arguments and transforms them into a single string.
local function GetParamString(...: any): string
	local packed = table.pack(...)
	local minimum  = math.min(10, packed.n)

	for index = 1, minimum do
		local value = packed[index]
		local valueType = typeof(packed[index])

		if valueType == "string" then
			packed[index] = string.format("%q[%d]", #value <= 18 and value or value:sub(1, 15) .. "...", #value)

		elseif valueType == "Instance" then
			local success, className = pcall(function()
				return value.ClassName
			end)

			packed[index] = success and string.format("%s<%s>", valueType, className) or valueType

		else
			packed[index] = valueType
		end
	end

	return table.concat(packed, ", ", 1, minimum ) .. (packed.n > minimum  and string.format(", ... (%d more)", packed.n - minimum ) or "")
end

--[[
	Adds a prefix to prints
]]
local function debugPrint(...)
	print("[Grid]:", ...)
end

--[[
	Adds a prefix to warnings
]]
local function debugWarn(...)
	warn("[Grid]:", ...)
end

--[[
	Throws an error without halting script
]]
local function debugError(...)
	for _, msg in pairs({...}) do
		task.spawn(error, "[GRID]: " .. tostring(msg), -1)
	end
end

--[[
	Waits for communication folders to exist or creates them.

 	YIELDS
]]
local function GetCommunications()
	if IsServer == true then
		-- Stops duplicates and destroys them
		if ReplicatedStorage:FindFirstChild("GridCommunications") and createdCommunications == false then
			ReplicatedStorage.GridCommunications:Destroy()
		elseif createdCommunications == true then
			return  ReplicatedStorage.GridCommunications
		end
		createdCommunications = true

		local CommunicationFolder = Instance.new("Folder")
		CommunicationFolder.Name = "GridCommunications"

		local FunctionsFolder = Instance.new("Folder")
		FunctionsFolder.Name = "Functions"
		local EventsFolder = Instance.new("Folder")
		EventsFolder.Name = "Events"
		local BindsFolder = Instance.new("Folder")
		BindsFolder.Name = "Binds"

		CommunicationFolder.Parent = ReplicatedStorage
		FunctionsFolder.Parent = CommunicationFolder
		EventsFolder.Parent = CommunicationFolder
		BindsFolder.Parent = CommunicationFolder

		return {
			["Functions"] = FunctionsFolder,
			["Events"] = EventsFolder,
			["Binds"] = BindsFolder
		}

	elseif IsClient == true then
		local CommunicationFolder = ReplicatedStorage:WaitForChild("GridCommunications")
		local FunctionsFolder = CommunicationFolder:WaitForChild("Functions")
		local EventsFolder = CommunicationFolder:WaitForChild("Events")
		local BindsFolder = CommunicationFolder:WaitForChild("Binds")

		return {
			["Functions"] = FunctionsFolder,
			["Events"] = EventsFolder,
			["Binds"] = BindsFolder
		}
	end
end


--// Functions

--[[
	Yields a thread.

 	YIELDS
]]
function YieldThread(): any?
	-- needed a way to first call coroutine.yield(), and then call YieldBindable.Event:Wait()
	-- but return what coroutine.yield() returned. This is kinda ugly, but the only other
	-- option was to create a temporary table to store the results, which I didn't want to do

	return (function(...)
		YieldBindable.Event:Wait()
		return ...
	end)(coroutine.yield())
end

-- Resumes a thread and passes any given arguments.
function ResumeThread(thread: thread, ...: any?)
	coroutine.resume(thread, ...)
	YieldBindable:Fire()
end

--[[
	Calls callback(...) in a separate thread and returns false if it errors or invoking client leaves the game.

	Fail state is only checked every 0.5 seconds, so don't expect errors to return immediately

 	YIELDS
]]
function SafeInvokeCallback(handler: table, ...: any): ...any
	local finished = false
	local callbackThread: thread = nil
	local invokeThread: thread = nil
	local result: table = nil

	-- Saves the results and resumes thread.
	local function finish(...: any)
		if finished == false then
			finished = true
			result = table.pack(...)

			if invokeThread then
				ResumeThread(invokeThread)
			end
		end
	end

	task.spawn(function(...: any)
		callbackThread = coroutine.running()
		finish(true, handler.Callback(...))
	end, ...)

	if finished == false then
		local client = IsServer and (...)

		task.spawn(function()
			while finished == false and coroutine.status(callbackThread) ~= "dead" do
				if IsServer and client.Parent ~= Players then
					break
				end

				task.wait(0.5)
			end

			finish(false)
		end)
	end

	if finished == false then
		invokeThread = coroutine.running()
		YieldThread()
	end

	return unpack(result)
end

--[[
	Safely invokes to a client with a possible timeout

 	YIELDS
]]
function SafeInvoke(timeout: number?, handler: table, ...: any): (boolean, ...any?)
	local thread = coroutine.running()
	local finished = false
	local result: table = nil

	task.spawn(function(...: any)
		if IsServer == true then
			result = table.pack(
				pcall(handler.Remote.InvokeClient, handler.Remote, ...)
			)
		else
			result = table.pack(
				pcall(handler.Remote.InvokeServer, handler.Remote, ...)
			)
		end

		if finished == false then
			finished = true
			ResumeThread(thread)
		end
	end, ...)

	if typeof(timeout) == "number" then
		task.delay(timeout, function()
			if finished == false then
				finished = true
				ResumeThread(thread)
			end
		end)
	end

	YieldThread()

	if result and result[1] == true and result[2] == true then
		return true, unpack(result, 3)
	end

	return false
end

--[[
	Goes through all callbacks in the handler and runs them with the given argument.

 	YIELDS
]]
function SafeFireEvent(handler: table, ...: any)
	local callbacks: {(...any) -> ()} = handler.Callbacks
	local index = #callbacks

	while index > 0 do
		local running = true

		task.spawn(function(...:any)
			while running == true and index > 0 do
				local callback = callbacks[index]
				index -= 1

				callback(...)
			end
		end, ...)

		running = false
	end
end


--[[
	Waits for the child with infinite yield.

	Regular WaitForChild had issues with order (RemoteEvents were going through before WaitForChild resumed)

 	YIELDS
]]
function WaitForChild(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)

	if not found then
		local thread = coroutine.running()
		local connection

		connection = parent.ChildAdded:Connect(function(child)
			if child.Name == name then
				connection:Disconnect()
				found = child
				ResumeThread(thread)
			end
		end)

		YieldThread()
	end

	return found
end

--[[
	Searches for the event handler and makes one if it doesn't exists yet.

 	YIELDS
]]
function GetEventHandler(name: string): {}
	-- Prevents creating the same handler
	local found = handlers.Events[name]
	if found then
		return found
	end

	local handler = {
		Name = name,
		Folder = GetCommunications().Events,

		Callbacks = {},
		IncomingQueueErrored = false
	}

	handlers.Events[name] = handler

	if IsServer == true then
		local remote = Instance.new("RemoteEvent")
		remote.Name = handler.Name
		remote.Parent = handler.Folder

		handler.Remote = remote
	else
		task.spawn(function()
			handler.Queue = {}

			local remote = WaitForChild(handler.Folder, handler.Name)
			handler.Remote = remote

			if #handler.Callbacks == 0 then
				handler.IncomingQueue = {}
			end

			remote.OnClientEvent:Connect(function(...)
				if handler.IncomingQueue then
					if #handler.IncomingQueue >= 2048 then
						if handler.IncomingQueueErrored == false then
							handler.IncomingQueueErrored = true
							debugWarn("Exhausted remote invocation queue for", remote:GetFullName())
							-- debugError(("Exhausted remove invocation queue for %s"):format(remote:GetFullName()))

							task.delay(1, function()
								handler.IncomingQueueErrored = false
							end)
						end

						if #handler.IncomingQueue >= 8172 then
							table.remove(handler.IncomingQueue, 1)
						end
					end

					counters.Received += 1
					table.insert(handler.IncomingQueue, table.pack(counters.Received, handler, ...))
					return
				end

				SafeFireEvent(handler, ...)
			end)

			if IsStudio == false then
				remote.Name = ""
			end

			for _, callback: () -> () in pairs(handler.Queue) do
				callback()
			end

			handler.Queue = nil
		end)
	end

	return handler
end

--[[
	Searches for the function handler and makes one if it doesn't exists yet.

 	YIELDS
]]
function GetFunctionHandler(name: string): {}
	-- Prevents creating the same handler
	local foundHandler = handlers.Functions[name]
	if foundHandler then
		return foundHandler
	end

	local handler = {
		Name = name,
		Folder = GetCommunications().Functions,

		Callback = nil,
		IncomingQueueErrored = nil
	}

	handlers.Functions[name] = handler

	if IsServer == true then
		local remote = Instance.new("RemoteFunction")
		remote.Name = handler.Name
		remote.Parent = handler.Folder

		handler.Remote = remote

	else
		task.spawn(function()
			handler.Queue = {}

			local remote = WaitForChild(handler.Folder, handler.Name)
			handler.Remote = remote

			handler.IncomingQueue = {}
			handler.OnClientInvoke = function(...)
				if not handler.Callback then
					if #handler.IncomingQueue >= 2048 then
						if not handler.IncomingQueueErrored then
							handler.IncomingQueueErrored = true
							
							debugError(("Exhausted remote invocation queue for &s"):format(remote:GetFullName()))

							task.delay(1, function()
								handler.IncomingQueueErrored = nil
							end)
						end

						if #handler.IncomingQueue >= 8172 then
							table.remove(handler.IncomingQueue, 1)
						end
					end

					counters.Received += 1
					local params = table.pack(counters.Received, handler, coroutine.running())

					table.insert(handler.IncomingQueue, params)
					YieldThread()
				end

				return SafeInvokeCallback(handler, ...)
			end

			if IsStudio == false then
				remote.Name = ""
			end

			for _, callback: () -> () in pairs(handler.Queue) do
				callback()
			end

			handler.Queue = nil
		end)
	end

	return handler
end

--[[
	Searches for the event handler and makes one if it doesn't exists yet.

 	YIELDS
]]
function AddToQueue(handler: table, callback: () -> (), shouldOutput: boolean)
	if handler.Remote then
		return callback()
	end

	handler.Queue[#handler.Queue + 1] = callback

	if shouldOutput == true then
		task.delay(5, function()
			if not handler.Remote then
				debugWarn(debug.traceback(("Infinite yield possible on '%s:WaitForChild(\"%s\")'"):format(handler.Folder:GetFullName(), handler.Name)))
			end
		end)
	end
end

--[[
	Runs all the deffered handlers.

 	YIELDS
]]
function ExecuteDeferredHandlers()
	local oldHandlers = handlers.Deferred
	local queue = {}

	handlers.Deferred = {}

	for handler in pairs(oldHandlers) do
		local incoming = handler.IncomingQueue

		handler.IncomingQueue = nil

		table.move(incoming, 1, #incoming, #queue + 1, queue)
	end

	table.sort(queue, function(a, b)
		return a[1] < b[1]
	end)

	for _, v in ipairs(queue) do
		local handler = v[2]

		if handler.Callbacks then
			SafeFireEvent(handler, unpack(v, 3))
		else
			ResumeThread(v[3])
		end
	end
end

--[[
	Part of the module shared with client and server
]]
local Middleware = {
	--[[
		Matches parameters
	]]
	MatchParams = function(event: string, paramTypes: table)
		paramTypes = { table.unpack(paramTypes) }
		local paramStart = 1

		for index: number, value: string in pairs(paramTypes) do
			local list = type(value) == "string" and string.split(value, "|") or value

			local dict = {}
			local typeListString = ""

			for _, parameter: string in pairs(list) do
				local typeString = parameter:gsub("^%s+", ""):gsub("%s+$", "")

				typeListString ..= (#typeListString > 0 and " or " or "") .. typeString
				dict[typeString:lower()] = true
			end

			dict._string = typeListString
			paramTypes[index] = dict
		end

		if IsServer == true then
			paramStart = 2
			table.insert(paramTypes, 1, false)
		end

		local function MatchParams(callback: () -> (), ...)
			local params = table.pack(...)

			if params.n > #paramTypes then
				if IsStudio == true then
					debugWarn(("Invalid number of parameters to %s"):format(event, #paramTypes - paramStart + 1, params.n - paramStart + 1))
				end
				return
			end

			for i = paramStart, #paramTypes do
				local argType = typeof(params[i])
				local argExpected = paramTypes[i]

				if not argExpected[argType:lower()] and not argExpected.any then
					if IsStudio then
						debugWarn(("Invalid parameter %d to %s (%s expected, got %s)"):format(i - paramStart + 1, event, argExpected._string, argType))
					end
					return
				end
			end

			return callback(...)
		end

		return MatchParams
	end
}

--[[
	Combines handler with a callback and logs it if logging exists
]]
function combineFunctions(handler, finalCallback: {()-> ()}|() -> (), ...:any?)
	local middleware = { ... }

	if typeof(finalCallback) == "table" then
		local info = finalCallback
		finalCallback = finalCallback[1]

		if info.MatchParams then
			table.insert(middleware, Middleware.MatchParams(handler.Name, info.MatchParams))
		end
	end

	local function GridHandler(...)
		if loggingGrid then
			local client = ...

			table.insert(loggingGrid[client][handler.Remote].dataIn, GetParamString(select(2, ...)))
		end

		local currentIndex = 1

		local function runMiddleware(index: number, ...)
			if index ~= currentIndex then
				return
			end

			currentIndex += 1

			if index <= #middleware then
				return middleware[index](
					function(...)
						return runMiddleware(index + 1, ...)
					end, ...
				)
			end

			return finalCallback(...)
		end

		return runMiddleware(1, ...)
	end

	return GridHandler
end

-- TODO: Figure out type arguments for binding events and functions
--[[
	Binds callbacks to event

 	YIELDS
]]
function Grid:BindEvents(pre: {[string]: () -> ()}?, callbacks: {[string]: () -> ()})
	if typeof(pre) == "table" then
		pre, callbacks = nil, pre
	end

	for name: string, callback: () -> () in pairs(callbacks) do
		local handler = GetEventHandler(name)
		if not handler then
			error(("[Grid]: Tried to bind callback to non-existing RemoteEvent %q"):format(name))
		end

		handler.Callbacks[#handler.Callbacks + 1] = combineFunctions(handler, callback, pre)

		if IsServer == true then
			handler.Remote.OnServerEvent:Connect(function(...)
				SafeFireEvent(handler, ...)
			end)
		else
			if handler.IncomingQueue then
				handlers.Deferred[handler] = true
			end
		end
	end

	ExecuteDeferredHandlers()
end

--[[
	Binds callbacks to function

 	YIELDS
]]
function Grid:BindFunctions(pre: table?, callbacks: {[string]: () -> ()})
	if typeof(pre) == "table" then
		pre, callbacks = nil, pre
	end

	for name: string, callback: () -> () in pairs(callbacks) do
		local handler = GetFunctionHandler(name)
		if not handler then
			error(("[Grid]: Tried to bind callback to non-existing RemoteFunction %q"):format(name))
		end

		if handler.Callback then
			error(("[Grid]: Tried to bind multiple callbacks to the same RemoteFunction (%s)"):format(handler.Remote:GetFullName()))
		end

		handler.Callback = combineFunctions(handler, callback, pre)

		if IsServer then
			handler.Remote.OnServerInvoke = function(...)
				return SafeInvokeCallback(handler, ...)
			end
		else
			if handler.IncomingQueue then
				handlers.Deferred[handler] = true
			end
		end
	end

	ExecuteDeferredHandlers()
end



if IsServer == true then
	function HandlerFireClient(handler, client, ...)
		if loggingGrid then
			table.insert(loggingGrid[client][handler.Remote].dataOut, GetParamString(...))
		end

		return handler.Remote:FireClient(client, ...)
	end

	--[[
		Returns all players
	]]
	function Grid:GetPlayers(): {Player}
		return Players:GetPlayers()
	end

	--[[
		Returns player's position, can be nil
	]]
	function Grid:GetPlayerPosition(player: Player): Vector3?
		return player and player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart.Position or nil
	end

	--[[
		Fires to a single client
	]]
	function Grid:FireClient(client: Player, event: string, ...: any)
		local handler = GetEventHandler(event)
		if not handler then
			error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
		end

		HandlerFireClient(handler, client, ...)
	end

	--[[
		Fires to every client in the server
	]]
	function Grid:FireAllClients(event: string, ...)
		local handler = GetEventHandler(event)
		if not handler then
			error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
		end

		for _, player: Player in pairs(self:GetPlayers()) do
			HandlerFireClient(handler, player, ...)
		end
	end

	--[[
		Fires to every client except given one
	]]
	function Grid:FireOtherClients(exceptClient: Player, event, ...)
		local handler = GetEventHandler(event)
		if not handler then
			error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
		end

		for _, player: Player in pairs(self:GetPlayers()) do
			if player ~= exceptClient then
				HandlerFireClient(handler, player, ...)
			end
		end
	end

	--[[
		Fires to every client with in a given radius from one client.

		Does not fire to client being checked from
	]]
	function Grid:FireOtherClientsWithinDistance(client: Player, maxDistance: number, event: string, ...)
		local handler = GetEventHandler(event)
		if not handler then
			error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
		end

		local clientPosition = self:GetPlayerPosition(client)
		if not clientPosition then
			return
		end

		for _, player: Player in pairs(self:GetPlayers()) do
			if player ~= client then
				local otherClientPosition = self:GetPlayerPosition(player)

				if otherClientPosition and (clientPosition - otherClientPosition).Magnitude <= maxDistance then
					HandlerFireClient(handler, player, ...)
				end
			end
		end
	end

	--[[
		Fires to every client with in the a radius from given position
	]]
	function Grid:FireAllClientsWithinDistance(position: Vector3, maxDistance: number, event: string, ...)
		local handler = GetEventHandler(event)
		if not handler then
			error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
		end

		for _, player: Player in pairs(self:GetPlayers()) do
			local playerPosition = self:GetPlayerPosition(player)

			if playerPosition and (position - playerPosition).Magnitude <= maxDistance then
				HandlerFireClient(handler, player, ...)
			end
		end
	end

	--[[
		Invokes client with with a custom timeout, returns false if it failed.

	 	YIELDS
	]]
	function Grid:InvokeClientWithTimeout(timeout: number, client: Player, event: string, ...): (boolean, any?)
		local handler = GetEventHandler(event)
		if not handler then
			error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
		end

		return SafeInvoke(timeout, handler, client, ...)
	end

	--[[
		Invokes client with a 60 seconds timeout

	 	YIELDS
	]]
	function Grid:InvokeClient(client: Player, event: string)
		return self:InvokeClientWithTimeout(60, client, event)
	end

	--[[
		Logs grid traffic with possible output but doesn't yield
	]]
	function Grid:LogTraffic(duration: number, shouldOutput: boolean)
		task.spawn(self.LogTrafficAsync, self, duration, shouldOutput)
	end

	--[[
		Logs grid traffic with possible output

	 	YIELDS
	]]
	function Grid:LogTrafficAsync(duration: number, shouldOutput: boolean)
		--[[
			Debug output
		]]
		local function output(...)
			if shouldOutput == true then
				debugWarn(...)
			end
		end

		if loggingGrid then return end
		output("Logging Grid Traffic...")

		loggingGrid = setmetatable({}, { __index = function(t, i)
			t[i] = setmetatable({}, { __index = function(t, i) t[i] = { dataIn = {}, dataOut = {} } return t[i] end })
			return t[i]
		end})

		local start = os.clock()
		task.wait(duration)
		local effDur = os.clock() - start

		local clientTraffic = loggingGrid
		loggingGrid = nil

		for player: Player, remotes in pairs(clientTraffic) do
			local totalReceived = 0
			local totalSent = 0

			for _, data in pairs(remotes) do
				totalReceived += #data.dataIn
				totalSent += #data.dataOut
			end

			output(string.format("Player '%s', total received/sent: %d/%d", player.Name, totalReceived, totalSent))

			for remote,data in pairs(remotes) do
				-- Incoming

				local listIn = data.dataIn
				if #listIn > 0 then
					output(string.format("   %s %s: %d (%.2f/s)", "FireServer", remote.Name, #listIn, #listIn / effDur))

					local count = math.min(#listIn, 3)
					for i = 1, count do
						local index = math.floor(1 + (i - 1) / math.max(1, count - 1) * (#listIn - 1) + 0.5)
						output(string.format("      %d: %s", index, listIn[index]))
					end
				end

				-- Outgoing

				local listOut = data.dataOut
				if #listOut > 0 then
					output(string.format("   %s %s: %d (%.2f/s)", "FireClient", remote.Name, #listOut, #listOut / effDur))

					local count = math.min(#listOut, 3)
					for i = 1, count do
						local index = math.floor(1 + (i - 1) / math.max(1, count - 1) * (#listOut - 1) + 0.5)
						output(string.format("      %d: %s", index, listOut[index]))
					end
				end
			end
		end
	end

else
	local communications = GetCommunications()
	communications.Binds.ChildAdded:Connect(function(child)
		print("Do binds stuff")
	end)

	communications.Events.ChildAdded:Connect(function(child)
		GetEventHandler(child.Name)
	end)
	for _,child in pairs(communications.Events:GetChildren()) do
		GetEventHandler(child.Name)
	end

	communications.Functions.ChildAdded:Connect(function(child)
		GetFunctionHandler(child.Name)
	end)
	for _,child in ipairs(communications.Functions:GetChildren()) do
		GetFunctionHandler(child.Name)
	end

	--[[
		Fires to server
	]]
	function Grid:FireServer(event: string, ...)
		local handler = GetEventHandler(event)
		if not handler then
			error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
		end

		if handler.Remote then
			handler.Remote:FireServer(...)
		else
			local params = table.pack(...)

			AddToQueue(handler, function()
				handler.Remote:FireServer(unpack(params))
			end, true)
		end
	end

	--[[
		Invoke server with custom timeout

	 	YIELDS
	]]
	function Grid:InvokeServerWithTimeout(timeout: number, event: string, ...): ...any
		local handler = GetFunctionHandler(event)
		if not handler then
			error(("[Grid]: '%s' is not a valid RemoteFunction"):format(event))
		end

		if not handler.Remote then
			-- Code below will break if the callback passed to AddToQueue is called
			-- before the function returns. This should never happen unless somebody
			-- changed how AddToQueue works.
			local thread = coroutine.running()

			AddToQueue(handler, function()
				ResumeThread(thread)
			end, true)

			YieldThread()
		end

		local result = table.pack(SafeInvoke(timeout, handler, ...))
		assert(result[1] == true, "InvokeServer error")

		return unpack(result, 2)
	end

	--[[
		Invokes server without timeout
	]]
	function Grid:InvokeServer(event: string, ...): ...any
		return self:InvokeServerWithTimeout(nil, event, ...)
	end
end


--[[ Value packing extension ]]--

do
	local SendingCache = setmetatable({}, { __index = function(t, i) t[i] = {} return t[i] end, __mode = "k" })
	local ReceivingCache = setmetatable({}, { __index = function(t, i) t[i] = {} return t[i] end, __mode = "k" })
	local MaxStringLength = 64
	local CacheSize = 32 -- must be under 256, keeping it low because adding a new entry goes through the entire cache

	local ValidTypes = {
		["number"] = true,
		["string"] = true,
		["boolean"] = true,
		["nil"] = true,

		["Vector2"] = true,
		["Vector3"] = true,
		["CFrame"] = true,

		["Color3"] = true,
		["BrickColor"] = true,

		["Udim2"] = true,
		["Udim"] = true
	}

	--[[
		Makes value one byte and adds it to cache if it was not added
	]]
	local function addEntry(value: any, client: Player)
		local valueType = typeof(value)

		if not ValidTypes[valueType] then
			error(string.format("[Grid]: Invalid value passed to Grid:Pack (values of type %s are not supported)", valueType))
		end

		if valueType == "boolean" or valueType == "nil" or value == "" then
			return value -- already one-byte
		elseif valueType == "string" and #value > MaxStringLength then
			return "\0" .. value
		end

		local cache = SendingCache[client]
		local info = cache[value]

		if not info then
			if #cache < CacheSize then
				local index = #cache + 1
				info = { char = string.char(index), value = value, last = 0 }

				cache[index] = info
				cache[value] = info
			else
				for i,other in ipairs(cache) do
					if not info or other.last < info.last then
						info = other
					end
				end

				cache[info.value] = nil
				cache[value] = info

				info.value = value
			end

			if IsServer == true then
				Grid:FireClient(client, "SetPackedValue", info.char, info.value)
			else
				Grid:FireServer("SetPackedValue", info.char, info.value)
			end
		end

		info.last = os.clock()

		return info.char
	end

	--[[
		Gets an entry from the receiving cache
	]]
	local function getEntry(value: any, client: Player)
		local valueType = typeof(value)
		if valueType ~= "string" or value == "" then
			return value
		end

		local index = string.byte(value, 1)
		if index == 0 then
			return string.sub(value, 2)
		end

		return ReceivingCache[client][index]
	end

	if IsServer == true then

		--[[
			Packs a value and adds it to the cache
		]]
		function Grid:Pack(value: any, client: Player)
			assert(typeof(client) == "Instance" and client:IsA("Player"), "[Grid]: Client is not a player")
			return addEntry(value, client)
		end

		--[[
			Unpacks the value
		]]
		function Grid:Unpack(value: any, client: Player)
			assert(typeof(client) == "Instance" and client:IsA("Player"), "[Grid]: Client is not a player")
			return getEntry(value, client)
		end

		Grid:BindEvents({
			SetPackedValue = function(client: Player, char: string?, value: any)
				if typeof(char) ~= "string" or #char ~= 1 then
					return client:Kick(KickTemplate:format("Expected string, got " .. tostring(char)))
				end

				local index = string.byte(char)
				if index < 1 or index > CacheSize then
					return client:Kick(KickTemplate:format("index too small or too big for cache"))
				end

				local valueType = typeof(value)
				if not ValidTypes[valueType] or valueType == "string" and #value > MaxStringLength then
					return client:Kick(KickTemplate:format("Non valid value type"))
				end

				ReceivingCache[client][index] = value
			end
		})
	else
		function Grid:Pack(value)
			return addEntry(value, "Server")
		end

		function Grid:Unpack(value)
			return getEntry(value, "Server")
		end

		Grid:BindEvents({
			SetPackedValue = function(char, value)
				ReceivingCache.Server[string.byte(char)] = value
			end
		})
	end
end

--[[ Reference extension ]]--

do
	local ReferenceTypes = {
		["Character"] = {},
		["CharacterPart"] = {}
	}

	local References = {}
	local Objects = {}

	for index: string, _ in pairs(ReferenceTypes) do
		References[index] = {}
		Objects[index] = {}
	end

	--[[
		Adds a reference for client
	]]
	function Grid:AddReference(key: string, referenceType: string, ...)
		local referenceInfo = ReferenceTypes[referenceType]
		assert(referenceInfo, "Invalid Reference Type " .. tostring(referenceType))

 		local referenceData = {
			Type = referenceType,
			Reference = key,
			Objects = {...},
			Aliases = {}
		}

		References[referenceType][referenceData.Reference] = referenceData

		local last = Objects[referenceType]
		for _, obj in ipairs(referenceData.Objects) do
			local list = last[obj] or {}
			last[obj] = list
			last = list
		end

		last.__Data = referenceData
	end

	--[[
		Add an alias to a existing reference
	]]
	function Grid:AddReferenceAlias(key: string, referenceType: string, ...)
		local referenceInfo = ReferenceTypes[referenceType]
		assert(referenceInfo, "Invalid Reference Type " .. tostring(referenceType))

		local referenceData = References[referenceType][key]
		if not referenceData then
			debugWarn(("Tried to add an alias to a non-existing reference %s[%s]"):format(tostring(referenceType), tostring(key)))
			return
		end

		local objects = {...}
		referenceData.Aliases[#referenceData.Aliases + 1] = objects

		local last = Objects[referenceType]
		for _,obj in ipairs(objects) do
			local list = last[obj] or {}
			last[obj] = list
			last = list
		end

		last.__Data = referenceData
	end

	--[[
		Removes the reference
	]]
	function Grid:RemoveReference(key: string, referenceType: string)
		local referenceInfo = ReferenceTypes[referenceType]
		assert(referenceInfo, "Invalid Reference Type " .. tostring(referenceType))

		local referenceData = References[referenceType][key]
		if not referenceData then
			debugWarn(("Tried to remove a non-existing reference %s[%s]"):format(tostring(referenceType), tostring(key)))
			return
		end

		References[referenceType][referenceData.Reference] = nil

		-- Removes the data from objects
		local function remove(parent: {}, objects: {}, index: number)
			if index <= #objects then
				local foundKey = objects[index]
				local child = parent[foundKey]

				remove(child, objects, index + 1)

				if next(child) == nil then
					parent[key] = nil
				end
			elseif parent.__Data == referenceData then
				parent.__Data = nil
			end
		end

		local objects = Objects[referenceData.Type]
		remove(objects, referenceData.Objects, 1)

		for _,alias in ipairs(referenceData.Aliases) do
			remove(objects, alias, 1)
		end
	end

	--[[
		Gets object from reference
	]]
	function Grid:GetObject(reference, referenceType): ...any?
		assert(ReferenceTypes[referenceType], "Invalid Reference Type " .. tostring(referenceType))

		local refData = References[referenceType][reference]
		if not refData then
			return nil
		end

		return unpack(refData.Objects)
	end

	--[[
		Gets reference from objects
	]]
	function Grid:GetReference(...): any?
		local objects = {...}

		local referenceType = table.remove(objects)
		assert(ReferenceTypes[referenceType], "Invalid Reference Type " .. tostring(referenceType))

		local last = Objects[referenceType]
		for i,v in ipairs(objects) do
			last = last[v]

			if not last then
				break
			end
		end

		local refData = last and last.__Data
		return refData and refData.Reference or nil
	end
end



return Grid

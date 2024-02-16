local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(script.Parent:WaitForChild("Types"))

local Shared = {
	Prefix = "[Grid]",
	IsStudio = RunService:IsStudio(),
	IsServer = RunService:IsServer(),
	YieldBindable = Instance.new("BindableEvent"),
	CreatedCommunications = false,

	Handlers = {
		Events = {},
		Functions = {},
		Binds = {},
		Deferred = {},
	},
	Counters = {
		Received = 0,
		Invoked = 0,
	},

	LoggingActive = false,
	Logs = setmetatable({}, {
		__index = function(logTable, index)
			logTable[index] = setmetatable({}, {
				__index = function(inLog, new)
					inLog[new] = { In = {}, Out = {} }
					return inLog[new]
				end,
			})
			return logTable[index]
		end,
	}),
}

--[=[
	Adds the prefix to print

	@param ... any -- The message you want to print
]=]
function Shared.DebugPrint(...: any)
	print(Shared.Prefix, ...)
end

--[=[
	Adds the prefix to warn

	@param ... any -- The message you want to print
]=]
function Shared.DebugWarn(...: any)
	warn(Shared.Prefix, ...)
end

--[=[
	Turns paramameters into a string

	@param ... any

	@return string -- Paramameters formatted into a string
]=]
function Shared.GetParametersString(...: any): string
	local packed = table.pack(...)
	local minimum = math.min(10, packed.n)

	for index = 1, minimum do
		local value = packed[index]
		local valueType = typeof(packed[index])

		if valueType == "string" then
			packed[index] = `{tostring(#value <= 18 and value or value:sub(1, 15)) .. "..."}[{tostring(#value)}]`
		elseif valueType == "Instance" then
			local success, className = pcall(function()
				return value.ClassName
			end)

			packed[index] = success and `{valueType}<{className}>` or valueType
		else
			packed[index] = valueType
		end
	end

	return table.concat(packed, ", ", 1, minimum) .. (packed.n > minimum and `, .. ({packed.n - minimum} more)` or "")
end

--[=[
	Waits for communication folders to exist or creates them.

	@yields

	@return Types.Communications -- The communication folders
]=]
function Shared.GetCommunications(): Types.Communications
	if Shared.IsServer == true and Shared.CreatedCommunications == false then
		-- Stops duplicates and destroys them
		if ReplicatedStorage:FindFirstChild("GridCommunications") and Shared.CreatedCommunications == false then
			ReplicatedStorage.GridCommunications:Destroy()
		elseif Shared.CreatedCommunications == true then
			return ReplicatedStorage.GridCommunications
		end
		Shared.CreatedCommunications = true

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

		Shared.DebugPrint("Created communications folders")
	end

	local CommunicationFolder = ReplicatedStorage:WaitForChild("GridCommunications")
	local FunctionsFolder = CommunicationFolder:WaitForChild("Functions")
	local EventsFolder = CommunicationFolder:WaitForChild("Events")
	local BindsFolder = CommunicationFolder:WaitForChild("Binds")

	return {
		Functions = FunctionsFolder,
		Events = EventsFolder,
		Binds = BindsFolder,
	}
end

--[=[
	Yields the current thread

	@yields

	@return any -- Returns what yield returned

-- TODO: Improve thread handling
]=]
function Shared.YieldThread(): any
	-- needed a way to first call coroutine.yield(), and then call YieldBindable.Event:Wait()
	-- but return what coroutine.yield() returned. This is kinda ugly, but the only other
	-- option was to create a temporary table to store the results, which I didn't want to do

	return (function(...)
		Shared.YieldBindable.Event:Wait()
		return ...
	end)(coroutine.yield())
end

--[=[
	Resumes the current thread

	@param thread Thread -- The thread you want to resume
	@param ... any -- What you want to return to the thread
-- TODO: Improve thread handling
]=]
function Shared.ResumeThread(thread: thread, ...: any?)
	coroutine.resume(thread, ...)
	Shared.YieldBindable:Fire()
end

--[=[
	Calls callback(...) in a separate thread and returns false if it errors or invoking client leaves the game.

	Fail state is only checked every 0.5 seconds, so don't expect errors to return immediately

	@param handler Types.FunctionHandler
	@param ... any -- The arguments you want to invoke with

	@yields
	@error "Any" -- The client can leave while invoke

	@return ...any -- The response from invoke
]=]
function Shared.SafeInvokeCallback(handler: Types.FunctionHandler, ...: any): ...any
	local finished = false
	local callbackThread: thread = nil
	local invokeThread: thread = nil
	local result: { any } = nil

	-- Saves the results and resumes thread.
	local function finish(...: any)
		if finished == false then
			finished = true
			result = table.pack(...)

			if invokeThread then
				Shared.ResumeThread(invokeThread)
			end
		end
	end

	task.spawn(function(...: any)
		callbackThread = coroutine.running()
		finish(true, handler.Callback(...))
	end, ...)

	if finished == false then
		local client = Shared.IsServer and (...)

		task.spawn(function()
			while finished == false and coroutine.status(callbackThread) ~= "dead" do
				if Shared.IsServer and client.Parent ~= Players then
					break
				end

				task.wait(0.5)
			end

			finish(false)
		end)
	end

	if finished == false then
		invokeThread = coroutine.running()
		Shared.YieldThread()
	end

	return unpack(result)
end

--[=[
	Goes through all callbacks in the handler and runs them with the given arguments.

	@param handler Types.EventHandler
	@param ... any -- The arguments you want to fire with

	@yields
]=]
function Shared.SafeFireEvent(handler: Types.EventHandler, ...: any)
	local callbacks: { (...any) -> () } = handler.Callbacks
	local index = #callbacks

	while index > 0 do
		local running = true

		task.spawn(function(...: any)
			while running == true and index > 0 do
				local callback = callbacks[index]
				index -= 1

				callback(...)
			end
		end, ...)

		running = false
	end
end

--[=[
	Waits for the child with infinite yield.

	Regular WaitForChild had issues with order (RemoteEvents were going through before WaitForChild resumed)

	@param parent Instance -- The instance the child should be parented to
	@param name string -- The name of the child

	@yields
]=]
function Shared.WaitForChild(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)

	if not found then
		local thread = coroutine.running()
		local connection

		connection = parent.ChildAdded:Connect(function(child)
			if child.Name == name then
				connection:Disconnect()
				found = child
				Shared.ResumeThread(thread)
			end
		end)

		Shared.YieldThread()
	end

	return found
end

--[=[
	Searches for the event handler and makes one if it doesn't exists yet.

	@param name string -- The name of the event handler.

	@returns Types.EventHandler

	@yields
]=]
function Shared.GetEventHandler(name: string): Types.EventHandler
	-- Prevents creating the same handler
	local found = Shared.Handlers.Events[name]
	if found then
		return found
	end

	local handler = {
		Name = name,
		Folder = Shared.GetCommunications().Events,

		Callbacks = {},
		IncomingQueueErrored = false,
	} :: Types.EventHandler

	Shared.Handlers.Events[name] = handler

	if Shared.IsServer == true then
		local remote = Instance.new("RemoteEvent")
		remote.Name = handler.Name
		remote.Parent = handler.Folder

		handler.Remote = remote
	else
		task.spawn(function()
			handler.Queue = {}

			local remote = Shared.WaitForChild(handler.Folder, handler.Name)
			handler.Remote = remote

			if #handler.Callbacks == 0 then
				handler.IncomingQueue = {}
			end

			remote.OnClientEvent:Connect(function(...)
				if handler.IncomingQueue then
					if #handler.IncomingQueue >= 2048 then
						if handler.IncomingQueueErrored == false then
							handler.IncomingQueueErrored = true
							Shared.DebugWarn(`Exhausted remote invocation queue for {remote:GetFullName()}`)

							task.delay(1, function()
								handler.IncomingQueueErrored = false
							end)
						end

						if #handler.IncomingQueue >= 8172 then
							table.remove(handler.IncomingQueue, 1)
						end
					end

					Shared.Counters.Received += 1
					table.insert(handler.IncomingQueue, table.pack(Shared.Counters.Received, handler, ...))
					return
				end

				Shared.SafeFireEvent(handler, ...)
			end)

			if Shared.IsStudio == false then
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

--[=[
	Searches for the function handler and makes one if it doesn't exists yet.

	@param name string -- The name of the function handler.

	@returns Types.FunctionHandler

	@yields
]=]
function Shared.GetFunctionHandler(name: string): Types.FunctionHandler
	-- Prevents creating the same handler
	local foundHandler = Shared.Handlers.Functions[name]
	if foundHandler then
		return foundHandler
	end

	local handler = {
		Name = name,
		Folder = Shared.GetCommunications().Functions,

		Callback = nil,
		IncomingQueueErrored = nil,
	} :: Types.FunctionHandler

	Shared.Handlers.Functions[name] = handler

	if Shared.IsServer == true then
		local remote = Instance.new("RemoteFunction")
		remote.Name = handler.Name
		remote.Parent = handler.Folder

		handler.Remote = remote
	else
		task.spawn(function()
			handler.Queue = {}

			local remote = Shared.WaitForChild(handler.Folder, handler.Name)
			handler.Remote = remote

			handler.IncomingQueue = {}
			handler.OnClientInvoke = function(...)
				if not handler.Callback then
					if #handler.IncomingQueue >= 2048 then
						if not handler.IncomingQueueErrored then
							handler.IncomingQueueErrored = true

							Shared.DebugWarn(`Exhausted remote invocation queue for {remote:GetFullName()}`)

							task.delay(1, function()
								handler.IncomingQueueErrored = nil
							end)
						end

						if #handler.IncomingQueue >= 8172 then
							table.remove(handler.IncomingQueue, 1)
						end
					end

					Shared.Counters.Received += 1
					local params = table.pack(Shared.Counters.Received, handler, coroutine.running())

					table.insert(handler.IncomingQueue, params)
					Shared.YieldThread()
				end

				return Shared.SafeInvokeCallback(handler, ...)
			end

			if Shared.IsStudio == false then
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

--[=[
	Runs all the deffered handlers.

	@yields
]=]
function Shared.ExecuteDeferredHandlers()
	local oldHandlers = Shared.Handlers.Deferred
	local queue = {}

	Shared.Handlers.Deferred = {}

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
			Shared.SafeFireEvent(handler, unpack(v, 3))
		else
			Shared.ResumeThread(v[3])
		end
	end
end

--[=[
	Match parameters

	@param event string -- The event
	@param paramTypes {any} -- The types to check for
]=]
function Shared.MatchParams(event: string, paramTypes: { any })
	paramTypes = { table.unpack(paramTypes) }
	local paramStart = 1

	for index: number, value: string in paramTypes do
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

	if Shared.IsServer == true then
		paramStart = 2
		table.insert(paramTypes, 1, false)
	end

	local function MatchParams(callback: () -> (), ...)
		local params = table.pack(...)

		if params.n > #paramTypes then
			if Shared.IsStudio == true then
				Shared.DebugWarn(
					`Invalid number of parameters to {event} ({#paramTypes - paramStart + 1} expected, got {params.n - paramStart + 1})`
				)
			end
			return
		end

		for i = paramStart, #paramTypes do
			local argType = typeof(params[i])
			local argExpected = paramTypes[i]

			if not argExpected[argType:lower()] and not argExpected.any then
				if Shared.IsStudio then
					Shared.DebugWarn(
						`Invalid parameter {tostring(i - paramStart + 1)} to {event} ({argExpected._string} got {argType})`
					)
				end
				return
			end
		end

		return callback(...)
	end

	return MatchParams
end

--[=[
	Combines handler with a callback and logs it if logging exists

	@param handler Types.EventHandler
	@param finalCallback: { (...any) -> () } | (...any) -> ()
	@param ... any?

	@returns (...any) -> ()
]=]
function Shared.CombineFunctions(
	handler: Types.EventHandler,
	finalCallback: { (...any) -> () } | (...any) -> (),
	...: any?
): (...any) -> ()
	local middleware = { ... }
	local callback: (...any) -> ()

	if typeof(finalCallback) == "table" then
		local info = finalCallback
		callback = finalCallback[1]

		if info.MatchParams then
			table.insert(middleware, Shared.MatchParams(handler.Name, info.MatchParams))
		end
	else
		callback = finalCallback
	end

	local function GridHandler(...)
		if Shared.LoggingActive then
			local client = ...

			table.insert(Shared.Logs[client][handler.Remote].In, Shared.GetParametersString(select(2, ...)))
		end

		local currentIndex = 1

		local function runMiddleware(index: number, ...)
			if index ~= currentIndex then
				return
			end

			currentIndex += 1

			if index <= #middleware then
				return middleware[index](function(...)
					return runMiddleware(index + 1, ...)
				end, ...)
			end

			return callback(...)
		end

		return runMiddleware(1, ...)
	end

	return GridHandler
end

--[=[
	Safely invokes a with a possible timeout

	@param timeout number?
	@param handler Types.FunctionHandler
	@param ... any -- The arguments you want to push through to client

	@yields

	@return (boolean, ...any)
]=]
function Shared.SafeInvoke(timeout: number?, handler: Types.FunctionHandler, ...: any): (boolean, ...any?)
	local thread = coroutine.running()
	local finished = false
	local result: { any } = nil

	task.spawn(function(...: any)
		if Shared.IsServer == true then
			result = table.pack(pcall(handler.Remote.InvokeClient, handler.Remote, ...))
		else
			result = table.pack(pcall(handler.Remote.InvokeServer, handler.Remote, ...))
		end

		if finished == false then
			finished = true
			Shared.ResumeThread(thread)
		end
	end, ...)

	if typeof(timeout) == "number" then
		task.delay(timeout, function()
			if finished == false then
				finished = true
				Shared.ResumeThread(thread)
			end
		end)
	end

	Shared.YieldThread()

	if result and result[1] == true and result[2] == true then
		return true, unpack(result, 3)
	end

	return false
end

return Shared

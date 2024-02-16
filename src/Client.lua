--[[
    Client side of Grid
]]

local Types = require(script.Parent:WaitForChild("Types"))
local Shared = require(script.Parent:WaitForChild("Shared"))

local Client = {}

--[=[
	Searches for the event handler and makes one if it doesn't exists yet.

    @param handler Types.EventHandler -- The handler
    @param callback () -> () -- The callback to add
    @param shouldOutput boolean -- Should debug be enabled?

    @return any

	@yields
]=]
function AddToQueue(handler: Types.EventHandler, callback: () -> (), shouldOutput: boolean): any
	if handler.Remote then
		return callback()
	end

	handler.Queue[#handler.Queue + 1] = callback

	if shouldOutput == true then
		task.delay(5, function()
			if not handler.Remote then
				Shared.DebugWarn(
					debug.traceback(
						`Infinite yield possible on '{handler.Folder:GetFullName()}:WaitForChild("{handler.Name}")'`
					)
				)
			end
		end)
	end

	return
end

local communications = Shared.GetCommunications()
-- TODO: Add binds support
-- communications.Binds.ChildAdded:Connect(function(child)
-- 	print("Do binds stuff")
-- end)

communications.Events.ChildAdded:Connect(function(child)
	Shared.GetEventHandler(child.Name)
end)
for _, child in pairs(communications.Events:GetChildren()) do
	Shared.GetEventHandler(child.Name)
end

communications.Functions.ChildAdded:Connect(function(child)
	Shared.GetFunctionHandler(child.Name)
end)
for _, child in ipairs(communications.Functions:GetChildren()) do
	Shared.GetFunctionHandler(child.Name)
end

--[[
		Fires to server
	]]
function Client:FireServer(event: string, ...)
	local handler = Shared.GetEventHandler(event)
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
function Client:InvokeServerWithTimeout(timeout: number, event: string, ...): ...any
	local handler = Shared.GetFunctionHandler(event)
	if not handler then
		error(("[Grid]: '%s' is not a valid RemoteFunction"):format(event))
	end

	if not handler.Remote then
		-- Code below will break if the callback passed to AddToQueue is called
		-- before the function returns. This should never happen unless somebody
		-- changed how AddToQueue works.
		local thread = coroutine.running()

		AddToQueue(handler, function()
			Shared.ResumeThread(thread)
		end, true)

		Shared.YieldThread()
	end

	local result = table.pack(Shared.SafeInvoke(timeout, handler, ...))
	assert(result[1] == true, "InvokeServer error")

	return unpack(result, 2)
end

--[[
		Invokes server without timeout
	]]
function Client:InvokeServer(event: string, ...): ...any
	return self:InvokeServerWithTimeout(nil, event, ...)
end

return Client

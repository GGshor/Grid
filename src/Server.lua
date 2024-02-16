--[[
    Server side of Grid
]]

local Players = game:GetService("Players")

local Server = {}
local Shared = require(script.Parent:WaitForChild("Shared"))

function HandlerFireClient(handler, client, ...)
	if Shared.LoggingActive then
		table.insert(Shared.Logs[client][handler.Remote].Out, Shared.GetParametersString(...))
	end

	return handler.Remote:FireClient(client, ...)
end

--[[
    Returns all players
]]
function Server:GetPlayers(): { Player }
	return Players:GetPlayers()
end

--[[
    Returns player's position, can be nil
]]
function Server:GetPlayerPosition(player: Player): Vector3?
	return player and player.Character and player.Character.PrimaryPart and player.Character.PrimaryPart.Position or nil
end

--[[
    Fires to a single client
]]
function Server:FireClient(client: Player, event: string, ...: any)
	local handler = Shared.GetEventHandler(event)
	if not handler then
		error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
	end

	HandlerFireClient(handler, client, ...)
end

--[[
    Fires to every client in the server
]]
function Server:FireAllClients(event: string, ...)
	local handler = Shared.GetEventHandler(event)
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
function Server:FireOtherClients(exceptClient: Player, event, ...)
	local handler = Shared.GetEventHandler(event)
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
function Server:FireOtherClientsWithinDistance(client: Player, maxDistance: number, event: string, ...)
	local handler = Shared.GetEventHandler(event)
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
function Server:FireAllClientsWithinDistance(position: Vector3, maxDistance: number, event: string, ...)
	local handler = Shared.GetEventHandler(event)
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
function Server:InvokeClientWithTimeout(timeout: number, client: Player, event: string, ...): (boolean, any?)
	local handler = Shared.GetEventHandler(event)
	if not handler then
		error(("[Grid]: '%s' is not a valid RemoteEvent"):format(event))
	end

	return Shared.SafeInvoke(timeout, handler, client, ...)
end

--[[
    Invokes client with a 60 seconds timeout

    YIELDS
]]
function Server:InvokeClient(client: Player, event: string)
	return self:InvokeClientWithTimeout(60, client, event)
end

--[[
    Logs grid traffic with possible output but doesn't yield
]]
function Server:LogTraffic(duration: number, shouldOutput: boolean)
	task.spawn(self.LogTrafficAsync, self, duration, shouldOutput)
end

--[[
    Logs grid traffic with possible output

    YIELDS
]]
function Server:LogTrafficAsync(duration: number, shouldOutput: boolean)
	--[[
        Debug output
    ]]
	local function output(...)
		if shouldOutput == true then
			Shared.DebugWarn(...)
		end
	end

	if Shared.LoggingActive then
		return
	end
	output("Logging Grid Traffic...")

	local start = os.clock()
	task.wait(duration)
	local effDur = os.clock() - start

	local clientTraffic = Shared.Logs

	for player: Player, remotes in pairs(clientTraffic) do
		local totalReceived = 0
		local totalSent = 0

		for _, data in pairs(remotes) do
			totalReceived += #data.In
			totalSent += #data.Out
		end

		output(string.format("Player '%s', total received/sent: %d/%d", player.Name, totalReceived, totalSent))

		for remote, data in pairs(remotes) do
			-- Incoming

			local listIn = data.In
			if #listIn > 0 then
				output(string.format("   %s %s: %d (%.2f/s)", "FireServer", remote.Name, #listIn, #listIn / effDur))

				local count = math.min(#listIn, 3)
				for i = 1, count do
					local index = math.floor(1 + (i - 1) / math.max(1, count - 1) * (#listIn - 1) + 0.5)
					output(string.format("      %d: %s", index, listIn[index]))
				end
			end

			-- Outgoing

			local listOut = data.Out
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

return Server

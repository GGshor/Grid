--[[
	-- Shared API

		Grid:LinkFunctions(local, functions)
		Grid:LinkEvents(local, events)

	-- Server API

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

		Grid:FireServer(name, ...)

		Grid:InvokeServer(name, ...)
		Grid:InvokeServerWithTimeout(timeout, name, ...)



	Notes:
		- The first return value of InvokeClient (but not InvokeServer) is bool success, which is false if the invocation timed out
		or the handler errored.

		- InvokeServer will error if it times out or the handler errors.

		- InvokeServer/InvokeClient do not return instantly on an error, but instead check for failure every 0.5 seconds. This is
		because it is not possible to both instantly detect errors and have them be logged in the output with full stacktraces.
]]

local RunService = game:GetService("RunService")

if RunService:IsServer() then
	return script:WaitForChild("Server")
else
	return script:WaitForChild("Client")
end

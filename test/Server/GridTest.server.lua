local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Grid = require(ReplicatedStorage.Grid)

-- Do functions
while true do
	Grid:FireAllClients("Notification", "TEST")

	task.wait(1)
end

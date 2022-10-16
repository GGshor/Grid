local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Grid = require(ReplicatedStorage.Grid)

-- Do functions
Grid:FireAllClients("Notification", "Test notification")
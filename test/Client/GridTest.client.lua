local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Grid = require(ReplicatedStorage:WaitForChild("Grid"))

-- Test all functions
Grid:BindEvents({
    ["Notification"] = function(message: string)
        print(message)
    end
})
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Grid = require(ReplicatedStorage:WaitForChild("Grid"))

return function()
	describe("Test server functions", function()
		it("should fire to all clients", function()
			expect(function()
				Grid:FireAllClients("Test")
			end).never.to.throw()
		end)

		it("should throw an error when using client methods", function()
			expect(function()
				Grid:FireServer("Test")
			end).to.throw()
		end)
	end)
end

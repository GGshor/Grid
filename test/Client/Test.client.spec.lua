local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Grid = require(ReplicatedStorage:WaitForChild("Grid"))

return function ()
	describe("Test client functions", function()
		it("should bind events without errors", function()
			expect(function()
				Grid:BindEvents({
					["Test"] = function()
						return
					end
				})
			end).to.never.throw()
		end)

        it("should throw an error when using server methods", function()
            expect(function()
                Grid:FireServer("Test")
            end).to.throw()
        end)
	end)
end
--!strict
-- Radio cutscene (placeholder until implemented).

local Kit = require(script.Parent.Kit)

return function(_data: any, kit: typeof(Kit))
	kit.fade(1, 0.6)
	kit.wait(0.6)
end

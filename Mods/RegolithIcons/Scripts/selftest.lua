-- Self-check for the dominant oxide pick. Runs outside the game with any Lua 5.4
-- (package.path must include this Scripts folder) or through DevBridge.
local Icons = require("icons")

local Ti, Fe, Si, Al, Slag, Regolith = 2, 3, 4, 5, 6, 1

-- Deposit profiles seen in game: one rich oxide, slag ignored even when larger.
assert(Icons.Pick({ [Ti] = 0.07, [Fe] = 0.05, [Si] = 0.57, [Al] = 0.04, [Slag] = 0.27 }) == Si)
assert(Icons.Pick({ [Ti] = 0.49, [Fe] = 0.04, [Si] = 0.06, [Al] = 0.04, [Slag] = 0.37 }) == Ti)
assert(Icons.Pick({ [Ti] = 0.10, [Fe] = 0.20, [Slag] = 0.70 }) == Fe)
-- Blends: no oxide twice the runner-up.
assert(Icons.Pick({ [Ti] = 0.15, [Fe] = 0.15, [Si] = 0.15, [Al] = 0.14, [Slag] = 0.40 }) == Regolith)
assert(Icons.Pick({ [Ti] = 0.30, [Fe] = 0.27, [Slag] = 0.43 }) == Regolith)
-- Never held regolith.
assert(Icons.Pick({}) == nil)

print("RegolithIcons selftest OK")

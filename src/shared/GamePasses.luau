--!strict
-- The game passes on sale in the lobby (LobbyMenu's Passes tab) and what
-- each one does (server GamePasses). Create each pass on the Creator
-- Dashboard (your experience > Monetization > Passes) and put its id here;
-- a pass with id 0 isn't set up yet and shows as "Coming soon".

export type Pass = {
	key: string, -- the player attribute Pass_<key> is true when owned
	id: number,
	name: string,
	description: string,
	order: number,
}

local GamePasses = {}

GamePasses.List = {
	{
		key = "ExtraLife",
		id = 2058442287,
		name = "Second Wind",
		description = "One extra life every night (Normal, Hard and Nightmare).",
		order = 1,
	},
	{
		key = "DoubleTeeth",
		id = 2058388294,
		name = "Collector",
		description = "Earn twice the Teeth for everything you do.",
		order = 2,
	},
	{
		key = "SurvivorKit",
		id = 2058760281,
		name = "Survivor Kit",
		description = "Start every night with a bandage and a spare battery.",
		order = 3,
	},
} :: { Pass }

GamePasses.ByKey = {} :: { [string]: Pass }
for _, pass in GamePasses.List do
	GamePasses.ByKey[pass.key] = pass
end

-- Whether a player has this pass (owned: the server sets Pass_<key>).
function GamePasses.owns(player: Player, key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true
end

return GamePasses

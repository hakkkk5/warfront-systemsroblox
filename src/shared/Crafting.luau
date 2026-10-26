--!strict
-- What the workbenches make (server Crafting.luau checks it, the client
-- Crafting screen shows it). Junk for them turns up everywhere: bottles, rags,
-- moonshine, tape, alarm clocks.

export type Recipe = {
	id: string,
	result: string, -- Items id
	count: number,
	needs: { { item: string, count: number } },
	blurb: string,
}

local Crafting = {}

-- in display order
Crafting.Recipes = {
	{
		id = "Molotov",
		result = "Molotov",
		count = 1,
		needs = { { item = "Bottle", count = 1 }, { item = "Rag", count = 1 }, { item = "Moonshine", count = 1 } },
		blurb = "Stuff the rag in the bottle, soak it. Throw it at them.",
	},
	{
		id = "NoiseTrap",
		result = "NoiseTrap",
		count = 1,
		needs = { { item = "AlarmClock", count = 1 }, { item = "Tape", count = 1 } },
		blurb = "Tape the bell open and set it. Throw it where you want them to go.",
	},
	{
		id = "FirstAidKit",
		result = "FirstAidKit",
		count = 1,
		needs = { { item = "Bandage", count = 1 }, { item = "Moonshine", count = 1 } },
		blurb = "Clean the wound first this time. Heals you fully.",
	},
} :: { Recipe }

Crafting.ById = {} :: { [string]: Recipe }
for _, r in Crafting.Recipes do
	Crafting.ById[r.id] = r
end

-- How close (studs) you have to stand to a bench to use it.
Crafting.BENCH_RANGE = 12

return Crafting

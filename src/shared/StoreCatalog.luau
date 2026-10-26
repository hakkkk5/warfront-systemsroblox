--!strict
-- What the lobby store sells: starting perks, paid for in Teeth earned by
-- playing. A perk is used up at the start of the next run, when its item is
-- put in your bag (server Store.grantPerks). Prices and caps live here so the
-- lobby UI and the server agree.

export type Perk = {
	id: string,
	item: string, -- Items id handed out at the start of a run
	name: string,
	description: string,
	price: number,
	max: number, -- how many you can stock up
	order: number,
}

local StoreCatalog = {}

StoreCatalog.Currency = "Teeth"

-- Daily supplies: Teeth for turning up in the lobby on consecutive days
-- (server Profiles.claimDaily), day 1 to 7; every day after the seventh
-- pays the last.
StoreCatalog.Daily = { 5, 8, 10, 12, 15, 20, 30 }

function StoreCatalog.dailyFor(streak: number): number
	local days = StoreCatalog.Daily
	return days[math.clamp(streak, 1, #days)]
end

StoreCatalog.Perks = {
	Battery = {
		id = "Battery",
		item = "Battery",
		name = "Spare Battery",
		description = "Start the night with a fresh battery for your flashlight.",
		price = 40,
		max = 5,
		order = 1,
	},
	Bandage = {
		id = "Bandage",
		item = "Bandage",
		name = "Bandage",
		description = "Start with a bandage. Heals 40 when you're hurt.",
		price = 60,
		max = 5,
		order = 2,
	},
	Syringe = {
		id = "Syringe",
		item = "Syringe",
		name = "Sedative Syringe",
		description = "Start with a syringe: put one of the family to sleep, or fight back when grabbed.",
		price = 120,
		max = 3,
		order = 3,
	},
} :: { [string]: Perk }

-- Teeth earned in a run (server Rewards.luau)
StoreCatalog.Rewards = {
	escape = 100, -- times the difficulty bonus below
	note = 5, -- each note read for the first time this run
	sedate = 20, -- each cannibal put to sleep
	chore = 4, -- each household chore, for everyone in the house
}

StoreCatalog.DifficultyBonus = {
	Normal = 1,
	Hard = 1.5,
	Nightmare = 2,
} :: { [string]: number }

function StoreCatalog.list(): { Perk }
	local list: { Perk } = {}
	for _, perk in StoreCatalog.Perks do
		table.insert(list, perk)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

return StoreCatalog

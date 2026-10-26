--!strict
-- Achievements and the hidden polaroids. Both are saved with the profile
-- (server Profiles: Data.achievements, Data.polaroids), pay Teeth the first
-- time, and show in the lobby's Records page. The server decides when one is
-- earned (server Achievements.luau); this list is what both sides agree on.

export type Achievement = {
	id: string,
	name: string,
	description: string,
	teeth: number,
	secret: boolean?, -- shown as ??? until earned
}

export type Polaroid = {
	id: string,
	title: string, -- what's written on the back
	caption: string, -- what you see, shown in the journal
}

local Trophies = {}

local ACHIEVEMENTS: { Achievement } = {
	{ id = "HouseEscape", name = "Checked Out Early", description = "Escape the farmhouse.", teeth = 25 },
	{ id = "TruckFixed", name = "Grease Monkey", description = "Get the old pickup running.", teeth = 25 },
	{ id = "PowerOn", name = "Let There Be Light", description = "Restore power at the ranger station.", teeth = 25 },
	{ id = "Rescued", name = "Wheels Up", description = "Reach the rescue helicopter.", teeth = 40 },
	{ id = "Downed", name = "Hard Landing", description = "Crawl out of the helicopter wreck.", teeth = 25, secret = true },
	{ id = "PlantEscape", name = "Off The Hook", description = "Get out of Hollow Meats alive.", teeth = 40, secret = true },
	{ id = "MineEscape", name = "Canary", description = "Make it through the old mine.", teeth = 40, secret = true },
	{ id = "Finished", name = "Last Rites", description = "See an ending.", teeth = 60 },
	{ id = "TrueEnding", name = "Nobody Left Behind", description = "Save Ranger Ellis and the pilot.", teeth = 150, secret = true },
	{ id = "Nightmare", name = "Iron Stomach", description = "Finish the game on Nightmare.", teeth = 200 },
	{ id = "Lullaby", name = "Lullaby", description = "Put three of the family to sleep in one night.", teeth = 40 },
	{ id = "Distraction", name = "Over There!", description = "Lure one of the family away with a thrown bottle or rock.", teeth = 15 },
	{ id = "Molotov", name = "Flambé", description = "Hit one of the family with a molotov.", teeth = 30 },
	{ id = "Crafter", name = "Handy", description = "Craft five things at workbenches in one night.", teeth = 30 },
	{ id = "Unseen", name = "Ghost", description = "Finish a chapter without being chased.", teeth = 35 },
	{ id = "Bookworm", name = "Bookworm", description = "Read every note in one night.", teeth = 40 },
	{ id = "Collector", name = "Family Album", description = "Find every hidden polaroid.", teeth = 150 },
	{ id = "Hider", name = "Hold Your Breath", description = "Hide while one of the family walks right past.", teeth = 15 },
	{ id = "Billboard", name = "Highest Point", description = "Ring the bell on top of the truck stop billboard.", teeth = 10 },
}

-- Thirteen photos hidden around the valley, one story told in pieces.
local POLAROIDS: { Polaroid } = {
	{ id = "P01", title = "Summer '71", caption = "A young couple outside a brand new farmhouse. A sign on the porch: HOLLOW MEATS - FAMILY BUTCHERS." },
	{ id = "P02", title = "The boys", caption = "Two little boys in matching aprons, holding a cleaver between them. They're both grinning." },
	{ id = "P03", title = "Grand opening", caption = "A ribbon across the plant gates. The whole town turned out. Everyone's smiling." },
	{ id = "P04", title = "Winter of '79", caption = "Snow up to the windows. The shelves in the store behind them are completely empty." },
	{ id = "P05", title = "Sunday supper", caption = "A long table, every seat filled. Only the family is looking at the camera." },
	{ id = "P06", title = "Inspection", caption = "A man in a county jacket with a clipboard, at the plant door. Someone has drawn an X over his face." },
	{ id = "P07", title = "Closed", caption = "The plant gates chained shut. A notice: CLOSED BY ORDER OF THE COUNTY. The gates are open in every later photo." },
	{ id = "P08", title = "Mama", caption = "A woman in a church dress holding a pie. The filling is very, very red." },
	{ id = "P09", title = "The mine", caption = "Miners at the shaft head, black with coal. One of them is circled. Under it: 'kept us fed all winter'." },
	{ id = "P10", title = "Pinecrest", caption = "Main Street, the church at the end of it. Not one person in the street. Not one car." },
	{ id = "P11", title = "Masks", caption = "The whole family in their masks, posed like a school picture. The smallest mask is on a child." },
	{ id = "P12", title = "Guests", caption = "Dozens of photos of strangers, pinned to a board. Some faces have a red tick. Most of them do." },
	{ id = "P13", title = "You", caption = "A blurry photo through a car windscreen on Hollow Road, in the rain. It's your car. It was taken before the crash." },
}

Trophies.Achievements = {} :: { [string]: Achievement }
for _, a in ACHIEVEMENTS do
	Trophies.Achievements[a.id] = a
end

Trophies.Polaroids = {} :: { [string]: Polaroid }
for _, p in POLAROIDS do
	Trophies.Polaroids[p.id] = p
end

Trophies.POLAROID_TEETH = 10

-- In display order.
function Trophies.achievementList(): { Achievement }
	return table.clone(ACHIEVEMENTS)
end

function Trophies.polaroidList(): { Polaroid }
	return table.clone(POLAROIDS)
end

return Trophies

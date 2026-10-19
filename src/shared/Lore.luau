--!strict
-- Readable notes scattered around the map.

export type Note = { title: string, body: string }

local Lore: { [string]: Note } = {
	Ledger = {
		title = "Meat Ledger",
		body = "OCT 3 - two hikers. Good weight.\nOCT 9 - trucker. Tough, smoked him.\nOCT 15 - girl from the gas station. Mama says no more locals.\nOCT 19 - car off the highway. Brother laid the log across the road like Papa showed us.\n\nKeep the knife sharp. Keep the door chained. Keep the key UPSTAIRS where the meat can't reach it.",
	},
	Diary = {
		title = "Mama's Diary",
		body = "The boys are getting careless. The Butcher leaves his truck keys on his belt like a trophy, jingling everywhere he goes. I can hear him coming a mile off.\n\nAbel sleeps upstairs now. He says the meat whispers at night.\n\nPapa took the motor out of the old truck so nobody leaves. Nobody ever leaves.",
	},
	Drawing = {
		title = "Child's Drawing",
		body = "(A crayon drawing of a house. Stick figures with sacks over their heads stand around a long table. One figure is lying on the table.)\n\nWritten underneath in shaky letters:\n\"FAMILY DINNER. I HIDE IN THE CLOSET WHEN BROTHER IS ANGRY. HE NEVER LOOKS IN THE CLOSET.\"",
	},
	Clipping = {
		title = "Newspaper Clipping",
		body = "PINECREST GAZETTE\n\nFOURTH HIKER MISSING NEAR HOLLOW ROAD\n\nState police have suspended the search for 24-year-old Dana Whitlock, last seen hiking the Hollow Ridge trail. She is the fourth person reported missing in the area this year.\n\nRanger Tom Ellis urged travellers to stay on the highway: \"If your car breaks down, stay in the car and radio the ranger station. Do not go into those woods.\"",
	},
	HunterLog = {
		title = "Hunter's Log",
		body = "Day 6. Something is following me. Not a bear. It walks on two legs and it hums.\n\nDay 7. Found my camp torn apart. They left my truck battery but took the deer. I stashed the battery under the tarp so the cold won't kill it.\n\nDay 8. I can see lanterns between the trees. If anyone finds this - the ranger station is past the burned bridge, east along the logging road. There's a radio.",
	},
	DoctorNote = {
		title = "Dr. Hale's Notes",
		body = "Field notes - wildlife sedation study\n\nThe xylazine mix drops a 300 lb black bear in under ten seconds. Inject into the neck or upper back, from BEHIND - an alert animal will never let you close.\n\nEffect lasts roughly a minute and a half on a large male.\n\nI have stopped going out at night. The 'animals' in this valley carry cleavers.\n\nSpare spark plugs for the generator are in the trailer.",
	},
	BarnNote = {
		title = "Scrawled Warning",
		body = "THE MOTOR IS IN THE BARN\nPAPA SAYS IT STAYS IN THE BARN\nIF YOU TOUCH THE MOTOR PAPA WILL HEAR\n\n(The writing gets smaller towards the bottom of the page.)\n\nhe always hears",
	},
	RangerLog = {
		title = "Ranger Station Log",
		body = "Generator failed again during the storm. Blown fuse - I left the spare in the lookout tower. Fuel can is in the tool shed.\n\nOnce the generator's up, the radio reaches Pinecrest dispatch. They can get the rescue chopper to the helipad in about two minutes.\n\nIf you're reading this and I'm not here: don't wait for me. Turn on the generator, call dispatch, and lock the door.",
	},
}

return Lore

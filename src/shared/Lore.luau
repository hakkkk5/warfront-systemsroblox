--!strict
-- Readable notes scattered around the map.

export type Note = { title: string, body: string }

local Lore: { [string]: Note } = {
	Ledger = {
		title = "Meat Ledger",
		body = "OCT 3 - two hikers. Good weight.\nOCT 9 - trucker. Tough, smoked him.\nOCT 15 - girl from the gas station. Mama says no more locals.\nOCT 19 - car on the highway. Jason ran it off the road with the truck, lights off, like Papa showed us.\n\nKeep the knife sharp. Keep the door chained. Keep the key UPSTAIRS where the meat can't reach it.",
	},
	Diary = {
		title = "Mama's Diary",
		body = "The boys are getting careless. Jason leaves his truck keys on his belt like a trophy, jingling everywhere he goes. I can hear him coming a mile off.\n\nMichel sleeps upstairs now. He says the meat whispers at night.\n\nPapa took the motor out of the old truck so nobody leaves. Nobody ever leaves.",
	},
	Drawing = {
		title = "Child's Drawing",
		body = "(A crayon drawing of a house. Stick figures with sacks over their heads stand around a long table. One figure is lying on the table.)\n\nWritten underneath in shaky letters:\n\"FAMILY DINNER. I HIDE IN THE CLOSET WHEN MICHEL IS ANGRY. HE NEVER LOOKS IN THE CLOSET.\"",
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

	-- Chapter 1 clues (Investigation.luau)
	ClueNewspaper = {
		title = "Pinecrest Gazette",
		body = "SIX VANISH ON HOLLOW ROAD IN TWO YEARS\n\nState police have again called off the search along Hollow Road, where six travellers have disappeared since 2022. Most were last seen after car trouble on the stretch of highway beside the old Garrett farm.\n\nJason and Michel Garrett, who have run the farm for twenty years, told the Gazette they \"do what we can for folks when the storm takes the road.\"\n\n\"We always take them in,\" said Michel.",
	},
	ClueMissing = {
		title = "Missing Posters",
		body = "A thick stack of MISSING posters, the same ones from the gas station board.\n\nDale Whitcomb. The Harlan family. Marisol Vega. Deputy Brandt. A dozen more you don't recognise.\n\nEvery face has been crossed out in red marker, one by one, and a date written beside it.\n\nThe last poster is blank. Someone has written today's date on it.",
	},
	ClueClothes = {
		title = "Bloody Jacket",
		body = "A sheriff's department jacket, stiff with dried blood. The sleeve has been cut away clean, like a joint of meat.\n\nThe name tag is still stitched over the pocket:\n\nDEP. T. BRANDT\nPINECREST SHERIFF'S DEPT.",
	},
	CluePhotos = {
		title = "Family Photos",
		body = "Photos in cheap frames. Jason and Michel smile in every one of them: at a picnic, by the truck, at the dinner table.\n\nEvery other face has been scratched out with something sharp.\n\nThe newest photo is a polaroid, still curling at the edges. It shows your car, wrapped around the pine on Hollow Road.",
	},
	ClueTeeth = {
		title = "Kitchen Drawer",
		body = "The drawer is full of teeth.\n\nDozens of them, sorted by size into a cutlery tray. Some still have fillings. A few are small enough to be a child's.\n\nA label taped to the front reads, in neat handwriting: KEEPSAKES.",
	},
	TomTally = {
		title = "Scratched Note",
		body = "Written in pencil on the back of a seed packet, pressed flat under the tally marks:\n\nDAY 14. Ranger T. Ellis, Pinecrest. They grabbed me at the station when the generator died. The fuse is still in the lookout tower - if anyone gets this, the station radio WORKS.\n\nThey take one of us upstairs every few days. The big one hums when he sharpens.\n\nThey always come down at night. I can hear the hatch.",
	},
	ClueFridge = {
		title = "Freezer Packages",
		body = "The fridge is packed with white paper parcels, frozen solid, each one labelled in neat marker:\n\nDALE - RIBS\nMARISOL - SHOULDER\nBRANDT - STEW MEAT\nHARLAN (SMALL) - SAUSAGE\n\nThe parcel at the front isn't frozen yet. The label is blank, waiting for a name.",
	},
	ClueHatch = {
		title = "Basement Hatch",
		body = "A heavy hatch in the kitchen floor, chained shut with a padlock the size of your fist.\n\nCold air seeps up through the cracks. It smells like a butcher's shop.\n\nThe wood around the edge has been scratched, deep and frantic, from the other side.",
	},
}

return Lore

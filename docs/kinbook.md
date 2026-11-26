# Kinbook: the cast and the running jokes

Kinbook is the town's social media, an app on the phone
(`scripts/ui/kinbook.gd`). It's the trashy corner of the game's humour
(`docs/design.md` section 8): anonymous call-outs, vague posts fishing
for "u ok hun", ChipIns for things people did to themselves, and comment
sections that wander into politics, who dated who, and outing whoever
posted "anonymously". The comments are the joke.

The same people turn up everywhere, so the town feels like one place and
the jokes build. This file is who they are. Keep them consistent: a new
post or story should sound like the person who wrote it.

## The rules

- **Trashy, not explicit.** The whole island has dated the same few
  people, and everybody admits it ("Halibut was 2019 for me"). Never
  spelled out.
- **Never on someone who's actually struggling.** Rent, the doctor list
  and the hospital are fair game; the joke's on the landlord, the
  province and the people being dramatic about a cholesterol check.
- **Made-up people only**, first name and an initial, the way these
  groups look. World brands from the README's table. No real people,
  businesses or parties.
- **Real Facebook habits:** "." to follow a post, "Commenting for
  updates", "PM me hun", "Not on here", "Who's your father?", the admin
  turning comments off, everyone asking "which one".

## Where the posts come from

| Where | File | What |
|---|---|---|
| Written posts | `kinbook_lines.gd` (POSTS, CHIPINS) | Rants & Raves, the dating group, ChipIns, there from the start |
| Own-page posts | `kinbook_stories.gd` (WALL) | Vague posts and drama on people's own pages |
| Stories | `kinbook_stories.gd` (STORIES) | Runs of posts that come out one every 4 minutes of play, saved, so they carry on next session (and 2 more come out for the time you were away) |
| Made from parts | `kinbook_gen.gd` | A new post every 70 seconds of play: rants, raves, questions, lost pets, vague posts, dating call-outs, ChipIns, each with a thread and maybe a tangent |
| About you | `kinbook_lines.gd` (ABOUT_YOU) | Your chases: when it gets going, and when you're caught or get away |

`tools/kinbook_check.gd` checks all of it.

## The cast

| Who | What they're like | Running jokes |
|---|---|---|
| **Paulette G.** | Posts that she's going through a very hard time and won't be updating everyone, then updates everyone | Story: the casserole feud with Darlene. Always "Not on here." Everyone thinks she posted it anonymously |
| **Darlene M.** | Bingo regular, "u ok hun??" first on every vague post | Feuds with Shelley at bingo, then with Paulette over a casserole she brought to a funeral and said was hers |
| **Shelley M.** | Bingo rival; her husband went to Countess Auto for one bolt | "Some people should mind their own cards." Purple dauber. Trudy says Shelley "kept my husband" |
| **Trudy K.** | Owns the truck Brent says is his | "Sending hugs xo." Took in Gary the cat |
| **Bernice H.** | Asks "Who's your father?" and "What happened??" | Dramatic hospital post: a cholesterol check |
| **Marlene T.** | Her son does "very good work actually" (he doesn't) | Her son Kevin is in the next room. Her other son built Wanda's deck, now in the yard |
| **Wanda F.** | ALL CAPS when she's "being civil" | The unattached deck. Bernard took her hubcap, twice |
| **Kayleigh J.** | Has dated everyone | "I think I dated him." Story: engaged to Kyle, then not; kept the ring and the air fryer |
| **Brittany B.** | One of three Brittanys | "WHICH Brittany." With Kyle in his mother's camper. Possibly on Reggie's boat |
| **Kyle's mother** | Corrects everyone about where Kyle lives | "They are NOT in my basement. They're in the camper." Later the basement |
| **Heather D.** | The voice of reason, also the entire Green Party | "Of course you did Kayleigh." "From WHAT Lorne." Had two muffins at Dale's town hall |
| **Lorne P.** | Comments "." on everything so he gets updates | Story: learns to say "commenting for updates". "is there a reward". "i pay SOME taxes" |
| **Gord W.** | Grumpy, "where are you from though" | "Nobody asked Dale." Secretly voted for Dale |
| **Dale S. (Orange Party)** | The Orange candidate for District 9, relentlessly upbeat | Story: the campaign, the stolen sign ("it was the wind"), the free coffee, 212 votes |
| **Wade E.** | Everything is politics. Drives for SpudDash. Speeding tickets | "This is what you get for voting Blue." "This is." Gord's fries were cold |
| **Brent S.** | Asks "what colour" on every theft post | Story: the impound ChipIn, the truck that's Trudy's, the never-used winch |
| **Garth R.** | Landlord with twelve struggling houses | Story: "some of us landlords are struggling too", the sink, luxury condos on Euston. Everybody's landlord is Garth |
| **Siobhan L.** | Garth's tenant | "Fix my sink Garth." "GARTH" |
| **Colby A.** | Outs the anonymous posters | "We all know this is Paulette." "Ok Tanner" |
| **Tanner O.** | Posts his rant on his own page, then "anonymously" | The Disney ChipIn. "lol" |
| **Clayton V.** | His brother-in-law has the paving contract and can do anything for cash | "Mostly from home" |
| **Doug R.** | Owns the truck everyone borrows. Knows it's Brenda | "Hi Bernard" |
| **Reggie B.** | His boat sank and everybody knows how | "Was this the same day the boat sank." "Not now Reggie" |
| **Tyler** (never posts) | Lifted black truck, "doesn't do drama", there are forty of him | Has the air fryer. Is seeing everyone's sister |
| **Marjorie** (never posts) | Cheats at bingo | Not invited to the new bingo |
| **Bernard** | The pothole on Kirkwood | Named, had a birthday, filled with a ribbon cutting, came back |
| **Admin** | Tries | "No names please." "This is not a buy and sell group." Turns comments off |

## The stories so far

Each is in `KinbookStories.STORIES`, in order. A story's posts come out
one at a time; most picks carry on a story already going.

- **paulette:** a very hard time → not updating anyone → "Darlene knows
  what she did" → the casserole → "we're fine" → "Not fine."
- **bernard:** the pothole gets a name → a birthday party → the province
  sends a man in a vest → filled at a ribbon cutting → "Bernard is back."
- **dale:** running for the Orange Party → the sign → the town hall → the
  coffee → 212 votes, and Gord voted for him.
- **bingo:** Darlene and Shelley's feud → CHEAT in dauber → both banned →
  their own bingo night; Marjorie's not invited.
- **air_fryer:** Tyler kept it → his mother sells it → bought back for $40
  with a casserole thrown in.
- **garth:** struggling landlord → reported by all twelve tenants → the
  sink → luxury condos.
- **brent:** gets the truck back → Trudy sells it → sells the winch.
- **kayleigh:** "new beginnings" → engaged to Kyle → off, keeping the
  ring and the air fryer.
- **lorne:** why nobody answers his "." → "commenting for updates".

## Adding to it

- **A new post in a story:** add it to the end of the story's list. It
  comes out next for anyone who's reached the end so far.
- **A new story:** add a list to STORIES. It starts for everyone.
- **More variety in the made-up posts:** add whole phrases to a list in
  `kinbook_gen.gd` (a sin, a ChipIn need, a vague opener, a tangent).
  Phrases must read right with any other part.
- Then `tools/kinbook_check.gd`.

Ideas for stories later: Dale runs again; Bernard Junior; the Brittanys
meet; Garth's condos get a ChipIn; Wade gets a dash cam; the Admin goes
through a very hard time and will not be updating everyone.

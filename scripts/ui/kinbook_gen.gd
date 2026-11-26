class_name KinbookGen
extends RefCounted
## Makes new Kinbook posts from parts, so the feed always has something
## fresh: rants, raves, questions, lost-and-found, vague posts fishing for
## "u ok hun", dating call-outs and ChipIns, each with a thread built from
## the regulars' habits (docs/kinbook.md). post(rng, used) gives one post
## not made before this session (`used` holds what's been made).
##
## Parts are whole phrases, so any mix reads right. {street}, {place},
## {man} and {who} are filled in, the same value through the whole post.

const STREETS := ["Grafton", "University", "Queen", "Kent", "Belvedere", "St. Peters Road", "Allen", "Euston",
	"North River Road", "Water Street", "Capital Drive", "Mount Edward Road", "Riverside Drive", "Kirkwood", "Brackley Point Road"]
const PLACES := ["the Megastore", "SoBuys", "the Tim Hardly's on Grafton", "Maple Tire", "the Ervin's on Riverside",
	"Countess Auto", "the BuyMart", "the Reelplex", "Stoppers", "the liquor store", "the Legion"]
## The regulars who post on their own pages and comment everywhere.
const CAST := ["Shelley M.", "Darlene M.", "Trudy K.", "Paulette G.", "Wanda F.", "Bernice H.", "Kayleigh J.",
	"Heather D.", "Doug R.", "Gord W.", "Reggie B.", "Brent S.", "Colby A.", "Siobhan L.", "Marlene T.", "Clayton V.",
	"Jean-Guy B.", "Tanner O.", "Lorne P.", "Wade E.", "Priya N.", "Ana C.", "Mohammed A."]
const MEN := ["Tyler", "Kyle", "Brandon", "Cody", "Jordan", "Travis", "Dustin", "Ryan", "Chad", "Logan"]

# --- rants and raves ---------------------------------------------------------------------------

const DRIVERS := ["the white Halfton", "the lifted black truck with the stickers", "the Kayo with the Ontario plates",
	"the silver Civique", "the guy in the Dodgy", "the SpudDash driver in the blue hatchback", "the rental car",
	"the Fjord with one headlight", "the minivan with six stick-figure kids on the back window"]
const SINS := ["parked across three spots at {place}", "did ninety through the school zone on {street}",
	"sat at a green light on {street} reading his phone", "stopped dead on {street} to take a picture of a church",
	"tailgated me the whole length of {street}", "went round the roundabout twice and then waved at ME",
	"ran the red on {street} like it was a suggestion", "blocked the drive-thru lane at {place} for a \"quick chat\"",
	"took the last cart at {place} and left it in the middle of the lot"]
const WHENS := ["this morning", "yesterday around five", "at seven a.m. on a Sunday", "again", "on my birthday"]
const RANT_KICKERS := ["We all know who you are.", "Your mother would be ashamed. I know her.", "This is why we can't have nice things.",
	"It's not Toronto, buddy.", "I have it on my dash cam. I don't have a dash cam. But I remember.",
	"I won't say your name. But I'll say it at bingo.", "You know what you did."]
const GENERAL_RANTS := [
	"RANT: Twenty-two dollars for a pizza at {place}. It was a medium. It was sad.",
	"RANT: My power's been out on {street} three times this week. My bill went up anyway. Explain that, Island Electric.",
	"RANT: The new condos on {street} are \"starting at $689,000.\" Starting. Where does it end.",
	"RANT: Two hours on hold with the province to be told to call the city. The city told me to call the province.",
	"RANT: The orange cones on {street} have been there so long they're on the map now.",
	"RANT: Paid $14 for parking downtown to go to a meeting about the parking downtown.",
	"RANT: To the person who keeps putting their recycling in MY blue bin. I know it's you. You're the only one who buys that much Pepsi.",
	"RANT: The guy at {place} called me \"bud\" four times in one sentence. I counted.",
	"RANT: The Tim Hardly's line on {street} went past the Ervin's again. Some of us have jobs. Some of us are in the line too, but still.",
]
const RAVE_ACTS := ["helped me jump my car", "carried my groceries all the way across the lot", "gave me his parking spot",
	"let me go ahead of him in line", "paid for my double-double", "handed in my wallet, cash and all",
	"pushed my car out of a snowbank in his work clothes", "held the door and didn't call me \"bud\""]
const RAVE_KICKERS := ["Your mother raised you right.", "Restored my faith in people. For about a day.",
	"If you're single, my daughter is.", "Faith in the Island: restored.", "I'd tell you your name but you know it."]
const QUESTIONS := [
	"QUESTION: Anyone know why the power's out on {street} AGAIN?",
	"QUESTION: Is it just me or did {place} put the prices up again?",
	"QUESTION: Does anyone know a mechanic who won't rob me?",
	"QUESTION: What's going on at {place}? Six cop cars and an FIP truck.",
	"QUESTION: Who do I call about the pothole on {street}? It's big enough to have a name.",
	"QUESTION: Anyone know a plumber who actually answers the phone?",
	"QUESTION: Is the bridge open? Asking for my mother-in-law. Hoping no.",
	"QUESTION: Why does the Arterial back up at 4:55 every day? There's six of us.",
	"QUESTION: Anyone else hear that bang on {street} last night or am I losing it?",
]
const PETS := ["Orange cat", "Small brown dog", "Very large rabbit", "A goat", "Grey cat with one ear", "A chicken",
	"Big black dog with a ball he won't give back"]
const PET_WHERE := ["near {place}", "on {street}", "in my garage", "on my deck", "at the bus stop on {street}"]
const PET_NOTES := ["Very friendly. Too friendly. Please come get him.", "Has a collar that says \"Do not feed.\" We fed him.",
	"Has been here two days and seems to own the place now.", "My husband wants to keep him. Please hurry.",
	"Will not leave. Has opinions.", "Ate a sandwich. Not his. Not mine either."]

# --- vague posts on people's own pages ---------------------------------------------------------

const VAGUE_OPENERS := ["Going through a lot right now.", "Things are very hard right now.", "Some days are harder than others.",
	"Feeling really let down today.", "Wow.", "Some people really show you who they are.",
	"Can't believe I have to deal with this today of all days.", "Need my space right now.", "I'm done.",
	"Never thought I'd see the day."]
const VAGUE_MIDDLES := ["I don't want to talk about it.", "Not getting into it on here.", "I will not be updating everyone.",
	"Please respect my privacy.", "You know who you are.", "That's all I'll say.", "Please don't message me."]
const VAGUE_CLOSERS := ["", "Thank you to the ones who checked on me.", "Some people need to look in the mirror.", "Karma's real.",
	"Focusing on me and the kids.", "Going to bed.", "Please respect that.", "Blessed anyway."]
const VAGUE_COMMENTS := ["u ok hun??", "Sending hugs xo", "PM'd you", "Messaged you hun", "What happened??", "Thinking of you",
	"Here if you need anything", "Call me", "Love you girl", "Praying for you", "Who do I need to fight", "Stay strong",
	"Hope you're ok", "Inbox me", "Karma's real hun", "Here for you always"]
const VAGUE_REPLIES := ["Not on here.", "Can't get into it.", "I'll message you.", "They know who they are.", "Thank you hun.",
	"Not on here, I said.", "Will explain later."]
const NOSY := ["Ok but what happened though", "Is this about {who_first}", "Did something happen at bingo", "Is it the truck thing again",
	"Is this about the casserole", "Was it Garth"]

# --- the dating group -----------------------------------------------------------------------

const MAN_DESCS := ["drives a lifted black truck", "works \"in sales\"", "has a boat but no house", "has a goatee and an opinion about the bridge",
	"is \"between places\"", "lives in Stratford but says Charlottetown", "has eleven pictures with fish", "says he's 6'1\"",
	"calls his truck \"her\"", "is \"getting into crypto\""]
const MAN_CLAIMS := ["Says he's not looking for anything serious, then asked to meet my mother.",
	"Says he's single. His profile says \"it's complicated\" since 2017.", "Told me he owns a business. It's a pressure washer.",
	"Says his ex is crazy. I've met his ex. She's lovely. She warned me.", "Says he \"doesn't do drama.\" Has been on here six times.",
	"Says he's new to the Island. His grandmother lives on my street.", "Asked me to split the bill. At his cousin's restaurant. Where he eats free."]
const DATING_COMMENTS := ["RUN", "Which {man}", "There's forty of them", "Oh honey", "2019 for me", "Last summer for me", "He's my cousin. Run.",
	"Is it the one with the boat", "Inbox me hun", "Commenting for updates", ".", "Not him again", "He messaged me this morning",
	"He messaged ME this morning", "Is his mother Bernice", "That's my ex. He has my air fryer.", "Following"]

## Dating threads that turn into a reunion.
const DATING_TANGENTS := [
	[["Anonymous", "Which {man}"], ["Anonymous", "There's forty of them", true], ["Anonymous", "Lifted truck {man}", true], ["Anonymous", "Oh THAT {man}", true]],
	[["Anonymous", "2019 for me"], ["Anonymous", "2021 for me", true], ["Anonymous", "Last week for me", true], ["Anonymous", "Should we start a group chat", true]],
	[["Anonymous", "Is he Bernice's grandson"], ["Anonymous", "Don't bring Bernice into this", true], ["Anonymous", "Bernice is in this group", true]],
	[["Anonymous", "He has my air fryer"], ["Anonymous", "Not the air fryer again", true]],
	[["Anonymous", "That's my brother"], ["Anonymous", "Sorry hun", true], ["Anonymous", "Don't be. Run.", true]],
	[["Anonymous", "I'm his wife"], ["Anonymous", "Oh no", true], ["Anonymous", "Keep him", true], ["Anonymous", "No thank you", true]],
	[["Anonymous", "Post his picture"], ["Admin", "No faces please.", true], ["Anonymous", "Inbox it to me then hun", true], ["Anonymous", "Me too", true], ["Anonymous", "Me too", true]],
	[["Anonymous", "He was at Wyoming's Saturday with Brittany"], ["Anonymous", "WHICH Brittany", true]],
]

# --- ChipIns ----------------------------------------------------------------------------------

const CHIPIN_NEEDS := [["New Phone (Dropped It at the Legion)", 900], ["Snowblower Fund", 1500], ["Concert Tickets (Sold Out, Need Resale)", 650],
	["Hot Tub Repair", 3200], ["Trip to Florida to Recover From Stress", 4000], ["Our Wedding (Again)", 12000],
	["Lawyer for the Fence Thing", 5000], ["Gaming Chair (Back Pain)", 700], ["Tattoo Cover-Up (It Says Kyle)", 450],
	["New Tires After the Bernard Incident", 800], ["Boat Insurance (Retroactive)", 2600], ["Parking Tickets, All of Them", 1100]]
const CHIPIN_TEXTS := ["Times are tough and every bit helps.", "I never ask for anything. This is the fifth time I've asked.",
	"Not getting into how this happened. Everybody knows how.", "Even $5 helps. $500 helps more.",
	"If you can't give, please share. If you can give, please give."]
const CHIPIN_COMMENTS := ["Shared!", "Can't give but sharing", "Is this a real one", "Didn't you just do one of these", "Sent $5 hun",
	"Get a job", "Get a second job", "Third one this month", "What happened to the last ChipIn", "Praying", "Saw you at the Legion Friday"]

# --- threads that wander off topic (added to any post) -----------------------------------------

const GENERAL_COMMENTS := ["Following", ".", "Commenting for updates", "PM me hun", "My cousin does that, PM me", "Google it",
	"Same thing happened to me", "This is why I moved to Alberta", "Island Electric strikes again", "Welcome to the Island",
	"Who's your father?", "Call the province", "Lol", "Wow", "This is the Island now", "Story of my life"]
const TANGENTS := [
	[["Wade E.", "This is what you get for voting Blue"], ["Brent S.", "Not everything is politics Wade", true], ["Wade E.", "This is", true]],
	[["Gord W.", "Ya but where are you from"], ["Ana C.", "HERE Gord", true], ["Gord W.", "Before that", true]],
	[["Lorne P.", "."], ["Tanner O.", "Lorne why do you always just put a period", true], ["Lorne P.", "so i get updates", true]],
	[["Kayleigh J.", "I think I dated him"], ["Heather D.", "Of course you did Kayleigh", true]],
	[["Garth R.", "Some of us landlords are struggling too"], ["Siobhan L.", "GARTH", true]],
	[["Admin", "Keep it civil please."], ["Wanda F.", "I AM being civil", true], ["Wanda F.", "IN CAPITALS", true]],
	[["Colby A.", "We all know who posted this"], ["Paulette G.", "It wasn't me", true], ["Colby A.", "Didn't say it was Paulette", true]],
	[["Marlene T.", "My son can fix that, PM me"], ["Wanda F.", "No he can't Marlene", true]],
	[["Dale S. (Orange Party)", "The Orange Party has a plan for this!"], ["Gord W.", "Nobody asked Dale", true]],
	[["Bernice H.", "Who's your father?"], ["Priya N.", "Why does that matter", true], ["Bernice H.", "Just so I know who to call", true]],
	[["Heather D.", "This is why we need the Greens"], ["Gord W.", "Heather you ARE the Greens", true]],
	[["Clayton V.", "My brother-in-law can do that for cash"], ["Doug R.", "Your brother-in-law is why this happened Clayton", true]],
	[["Brent S.", "what colour"], ["Heather D.", "WHY Brent", true], ["Brent S.", "no reason", true]],
	[["Reggie B.", "Was this the same day the boat sank"], ["Clayton V.", "Not now Reggie", true]],
]


## One new post: {group, by?, text, likes, comments, closed?} or a ChipIn
## {chipin: true, by, title, raised, goal, text, comments}. Nothing in
## `used` (texts already made) comes out again.
static func post(rng: RandomNumberGenerator, used: Dictionary) -> Dictionary:
	for _try in 12:
		var p := _make(rng)
		var key := str(p.get("title", "")) + str(p.get("text", ""))
		if not used.has(key):
			used[key] = true
			return p
	return _make(rng)


static func _make(rng: RandomNumberGenerator) -> Dictionary:
	var v := {"street": _pick(rng, STREETS), "place": _pick(rng, PLACES), "man": _pick(rng, MEN), "who": _pick(rng, CAST)}
	v["who_first"] = str(v["who"]).split(" ")[0]
	var kind := _weighted(rng, {"rant": 3.0, "rave": 1.2, "question": 2.0, "pet": 0.8, "vague": 2.6, "dating": 2.2, "chipin": 1.4})
	match kind:
		"rant":
			var text := ""
			if rng.randf() < 0.55:
				text = "RANT: To %s that %s %s. %s" % [_pick(rng, DRIVERS), _pick(rng, SINS), _pick(rng, WHENS), _pick(rng, RANT_KICKERS)]
			else:
				text = _pick(rng, GENERAL_RANTS)
			return _group_post(rng, "rants", text, v, GENERAL_COMMENTS, 0.7)
		"rave":
			var text := "RAVE: To the young man at %s who %s. %s" % [_pick(rng, PLACES), _pick(rng, RAVE_ACTS), _pick(rng, RAVE_KICKERS)]
			return _group_post(rng, "rants", text, v, ["Love this", "Island kindness", "Who was it??", "My nephew! I bet it was my nephew",
				"Is he single though", "This is the Island I know"], 0.4)
		"question":
			return _group_post(rng, "rants", _pick(rng, QUESTIONS), v, GENERAL_COMMENTS, 0.6)
		"pet":
			var text := "FOUND: %s %s. %s" % [_pick(rng, PETS), _pick(rng, PET_WHERE), _pick(rng, PET_NOTES)]
			return _group_post(rng, "rants", text, v, ["Is there a reward", "That's my neighbour's!", "Check the Megastore",
				"He's been at my place too", "Keep him", "Post a picture", "Commenting for updates"], 0.3)
		"vague":
			return _vague(rng, v)
		"dating":
			var text := "Anyone know a {man}? He %s. %s" % [_pick(rng, MAN_DESCS), _pick(rng, MAN_CLAIMS)]
			return _group_post(rng, "dating", text, v, DATING_COMMENTS, 0.75, true)
		_:
			return _chipin(rng, v)


static func _group_post(rng: RandomNumberGenerator, group: String, text: String, v: Dictionary, pool: Array,
		tangent_chance: float, anonymous := false) -> Dictionary:
	var comments: Array = []
	var lines := _some(rng, pool, rng.randi_range(3, 5) if anonymous else rng.randi_range(2, 4))
	var names := _some(rng, CAST, lines.size())
	for i in lines.size():
		comments.append(["Anonymous" if anonymous else str(names[i]), _fill(str(lines[i]), v)])
	var tangents: Array = DATING_TANGENTS if anonymous else TANGENTS
	if rng.randf() < tangent_chance:
		for c: Array in _one(rng, tangents):
			comments.append([c[0], _fill(str(c[1]), v), c.size() > 2 and bool(c[2])])
	return {"group": group, "text": _fill(text, v), "likes": rng.randi_range(8, 420), "comments": comments,
		"closed": rng.randf() < 0.12 and comments.size() > 4}


static func _vague(rng: RandomNumberGenerator, v: Dictionary) -> Dictionary:
	var by := _pick(rng, CAST)
	while v["who"] == by:
		v["who"] = _pick(rng, CAST)
	var parts: Array[String] = [_pick(rng, VAGUE_OPENERS)]
	for m in _some(rng, VAGUE_MIDDLES, rng.randi_range(1, 2)):
		parts.append(str(m))
	var close := _pick(rng, VAGUE_CLOSERS)
	if close != "":
		parts.append(close)
	var comments: Array = []
	var names := _some(rng, CAST.filter(func(n: String) -> bool: return n != by), 6)
	var lines := _some(rng, VAGUE_COMMENTS, rng.randi_range(3, 5))
	for i in lines.size():
		comments.append([str(names[i]), str(lines[i])])
	comments.append([by, _pick(rng, VAGUE_REPLIES), true])
	comments.append([str(names[5]), _fill(_pick(rng, NOSY), v), true])
	comments.append([by, "Not on here.", true])
	if rng.randf() < 0.3:
		comments.append(["Lorne P.", "."])
	return {"group": "wall", "by": by, "text": " ".join(parts), "likes": rng.randi_range(30, 260), "comments": comments}


static func _chipin(rng: RandomNumberGenerator, v: Dictionary) -> Dictionary:
	var need: Array = _one(rng, CHIPIN_NEEDS)
	var by := _pick(rng, CAST)
	var first := by.split(" ")[0]
	var goal := int(need[1])
	var comments: Array = []
	var lines := _some(rng, CHIPIN_COMMENTS, rng.randi_range(2, 3))
	var names := _some(rng, CAST.filter(func(n: String) -> bool: return n != by), lines.size())
	for i in lines.size():
		comments.append([str(names[i]), str(lines[i])])
	return {"chipin": true, "by": by, "title": "%s's %s" % [first, need[0]], "goal": goal,
		"raised": int(goal * rng.randf_range(0.0, 0.2)) if rng.randf() < 0.85 else int(goal * rng.randf_range(1.0, 1.6)),
		"text": _pick(rng, CHIPIN_TEXTS), "comments": comments}


static func _one(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi() % list.size()]


static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return str(list[rng.randi() % list.size()])


## `n` different items from `list`, in a random order.
static func _some(rng: RandomNumberGenerator, list: Array, n: int) -> Array:
	var pool := list.duplicate()
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return out


static func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k: String in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return str(weights.keys()[0])


static func _fill(text: String, v: Dictionary) -> String:
	for k: String in v:
		text = text.replace("{%s}" % k, str(v[k]))
	return text

class_name PedestrianLines
extends RefCounted
## What people on foot think and say (Pedestrian, RideFares). Thoughts
## float over their heads now and then while they walk; the rest are said
## out loud, in reaction to something.
##
## The voice is docs/radio.md's: dry, specific, grown-up worries said with
## a straight face (rent, the doctor list, the power bill, the town
## knowing your business by supper). The joke's on prices, landlords, the
## province and the people with power, never on the person thinking it.
## Some lines call back to the ads (Countess Auto, Breezy Home, the
## interlock, the doctor list), so the town feels like one place. No real
## people or businesses; the world brands from the README's table.
##
## pick() avoids anything said lately, across everyone, so a walk down
## Queen Street doesn't hear the same line twice. NOTICE, BUS_*,
## PAIR_CHATS, RECOGNISE and CALLING are for the people-on-foot and
## transit work (StreetEvents, the bus stops, witnesses).

## Thoughts anyone might have, walking round Charlatown.
const ANYONE := [
	"Did I leave the stove on?", "Is it going to rain? It's going to rain.", "What was I going in for?",
	"Who parks like that?", "Wind's off the harbour today.", "Forgot my bags. Again.", "Smells like fries.",
	"Was that my cousin? Everyone's my cousin.", "Lovely day. Won't last.",
	"Rent went up again. The apartment didn't get any bigger.", "Power bill came. I'll open it Friday.",
	"Still on the doctor list. Year four.", "Eight dollars for a coffee. When did that happen?",
	"Saw my ex at the Megastore. Hid in frozen foods.", "That's the third Ontario plate on this street.",
	"If I wave, that's a whole conversation.", "Don't make eye contact. You'll be here an hour.",
	"Pretend you're on the phone.", "Every house on this street is an Airbnb now.",
	"Gas went up six cents overnight. Overnight.", "They made the chip bag bigger and the chips smaller.",
	"Paved that road last year. Dug it up this year.", "Same orange cones. Since July.",
	"Went in for a bolt. Came out with a tarp.", "Three forty-nine a week for a toaster. Forever.",
	"Is that a new premier? I can't keep up.", "Wearing two sweaters. That's the heating plan.",
	"My landlord lives in Toronto. Has never seen the place.", "Nothing's open after nine. Nothing.",
	"Three Tim Hardly's on one street. Still a line.", "Somebody left their keys in it. Classic.",
	"That's the Gallants' car. They're not at work.", "Red mud on the new shoes. Of course.",
	"If I see one more 'luxury condos' sign.", "Who's that? Not from here. Look at the shoes.",
	"Somebody's already posted about this, I bet.", "That'll be on Facebook in ten minutes.",
	"Groceries were sixty dollars. It was one bag.", "Two years less a day. For what, though?",
	"Bridge toll's only one way. Think about that.", "Is that pothole new, or just deeper?",
	"I could move out west. Then I'd be out west.", "Cheaper to fly to Florida than to Halifax.",
	"Said I'd only stay a year. That was 1998.", "Everybody knows everybody. Nobody tells me anything.",
	"Paid parking on a Sunday. Who decided that?", "New restaurant. Give it six months.",
	"Another For Sale sign. Another Ontario plate in the driveway.", "Insurance went up. I didn't do anything. That's why, apparently.",
	"A coffee and a muffin. I'll need financing.", "That used to be a bank. Now it's condos. Of course it's condos.",
	"Nobody's lived in that house since it sold.", "Could I afford to live where I grew up? Next thought.",
	"Three years on the list. Got a pamphlet.", "Should check who died. Just in case.",
]

## Thoughts by kind of person (Pedestrian.kind).
const BY_KIND := {
	"commuter": [
		"Late. Late. Late.", "That meeting could've been an email.", "Forty unread. Wonderful.",
		"A meeting about having fewer meetings.", "Got a raise. Rent heard about it.",
		"Parking ticket. Ten minutes over. They were waiting.", "Two hundred a month to park downtown.",
		"Boss said 'we're a family' again. Bad sign.", "Bus app says 'soon.' It's said that since nine.",
		"Hit every red light on University.", "My commute is eleven minutes. I'm complaining anyway.",
		"If I stay late once, they'll expect it.", "Government job. Pension. Don't rock the boat.",
		"Annual review: 'meets expectations.' Barely.", "Sat in the Tim's line twenty minutes. Worth it. Wasn't.",
		"Did I lock the car? Nobody locks the car.", "Working from home tomorrow. Working from the car today.",
		"Who replies-all to a lunch order?", "The new hire's from Ontario. Bought a house in a week.",
		"Five o'clock and the Arterial's backed up. Six cars.", "Thirty emails. All of them 'per my last email.'",
	],
	"tourist": [
		"Is the dirt supposed to be red?", "Take a picture, Gary.", "We should move here.",
		"Honey, that house is only six hundred thousand!", "Where's the farmhouse from the book?",
		"Everyone's so friendly. Why are they staring?", "Why's everybody waving at me?",
		"Is everything closed? It's seven-thirty.", "Lobster roll was thirty-two dollars. Worth it?",
		"Is that the real one or a gift shop?", "Gary, stop saying 'quaint.'", "Bought the straw hat. No regrets.",
		"Our Airbnb host lives in Mississauga.", "They said Island time. I thought it was a joke.",
		"Where do the locals eat? Somewhere else, apparently.", "Is it rude to ask where the beach is?",
		"I think we've passed this church four times.", "Everyone keeps asking who my father is.",
		"Gary bought a lobster trap. For the wall.",
	],
	"senior": [
		"In my day this was all potato fields.", "Gas was a quarter once, you know.",
		"Read the obituaries. Nobody I know. Good day.", "Three funerals this week. Lovely sandwiches at two of them.",
		"Bingo tonight. Marjorie cheats.", "I'll tell Doris. She'll have it on Facebook before I'm home.",
		"Paid off the house in '79. Eleven thousand dollars.", "My grandson's thirty-eight. Still downstairs.",
		"Nine hours in Emergency. Brought a book. Finished it.", "My doctor retired. He was eighty-one.",
		"Mind the ice. There's no ice. Mind it anyway.", "These new houses. Cardboard and hope.",
		"Voted the same way fifty years. They never noticed.", "Pension went up two dollars. Power went up forty.",
		"I don't need a phone. I have Doris.", "They tore down the good one and kept the ugly one.",
		"Who's that one belong to? Not a MacDonald. Too tall.",
		"Doctor I don't have told me to walk more. So I'm walking.",
	],
	"jogger": [
		"Breathe. Breathe.", "Hill. Why is there a hill.", "Just one more block.",
		"Someone will post this. Suck it in.", "Running from my problems. They're faster.",
		"Five k. That's two doughnuts, earned.", "Wave at the other runner. We're a team now.",
		"My watch says I'm dying. My watch is dramatic.", "Signed up for the marathon in a weak moment.",
		"Don't stop at the lights. Jog on the spot. Look serious.", "Personal best. Nobody saw. Typical.",
		"Lap two. Same Tim's line. Same people in it.",
	],
	"teen": [
		"No signal.", "So bored.", "Literally nothing to do here.", "Should've got fries.",
		"Moving to Toronto. Can't afford Toronto.", "Whole school will know by lunch.",
		"Third shift at Tim's this week. I smell like Hardly Bits.", "Minimum wage. Maximum customer.",
		"Saw my teacher at the Megastore. Horrifying.", "Mom and Dad met in grade nine. Here. Gross.",
		"Saving for a car. And a house. Ha.", "Grandma's on Facebook, so I'm not.",
		"Is there a bus? There's never a bus.", "Someone's filming. Act natural.",
		"Everyone in my class is my cousin. Dating is a nightmare.",
		"Applied to ten jobs. Got one. It's my uncle's.",
	],
	"stroller": [
		"No rush.", "Might stop in for a tea.", "Window shopping. Heavy on the window.",
		"Every shop here used to be a different shop.", "That's where the Zellers was.",
		"Not buying anything. Just looking. Okay, one thing.", "Gulls are bolder this year.",
		"Lovely day for it. For what, who knows.", "Nice to be out. Nice to go home, too.",
		"Might pop into the Megastore. For nothing. Just to look.",
	],
}

## Two people who stopped to chat: lines said in turn, starting with the
## one who stopped first (two to four lines).
const CHATS := [
	["Some weather, eh?", "Can't complain.", "You will, though.", "Oh, I will."],
	["How's your mother?", "Oh, she's grand.", "Get a doctor yet?", "Year six."],
	["Who's your father?", "Bernie MacDonald.", "Which one?", "The other one."],
	["Haven't seen you in ages!", "I was in Summerside.", "For how long?", "An afternoon."],
	["Did you hear about the Gallants?", "No! Tell me.", "Can't. It's not on Facebook yet."],
	["Off to the market?", "If I can find parking.", "There's no parking.", "There's never parking."],
	["You're looking well!", "I'm not.", "No, you're not."],
	["Saw your truck at Countess Auto.", "Needed one bolt.", "Get it?", "Got a winch."],
	["Did you sell the house?", "Over asking. To Ontario.", "Where'll you live?", "Ontario."],
	["How's the new place?", "Cozy.", "Cozy how?", "I can reach the stove from bed."],
	["Power bill come?", "Didn't open it.", "Smart."],
	["Who's premier now?", "Same as last month.", "No, there's a newer one."],
	["Going to the funeral?", "Which one?", "Tuesday's.", "I'm doing Tuesday and Thursday."],
	["They're paving Grafton again.", "Again?", "Different cousin."],
	["Working much?", "Three jobs.", "Good for you!", "Is it, though?"],
	["Kids moved out?", "One did.", "Good for him!", "He's back."],
	["Lovely day!", "Won't last."],
	["Saw you on Rants & Raves.", "Wasn't me.", "Blue Halfton?", "...Was me."],
	["We should get together sometime!", "We should!", "Christmas, maybe.", "Which one?"],
	["Get a doctor yet?", "Got a video call from one.", "Where's she?", "Alberta."],
	["Your daughter still out west?", "Calgary.", "Coming home?", "Can't afford to."],
	["Did you get the job?", "His nephew got it.", "Whose nephew?", "Everybody's."],
	["Is that new, the coat?", "Breezy Home.", "How much?", "Ask me in four years."],
	["Heard you got a new car.", "Just financing it.", "For how long?", "Till it's a used car."],
	["You coming to the meeting?", "What's it about?", "The last meeting.", "Then no."],
	["Busy day?", "Run off my feet.", "Doing what?", "Waiting for a call back."],
	["Didn't know you were back!", "Neither did I. Rent."],
	["Heard Gord lost his licence.", "Again?", "He's on the mower now.", "He'll lose that too."],
]

## A car coming at them.
const DODGE := [
	"Hey! Watch it!", "I'm walking here!", "Sidewalk, buddy! Side. Walk.", "Whoa!", "Are you nuts?!",
	"You'll be on Facebook for that!", "I've got your plate!", "Easy! I've got no doctor!",
	"I'm not dying in front of a Tim's!", "Learn to drive! Or leave!", "That was close!", "I know that truck!",
]
## Painted.
const PAINTED := [
	"My good coat!", "That's going in the wash.", "Hey! I'm still paying for this jacket!", "Not the face!",
	"Oh, that's going on Facebook.", "I'm calling the police. They won't come, but I'm calling.",
	"Really? On a Tuesday?", "Ow! Who raised you?", "That's dry-clean only!", "I'm on my lunch!",
	"There's no doctor for this, you know.",
]
## Paint landing near them.
const FLEE := [
	"Run!", "Paint! Paint!", "Not again!", "Get down!", "Not the good shoes!", "Every man for himself!",
	"I'm too old for this!", "Somebody film this!", "Nope. Nope.",
]
## Someone aiming a marker at them.
const AIMED_AT := [
	"Don't shoot!", "Easy now!", "I'm just walking!", "Put that down!", "I know your father!",
	"I'm on my lunch!", "Do it and I'll tell everyone.", "Not the coat. Okay? Not the coat.", "Whoa, whoa.",
]
## The player walking into them.
const BUMPED := [
	"Sorry!", "Pardon me.", "Oop, sorry.", "After you.", "Sorry! Why am I sorry?",
	"Sorry. My fault. It was yours.", "Excuse me, dear.",
]
## Sirens about.
const SIRENS := [
	"Somebody's in trouble.", "Not the FIP again.", "Sirens. On a weekday.", "What now?",
	"That'll be on Rants & Raves tonight.", "There goes the overtime.", "That's four point two million right there.",
	"Bet it's Darren's boy.", "Police are out. Must be a slow day for paperwork.",
]

## Something happening in the street (StreetEvents kinds): one onlooker
## says one. Kept few: these come up a lot.
const NOTICE := {
	"crash": ["That'll be on Kinbook before the tow gets here.", "Insurance is going up. Everyone's.",
		"Third one at this corner since lunch.", "Somebody's calling their cousin who does bodywork.",
		"Oof. Everyone okay? Good. Idiot."],
	"tow": ["There goes someone's afternoon. And ninety-five dollars.", "Faster than the ambulance, that tow truck.",
		"Plus the after-hours fee. It's two in the afternoon.", "They always come for the money."],
	"stalled": ["Just left it there. Island parking.", "Somebody's having a day.", "That's not a parking spot. Is it now?"],
	"painted": ["Well. It's a colour.", "That won't come off at the car wash.", "Must be a Tuesday.", "Somebody's going in the group for that."],
	"arrest": ["Out by supper.", "Two years less a day. Less a day.", "Knew it. I knew it.", "Somebody's mother's getting a call."],
}

## Waiting at a bus stop (thoughts).
const BUS_WAIT := ["Every twenty minutes, they said. Which twenty?", "Is that it? No. A truck.",
	"The app says 'soon.' The app's a liar.", "Exact change. Nobody has exact change.",
	"Bus shelter's got no walls. Just the idea of a shelter.", "Forty minutes. Could've walked to Stratford."]
## The bus left without them, or never came.
const BUS_MISSED := ["Wait! ...Never mind.", "He saw me. He saw me and he went.", "Of course."]
const BUS_GAVE_UP := ["Forget it. I'll walk.", "Faster to walk. Always was."]

## Two walking together, now and then: [one says, the other answers].
const PAIR_CHATS := [["Where do you want to eat?", "Somewhere we can afford. So, home."],
	["Did you lock the door?", "Nobody locks the door."], ["We should do this more.", "We say that every time."],
	["Remind me to get milk.", "You'll forget anyway."], ["Is that the Gallants?", "Don't look. They'll stop."],
	["Look at that sky.", "Rain later, for sure."], ["Your mother called.", "Which one?"],
	["Should we look at houses?", "Look, sure."], ["Is that your ex?", "Keep walking."],
	["Slow down a bit.", "You walk like you're late for bingo."]]

## Saw the player paint someone, then sees them again up close.
const RECOGNISE := ["That's them. The paint one.", "Don't look. Keep walking.", "Oh no. It's them again.", "I'm posting this."]
## Calling it in (said on the phone).
const CALLING := ["Hello, police? There's a person with paint. Yes. Paint.", "I'd like to report a painting. Of a person.",
	"They went toward the Tim's. Well, every way's toward a Tim's.", "Yes, I'll hold. Again."]

## Hailing a ride.
const HAIL := [
	"Need a ride! I'll pay ya!", "Hey! Ride? I'll pay!", "Over here! I'll pay ya!", "Taxi! ...ish? I'll pay!",
	"Can you drive me? Cash!", "Need a lift, bud! I'll pay!", "There's never a cab! You'll do!",
]
## Getting in: "%s" is the street.
const BOARD := [
	"Thanks! %s, please.", "%s. And step on it!", "%s, please. I'm in no rush. Well, a bit.",
	"%s. Don't take University, it's a mess.", "%s. You know it? Where the bank used to be.",
	"%s. If anyone asks, you never saw me.",
]
## Riding along.
const RIDE_FAST := [
	"Easy! I've got eggs!", "This isn't the Gold Cup!", "Slow down!", "I don't have a doctor!",
	"I'd like to see my grandchildren!", "My heart! I'm on a list for that!",
]
const RIDE_CRASH := [
	"My neck!", "Was that a curb?!", "Ow!", "I felt that in my teeth.", "That's going on Rants & Raves.",
	"Do you have a licence? A real one?",
]
const RIDE_SLOW := [
	"Are we lost?", "I could've walked by now.", "Take a left. No, right. The other right.",
	"You're not from here, are you?", "My grandmother drives faster. She's ninety.",
]
const RIDE_CHAT := [
	"Nice car.", "You from here? Who's your father?", "Mind if I open the window?", "Busy night?",
	"Lost my licence. Got a mower. Long story.", "Cheaper than parking downtown, this.", "I'll leave you a good review.",
]
const RIDE_POLICE := [
	"Why are the police behind us?!", "I didn't sign up for this!", "Let me out!", "I have a job interview!",
	"If this goes on Facebook, I wasn't here.",
]
## Paying.
const PAID_GOOD := ["Thanks! Keep the change.", "Smooth ride. Here you go.", "Perfect. Thank you!",
	"Lovely. I'll tell people about you."]
const PAID_OK := ["Thanks, I guess.", "Here. We made it.", "That'll do.", "Here. Put it toward tires."]
const PAID_BAD := ["Never again.", "Here. Spend it on driving lessons.", "My chiropractor thanks you.",
	"Here. I'm posting about this."]
## Getting out without paying.
const BAIL := ["I'll walk from here.", "Forget it!", "This is where I get off.", "I'll get my cousin to come get me."]

## Lines said lately, by anyone: pick() tries to avoid them.
const RECENT := 40
static var _recent: Array[String] = []


static func pick(rng: RandomNumberGenerator, lines: Array) -> String:
	var line := ""
	for _i in 8:
		line = str(lines[rng.randi() % lines.size()])
		if not line in _recent:
			break
	_recent.append(line)
	if _recent.size() > RECENT:
		_recent.pop_front()
	return line


static func thought(rng: RandomNumberGenerator, kind: String) -> String:
	var own: Array = BY_KIND.get(kind, [])
	if not own.is_empty() and rng.randf() < 0.55:
		return pick(rng, own)
	return pick(rng, ANYONE)


## An [opener, reply] pair from `pairs` (PAIR_CHATS), not one heard lately.
static func pick_pair(rng: RandomNumberGenerator, pairs: Array) -> Array:
	var pr: Array = pairs[rng.randi() % pairs.size()]
	for _i in 8:
		if not str(pr[0]) in _recent:
			break
		pr = pairs[rng.randi() % pairs.size()]
	_recent.append(str(pr[0]))
	if _recent.size() > RECENT:
		_recent.pop_front()
	return pr


## A chat for two people, not one heard lately.
static func chat(rng: RandomNumberGenerator) -> Array:
	var lines: Array = CHATS[0]
	for _i in 8:
		lines = CHATS[rng.randi() % CHATS.size()]
		if not str(lines[0]) in _recent:
			break
	_recent.append(str(lines[0]))
	if _recent.size() > RECENT:
		_recent.pop_front()
	return lines

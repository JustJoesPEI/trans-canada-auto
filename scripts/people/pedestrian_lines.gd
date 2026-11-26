class_name PedestrianLines
extends RefCounted
## What people on foot think and say (Pedestrian, RideFares). Thoughts
## float over their heads now and then while they walk; the rest are said
## out loud, in reaction to something.
##
## No line comes round again soon: `pick` skips the last RECENT lines shown
## anywhere in town, so the same joke isn't heard twice in a row.

## How many of the latest lines `pick` won't use again.
const RECENT := 40
static var _recent: Array[String] = []

## Thoughts anyone might have, walking round Charlatown in late fall.
const ANYONE := ["Did I leave the stove on?", "Potatoes for supper again.",
	"Is it going to rain? It's going to rain.", "I should call my mother.", "Need milk. And bread. And milk.",
	"That gull's been following me.", "Coffee. I need coffee.", "Should've worn the warmer coat.",
	"Was that my cousin? Everyone's my cousin.", "Chowder or mussels...", "Wind's off the harbour today.",
	"Forgot my bags. Again.", "Who parks like that?", "My feet are killing me.", "Love this town.",
	"What was I going in for?", "Smells like fries.", "Bit nippy.", "Three more blocks."]

## Thoughts by kind of person (Pedestrian.kind).
const BY_KIND := {
	"commuter": ["Late. Late. Late.", "That meeting could've been an email.", "Is the bus coming or not?",
		"Who replies-all to a lunch order?", "Forty unread. Wonderful.", "Did I lock the car?"],
	"tourist": ["Which way's the waterfront?", "Everyone's so friendly!", "Is the dirt supposed to be red?",
		"Where do you get a lobster supper?", "Take a picture, Gary.", "We should move here.",
		"Is that the real one or a gift shop?"],
	"senior": ["In my day this was all potato fields.", "Too fast, these young people.", "Bingo tonight.",
		"Gas was a quarter once, you know.", "Mind the ice. There's no ice. Mind it anyway.",
		"I'll tell Doris about this."],
	"jogger": ["Breathe. Breathe.", "Just one more block.", "Why do I do this to myself?", "Personal best.",
		"Hill. Why is there a hill.", "Hydrate."],
	"teen": ["No signal.", "So bored.", "Is it Friday yet?", "Mom's gonna kill me.", "Literally nothing to do here.",
		"Should've got fries."],
	"stroller": ["Lovely day for it.", "Might stop in for a tea.", "Wonder what's on sale.",
		"Those clouds look like a lobster.", "No rush."],
}

## Said to someone they stopped to chat with: [opener, reply].
const CHATS := [["Some weather, eh?", "Can't complain."], ["How's your mother?", "Oh, she's grand."],
	["Who's your father?", "You know him! Bernie's boy."], ["Busy day?", "Run off my feet."],
	["Supposed to rain later.", "It always is."], ["Did you hear about the Gallants?", "No! Tell me."],
	["Haven't seen you in ages!", "I was in Summerside."], ["Off to the market?", "If I can find parking."]]

## A car coming at them.
const DODGE := ["Hey! Watch it!", "Sidewalk's for walking!", "Whoa!", "Are you nuts?!", "I'm walking here!",
	"Learn to drive!", "That was close!"]
## Painted.
const PAINTED := ["My good coat!", "Ow! Paint?!", "That's going in the wash.", "Really?!", "Hey! I just bought this!",
	"Not the face!"]
## Paint landing near them.
const FLEE := ["Run!", "Not again!", "Paint! Paint!", "Get down!", "Whoa!", "Are you nuts?!"]
## Someone aiming a marker at them.
const AIMED_AT := ["Don't shoot!", "Easy now!", "I'm just walking!", "Put that down!", "Whoa, whoa."]
## The player walking into them.
const BUMPED := ["Sorry!", "Pardon me.", "Oop, sorry.", "Excuse me.", "After you."]
## Sirens about.
const SIRENS := ["Somebody's in trouble.", "Not the FIP again.", "Sirens. On a weekday.", "What now?"]

## Seen in the street (StreetEvents), by kind: said by one onlooker now
## and then, most just look.
const NOTICE := {
	"crash": ["Oof. Everyone okay?", "That's going to cost somebody.", "Saw that coming.", "Somebody call a tow.",
		"Right in the middle of the road, too.", "Insurance is going to love that."],
	"tow": ["There goes someone's afternoon.", "Should've paid the meter.", "Bet that's not cheap.",
		"They don't waste any time, do they?"],
	"stalled": ["Somebody's having a day.", "Just left it there?", "That's not a parking spot."],
	"painted": ["Is that... paint?", "That won't come off easy.", "Who does that?", "Well, it's a colour."],
	"arrest": ["Knew it.", "Oh, this is good.", "Wonder what they did.", "Not something you see every day."],
}

## Waiting at a bus stop (thoughts).
const BUS_WAIT := ["Should be here any minute.", "Every twenty minutes, they said.", "Hope there's a seat.",
	"Is that it? No, that's a truck.", "Did I miss it?", "Got my change ready."]
## The bus left without them, or never came.
const BUS_MISSED := ["Wait! ...never mind.", "Next one, then.", "Of course."]
const BUS_GAVE_UP := ["Forget it. I'll walk.", "Walking's faster anyway."]

## Two walking together, now and then: [one says, the other answers].
const PAIR_CHATS := [["Where do you want to eat?", "I don't mind. You pick."], ["Did you lock the door?", "...I think so."],
	["We should do this more.", "We say that every time."], ["Is it this way?", "Pretty sure, yeah."],
	["Remind me to get milk.", "You'll forget anyway."], ["Slow down a bit.", "Sorry, sorry."],
	["Look at that sky.", "Rain later, for sure."]]

## Saw the player paint someone, then sees them again up close.
const RECOGNISE := ["That's them!", "That's the one with the paint!", "Don't look. Keep walking.", "Oh no. It's them again."]
## Calling it in (said on the phone).
const CALLING := ["Hello, police? There's someone with paint...", "Yes, I want to report a painting. A person.",
	"They went that way! I think."]

## Hailing a ride.
const HAIL := ["Need a ride! I'll pay ya!", "Hey! Ride? I'll pay!", "Over here! I'll pay ya!",
	"Taxi! ...ish? I'll pay!", "Can you drive me? Cash!", "Need a lift, bud! I'll pay!"]
## Getting in: "%s" is the street.
const BOARD := ["Thanks! %s, please.", "%s. And step on it!", "Oh, lovely. %s, if you would.",
	"%s, please. I'm in no rush. Well, a bit."]
## Riding along.
const RIDE_FAST := ["Easy! I've got eggs!", "This isn't the Gold Cup!", "Slow down!", "My heart!"]
const RIDE_CRASH := ["My neck!", "Was that a curb?!", "Ow!", "Do you have a licence?", "I felt that in my teeth."]
const RIDE_SLOW := ["Are we lost?", "You know the way, right?", "I could've walked by now.", "Take a left. No, right."]
const RIDE_CHAT := ["Nice car.", "Been driving long?", "Mind if I open the window?", "You from here?",
	"I'll leave you a good review."]
const RIDE_POLICE := ["Why are the police behind us?!", "I didn't sign up for this!", "Let me out!"]
## Paying.
const PAID_GOOD := ["Thanks! Keep the change.", "Smooth ride. Here you go.", "Perfect. Thank you!"]
const PAID_OK := ["Thanks, I guess.", "Here. We made it.", "That'll do."]
const PAID_BAD := ["Never again.", "Here. Don't spend it on driving lessons.", "My chiropractor thanks you."]
## Getting out without paying.
const BAIL := ["I'll walk from here.", "Forget it!", "This is where I get off."]


static func pick(rng: RandomNumberGenerator, lines: Array) -> String:
	var line := str(lines[rng.randi() % lines.size()])
	for attempt in 6:
		if not _recent.has(line):
			break
		line = str(lines[rng.randi() % lines.size()])
	_recent.append(line)
	if _recent.size() > RECENT:
		_recent.pop_front()
	return line


## An [opener, reply] pair from `pairs`, not one heard lately.
static func pick_pair(rng: RandomNumberGenerator, pairs: Array) -> Array:
	var pr: Array = pairs[rng.randi() % pairs.size()]
	for attempt in 6:
		if not _recent.has(str(pr[0])):
			break
		pr = pairs[rng.randi() % pairs.size()]
	_recent.append(str(pr[0]))
	if _recent.size() > RECENT:
		_recent.pop_front()
	return pr


static func thought(rng: RandomNumberGenerator, kind: String) -> String:
	var own: Array = BY_KIND.get(kind, [])
	if not own.is_empty() and rng.randf() < 0.55:
		return pick(rng, own)
	return pick(rng, ANYONE)

class_name PedestrianLines
extends RefCounted
## What people on foot think and say (Pedestrian, RideFares). Thoughts
## float over their heads now and then while they walk; the rest are said
## out loud, in reaction to something.

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

## Hailing a ride.
const HAIL := ["Need a lift!", "Ride? I'll pay!", "Over here! Hey!", "Taxi! ...ish?", "Can you drive me?"]
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
	return str(lines[rng.randi() % lines.size()])


static func thought(rng: RandomNumberGenerator, kind: String) -> String:
	var own: Array = BY_KIND.get(kind, [])
	if not own.is_empty() and rng.randf() < 0.55:
		return pick(rng, own)
	return pick(rng, ANYONE)

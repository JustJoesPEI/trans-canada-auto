class_name GarageLines
extends RefCounted
## Every word of The Garage (GarageTest): Tenner, the parking officer, the
## notepad, the title card and the road test result. docs/voice.md: a
## straight face, the honest line at the end.
##
## The Garage is a homage to the first mission of a 1999 car chase game:
## a parking garage, sixty seconds, a list of stunts, and a whole
## generation of kids who never got past it. We never name the game.
## Tenner (Tanner, near enough) does all the remembering, and the joke is
## that he's still not over it. The digs are at the game and at the kids
## it beat, the last line usually at the city (the meter, the ticket).

const NAME := "TENNER"
const OFFICER := "PARKING ENFORCEMENT"

## Over his head while he waits, before you talk to him.
const WAITING: Array[String] = [
	"Sixty seconds. I've timed it.",
	"Show me what you've got.",
	"Bring your own car.",
	"Most don't pass.",
	"Hiring. Drivers. Not walkers.",
]

## The counter's card.
const CARD_TITLE := "Tenner"
const CARD_SUB := "Getaway driver, semi-retired. Hiring. Says it like he's said it before."
const TAKE := "Take the test"
const TAKE_NOTE := "Sixty seconds on the meter. He's paying the meter."
const TAKE_AGAIN := "Take it again"
const NEED_CAR := "Bring a car. I'm not lending you mine."

## Said before the first test, one at a time (any key moves on).
const INTRO: Array[String] = [
	"Call me Tenner. Like the money. It's what I charge.",
	"1999. They sold us a car chase game. First thing it does is put you in a parking garage.",
	"Burnout. Handbrake. Slalom. One-eighty. Reverse one-eighty. Three-sixty. Speed. Brake test. Sixty seconds.",
	"I've known that list longer than my SIN number.",
	"Took me three weeks to pass. Half of Sherwood never did.",
]
## Before a retake: just the meter.
const AGAIN: Array[String] = [
	"Again. Like old times.",
]
## Feeding the meter, last thing before the title.
const METER := "Two dollars. That's a minute downtown now."

## Mumbled while he watches you, every few seconds, never the same twice in
## a test. The second game's triangle (getting out of the car) is Joe's own
## memory: ten years old, didn't know you could.
const MUMBLES: Array[String] = [
	"The second one, you could get out of the car. Triangle. I didn't know.",
	"I was ten. Pressed triangle by accident. Got out of the car. Sat there with my mouth open.",
	"Walked around for an hour. Didn't drive once. Whole new game.",
	"My mother thought I'd broke it.",
	"My brother's still in that garage. He's 41. Memory card's fine.",
	"They sold it as a car chase game. It was a parking garage. For a month.",
	"You could watch your crashes back. Like a film. I watched mine for hours.",
	"Every car was brown. You don't see a brown car anymore.",
	"The city ended at the water. Same as here, really.",
	"I had it in the big box. Kept the box. Wife threw out the box.",
	"Back then the cops rammed you off the road. Now they mail it.",
	"Then they let you get out and walk around for a whole game. Some of us never recovered.",
	"Pillars, not cars. Pillars.",
	"I've seen worse. I was worse.",
]

## The notepad: [move id, what's written, his note beside it ("" for none)].
const LIST: Array = [
	["burnout", "Burnout", ""],
	["handbrake", "Handbrake turn", "(the hand one)"],
	["slalom", "Slalom", "weave. NOT the cars"],
	["one_eighty", "180", "no handbrake, show off"],
	["reverse_180", "Reverse 180", "backwards!!"],
	["three_sixty", "360", ""],
	["speed", "Speed", "60 on the dial"],
	["brake_test", "Brake test", "from 40, dead stop"],
	["back_in", "Back into a stall", "like a normal person"],
]
const PAD_HEAD := "THE GARAGE"
const PAD_SUB := "60 sec. no excuses"
## Written in red at the bottom after the roof ramp.
const PAD_ROOF := "ROOF??"

## Said as each comes off the list.
const DONE := {
	"burnout": "Burnout. Smells right.",
	"handbrake": "Handbrake. It's in the name.",
	"slalom": "Slalom. Didn't touch a thing. Suspicious.",
	"one_eighty": "One-eighty. Facing home. Good instinct.",
	"reverse_180": "Reverse one-eighty. I never once got that first go.",
	"three_sixty": "Three-sixty. Now you're facing the way you were facing.",
	"speed": "Sixty. In a parkade. Lovely.",
	"brake_test": "Brakes work. Writing that down.",
	"back_in": "Backed in. Your father would cry.",
	"roof": "We don't need that. Bonus marks.",
}

## Hitting things.
const CRASH: Array[String] = [
	"Concrete wins. Every time.",
	"That's coming out of something.",
	"That one'll be on Kinbook by supper.",
	"Pillars are load-bearing. So's my patience.",
	"Somebody's mother parks there.",
]

## The meter getting low.
const LOW := "Meter's running down. So's the city's patience."
## The officer, walking up when it runs out.
const TICKET: Array[String] = [
	"Meter's expired.",
	"That's twenty-five dollars. You can appeal it. Nobody has.",
]
const TICKET_FINE := 25

## The title card.
const TITLE := "THE GARAGE"
const TITLE_SUB := "SIXTY SECONDS.  NO SIGNALLING REQUIRED."
const TITLE_CREDIT := "A TENNER PRODUCTION"

## The result, as a road test sheet.
const SHEET_HEAD := "ROAD TEST RESULT"
const SHEET_EXAMINER := "Examiner: Tenner (semi-retired)"
const SIGNALLED := "Signalled: never."
const HIRED := "HIRED"
const FAILED := "FAILED"
const TICKETED := "TICKETED"

## Remarks on hits: 0, 1, a few, lots.
static func hit_remark(n: int) -> String:
	if n == 0:
		return "Hit nothing. I don't trust it."
	if n == 1:
		return "Hit one thing. We'll call it a lean."
	if n <= 4:
		return "Hit %d things. Insurance will be in touch." % n
	return "Hit %d things. Insurance has moved away." % n


## The last line on the sheet, and what he says.
static func verdict(passed: bool, why: String, first_try: bool) -> String:
	if passed:
		if first_try:
			return "Took me eleven tries in '99. You did it in one. I hate you. You're hired."
		return "You're hired. You'd still fail the real test."
	match why:
		"ticket":
			return "Expired meter. That's how it got most of us."
		"left":
			return "You left the garage. Some of us never did."
		"roof":
			return "Through the roof. Out of the garage. That's a first. Still a fail."
		"car":
			return "You got out of the car. I know. Triangle. Still a fail."
	return "Same as my brother. You can try again. He's still trying."

## Retake: a new best time, or not.
const BEST := "New best. Sixty seconds is a long time, apparently."
const NOT_BEST := "Slower than last time. I'm not paying twice for the same parkade."
## The extra row on the sheet after the roof ramp.
const ROOF_ROW := "Roof (not on the list)"

## The sandwich board out front, on Queen Street.
const BOARD := "DRIVERS\nWANTED\n\nMUST PASS\nTHE GARAGE\n\nMOST DON'T"

## Kinbook's posts are in KinbookLines: one in the feed from the start
## (POSTS), and "garage_pass" and "garage_ticket" (ABOUT_YOU).

class_name EmergencyLines
extends RefCounted
## What everyone says when someone's hurt (EmergencyServices, Pedestrian):
## the person on the ground, the people running for a doorway, whoever
## calls it in, the Island Boo-Boo Bus's paramedics, the Island Wee-Woo
## Brigade, and the police and the Brigade having a go at each other.
## docs/voice.md: a straight face, the honest line at the end, aimed up.
## The people who got hurt are never the joke; the wait, the system, the
## driver and the two services are.
##
## The Brigade's keen one at the end of the hose is Kevin (Marlene T.'s
## son, docs/kinbook.md: "he does very good work actually").

# --- people on foot ---------------------------------------------------------------------------

## Knocked over by a car going slowly: down on their backside, then up.
const BUMPED := [
	"Watch it! I'm on my break.",
	"You hit me with your car.",
	"I'm fine. My hip isn't.",
	"That's going on Kinbook.",
	"Ever heard of a sidewalk? This is one.",
	"I had the walk signal!",
]

## Lying in the street after a car hit them, putting it on a bit.
const DOWN_STRUCK := [
	"Don't move me. I'm comfortable.",
	"I can see a light. No, that's the Boo-Boo Bus.",
	"Tell Darlene she can keep the casserole dish.",
	"Somebody film this. For the lawyer.",
	"I was on the SIDEWALK.",
	"Is my coffee okay?",
	"My whole life flashed by. It was mostly waiting rooms.",
	"Is it bad? Don't tell me. Tell my sister.",
	"Did anyone get the plate? Was it a local plate?",
]

## Down after a third paintball: a death scene, played to the back row.
const DOWN_PAINTED := [
	"Go on without me.",
	"It's in my good coat.",
	"I'm out. Call it in.",
	"Raspberry. It's always raspberry.",
	"This is how it ends. Downtown, on a weekday.",
	"Tell my mother I was out fair.",
	"I can't feel my dry cleaning.",
	"Avenge me. Or don't. Just call someone.",
]

## A car coming back at someone already down: they roll clear.
const ROLL_CLEAR := [
	"AGAIN?",
	"I'm already DOWN!",
	"Twice? Really?",
	"Oh, come ON.",
]

## Running for a doorway once someone's been hit on the sidewalk.
const SCATTER := [
	"He's on the sidewalk!",
	"Not again!",
	"Into the Tim Hardly's!",
	"Get behind the mailbox!",
	"Sidewalk, buddy! SIDEWALK!",
	"Everybody inside!",
	"Not the good shoes!",
	"Is he coming back around?",
]

## Calling it in, on the phone, a few seconds after.
const CALLING := [
	"Hi, yes, the Boo-Boo Bus? It's bad.",
	"Yes, a boo-boo. A big one.",
	"They're breathing. They're mostly complaining.",
	"No, I'm not hurt. I'm filming.",
	"Hi, Boo-Boo Bus? Bring the good blanket.",
]

## Nobody came: up on their own.
const GAVE_UP := [
	"Fine. I'll walk it off.",
	"Twelve minutes. Same as the clinic.",
	"I'll drive myself. I'll get a ride. I'll walk.",
]

# --- the Island Boo-Boo Bus --------------------------------------------------------------------

## A paramedic getting to someone.
const MEDIC_ARRIVE := [
	"IBBB. Okay, what happened here?",
	"Who's got the boo-boo?",
	"Don't get up. I'll do the getting.",
	"Hi there. Can you tell me your name? And who's your father?",
	"Okay. Let's have a look at you.",
]

## A paramedic and the patient: [medic, patient, (medic, patient)].
const ASSESS := [
	["Can you tell me what day it is?", "Payday. And I'm still broke."],
	["Any pain?", "Only in my good jacket."],
	["On a scale of one to ten?", "Eleven. Twelve if you count the wait."],
	["Want to go to Emergency?", "How long's the wait?", "Eleven hours.", "I'll walk it off."],
	["Do you have a family doctor?", "I'm on the list.", "Since when?", "2019."],
	["Follow my finger.", "Which one? There's three."],
	["Do you remember what hit you?", "The bumper. Very up close."],
	["Any allergies?", "Cars, now."],
]

## The same, for someone hit by a car.
const ASSESS_STRUCK := [
	["Tread pattern on your shirt's all-season.", "In November?"],
	["Did you see the car?", "I saw the grille. It needs a wash."],
	["You were on the sidewalk?", "The whole time. Ask anyone."],
]

## The same, for someone painted out.
const ASSESS_PAINTED := [
	["Pupils are fine. That's raspberry.", "They told me it was strawberry."],
	["It's water-based. It comes right out.", "Unlike my student loan."],
	["How many hits?", "Three. One was my head, so four."],
]

## A paramedic rinsing paint off.
const RINSE := [
	"Hold still, it's just a rinse.",
	"Close your eyes. And your mouth. Especially your mouth.",
	"Bit of water. You'll be grand.",
]

## A paramedic done with someone.
const MEDIC_DONE := [
	"Neck brace. Mostly for the photos.",
	"Here's a blanket. Everybody gets a blanket.",
	"You're good. Don't look it up.",
	"Sign here. That says you said no to the hospital. Smart.",
	"Bandage. Keep it on till you've told everyone.",
]

## The patient off again, patched up.
const PATIENT_LEAVES := [
	"Best care I've had in years.",
	"Do I keep the blanket?",
	"Eleven hours? No thanks.",
	"I'm posting about this.",
	"Back to work, I suppose.",
]

## The paramedics to each other, between patients, or the last one.
const MEDIC_CHAT := [
	["That's six today.", "It's ten in the morning."],
	["Who's on the paperwork?", "You. You're always on the paperwork."],
	["Same car as Tuesday?", "Same car as Tuesday."],
	["Is the Brigade coming?", "The Brigade's always coming."],
]

# --- the Island Wee-Woo Brigade ----------------------------------------------------------------

## Getting out at a scene that's no fire at all: [captain, Kevin].
const FIRE_ARRIVE := [
	["Here we are, doing traffic again.", "Is anything on fire? Anything at all?"],
	["Isn't this a police job?", "I brought the hose anyway."],
	["Wee-Woo Brigade. Nobody panic.", "Should I panic?"],
	["Everybody stand back. Further. No, further.", "Can I unroll the big hose?"],
	["We heard sirens. We came.", "We always come."],
]

## Kevin, at the end of the hose, keen.
const KEVIN := [
	"Hose is charged! Say the word!",
	"Can I spray it? Just a little?",
	"You never know. It could go up any time.",
	"Paint's flammable, right? It's not? You're sure?",
	"I'm ready. I've been ready since Tuesday.",
	"Just say 'go'. Anyone. Just say it.",
	"I could do the sidewalk. Sidewalks get dirty.",
]

## The captain, to Kevin.
const CAPTAIN := [
	"Nobody's spraying anything, Kevin.",
	"Kevin. It's a sidewalk.",
	"Put it down, Kevin.",
	"Your mother says you're doing very good work, Kevin.",
	"Kevin, we talked about this.",
]

## At the end, the captain gives in.
const KEVIN_GO := [
	["...Fine. Once.", "YES."],
	["Go on, then. A short one.", "Best day of my life."],
	["One squirt, Kevin.", "You won't regret this."],
]

## Hosing paint off a stalled car.
const FIRE_CAR := [
	["Stand back, we're hosing it down.", "Finally!"],
	["Evidence Paint. The police love this stuff.", "We hate it. It gets in the treads."],
	["That'll start now. Don't thank us.", "You can thank me. I'm Kevin."],
]

## Hosing a mess of paint off the street.
const FIRE_MESS := [
	["Hazardous materials. Raspberry.", "Smells nice, actually."],
	["We'll have this cleaned up in a minute.", "Council's three years on the pothole, mind."],
	["Paint spill. Logging it as a fire.", "Good. We need the numbers."],
]

## Back in the truck.
const FIRE_LEAVE := [
	"Back to the hall. The chili won't watch itself.",
	"Good call, everybody. Log it as a fire.",
	"Right. Back to the hall before the police take credit.",
]

# --- the police and the Brigade ----------------------------------------------------------------

## Passing on the street or at the same scene: [who, text] each ("fire",
## a firefighter; "cop", an officer).
const BANTER := [
	[["fire", "Isn't this a police job?"], ["cop", "We're busy."], ["fire", "Doing what?"], ["cop", "Lunch."]],
	[["cop", "Don't you lot have a nap to get back to?"], ["fire", "Don't you have a muffin to finish?"]],
	[["cop", "Must be nice. Sleep all day, eat chili, get in a calendar."], ["fire", "You wanted the calendar."], ["cop", "...Yeah."]],
	[["fire", "How come you never do traffic?"], ["cop", "We do traffic. From the car."]],
	[["cop", "I applied to the Brigade once."], ["fire", "We know. We still have the letter."]],
	[["cop", "Nine fires a year and a fridge full of lasagna."], ["fire", "Eight. One was a toaster."]],
	[["fire", "Call us if it catches fire."], ["cop", "It's paint."], ["fire", "Call us anyway. Kevin's bored."]],
	[["cop", "Who called you?"], ["fire", "Nobody. We heard sirens."]],
	[["fire", "Nice cruiser. When's your nap?"], ["cop", "When's yours?"], ["fire", "Two. Then four."]],
	[["cop", "Do you even have a fire today?"], ["fire", "Do you even have a suspect?"]],
]

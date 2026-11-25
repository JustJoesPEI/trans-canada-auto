class_name SpudDashLines
extends RefCounted
## SpudDash's words (docs/design.md section 8, "Humour"): what each place
## sells, who orders it and what they say, and the rating they give at the
## door. Made-up people and stand-ins only; the joke's on institutions.

## Orders by place: [what, fragility] (1 is ordinary; more spills sooner).
const ORDERS := {
	"Starbeans": [["Four oat-milk lattes in a cardboard tray", 1.8], ["A venti cold brew and a lemon scone", 1.4], ["Six pumpkin things, it's that time", 1.6]],
	"Tim Hardly's": [["A box of forty Hardly Bits", 0.8], ["Two large double-doubles and a breakfast wrap", 1.6], ["Twelve coffees for a road crew", 2.0]],
	"Wren's Donuts": [["A dozen maple glazed", 1.0], ["Six cream-filled. Handle with care", 1.6], ["One apple fritter the size of a hubcap", 0.9]],
	"A-OK Root Beer": [["Two root beer floats", 2.0], ["A Papa Burger and onion rings", 1.0], ["A gallon jug of root beer, glass", 1.8]],
	"Burger Baron": [["Two Baron Doubles, no pickles", 0.9], ["A Mushroom Melt and a strawberry shake", 1.5], ["Eight cheeseburgers for a hockey team", 0.8]],
	"Cluckers": [["A 12-piece bucket and a gravy", 1.3], ["Popcorn chicken for a birthday party", 0.9], ["Two wraps and the hot sauce they keep behind the counter", 1.0]],
	"Dairy Duchess": [["A Flurry, already melting", 2.0], ["An ice cream cake that says CONGRATS ON THE PERMIT", 2.4], ["Four dipped cones in a tray", 2.2]],
	"MacDougall's": [["Two Big MacDougalls and a large fries", 0.9], ["Forty nuggets in one bag", 0.8], ["A McFlounder and a hot apple pie", 1.1]],
	"Portland Pizza": [["Two large pepperoni", 1.2], ["A donair pizza, extra sauce", 1.4], ["A party sub and a garlic fingers", 1.1]],
	"Sub Station": [["A footlong for a committee meeting", 0.8], ["Three subs, toasted, labelled", 0.9]],
	"Windy's": [["A Breezy and two square burgers", 1.5], ["Spicy nuggets and a chili", 1.3]],
	"Wyoming's": [["Thirty wings, hot", 1.2], ["A rack of ribs and a coleslaw", 1.3], ["A loaded poutine the size of a hubcap", 1.4]],
}
const ORDER_ANY := [["A bag of takeout", 1.0], ["Two combos and a drink tray", 1.5]]

const CLIENTS := ["Darlene", "Wade", "Bernice", "Gord", "Shelley", "Tanner", "Marlene", "Lorne", "Kayleigh",
	"Doug", "Reggie", "Paulette", "Clayton", "Heather", "Ramesh", "Priya", "Jean-Guy", "Siobhan", "Mohammed",
	"Ana", "Brent", "Wanda", "Colby", "Trudy"]

const LINES := [
	"For the committee reviewing the committee. They're on hour six.",
	"Dinner for the bridge toll booth. They only work one way too.",
	"Leave it on the step. I'm in a consultation about the step.",
	"Mind the pothole at the end of my driveway. It's the province's, not mine.",
	"Lunch for the potato lobby. Fries are a sensitive subject. Keep them hot.",
	"I'm watching council on TV. Hurry, they're about to table something.",
	"It's for my cousin from away. Don't tell him it's not lobster.",
	"Knock once. The parking authority's been by twice today.",
	"Night shift at the courthouse. The backlog has its own backlog.",
	"Extra napkins please. The FIP took my last ones as evidence.",
	"Third time ordering. The last two drivers took the Arterial at five.",
	"If anyone asks, I'm at the gym.",
	"The Premier's office said 'soon'. I'm hoping you mean sooner.",
	"Building a deck without a permit. Leave it by the deck that isn't there.",
	"For the ferry crew. They're arguing with the bridge again.",
	"My mother knows your mother, so no pressure.",
	"For the fundraiser for the hospital parking lot.",
	"Tourist season. I'm the rental car stopped in the middle of Grafton.",
	"Bring it round back. The front door's under review.",
	"Hungry. That's the whole message.",
	"Please don't get painted. Last time my fries came teal.",
	"For the planning board. Take as long as you like, they do.",
	"It's for a ribbon cutting at the new ribbon-cutting centre.",
	"Working from home for the Department of Working From Home.",
]

## The rating at the door, by how it went. "%s" in PAINTED is the colour.
const HAPPY := [
	"Still hot. Who are you?",
	"Five stars. Would get fed again.",
	"Quickest thing on the Island since the bridge toll.",
	"Not a fry out of place. Faith in institutions: partly restored.",
	"Perfect. I'll tell my mother, and she'll tell yours.",
]
const SLOW := [
	"Arrived. Eventually. Like the new hospital wing.",
	"I aged. The fries aged.",
	"Did you take the Arterial at five?",
]
const BUMPY := [
	"A bit shaken. So am I, after watching you park.",
	"The burger's a wrap now.",
	"Some of the drink made it.",
]
const WRECKED := [
	"This was dinner. It's a casserole now.",
	"Did you deliver it or drop it off the bridge?",
	"I've filed a complaint with a committee that'll never meet.",
]
const PAINTED := [
	"My order arrived %s.",
	"Delicious. Also %s, for some reason.",
	"Your car's %s. So's my bag. Explain.",
]


static func order_for(place: String, rng: RandomNumberGenerator) -> Array:
	var list: Array = ORDERS.get(place, ORDER_ANY)
	return list[rng.randi() % list.size()]


## A colour's name for "My order arrived orange".
static func colour_name(c: Color) -> String:
	if c.s < 0.25:
		return "white" if c.v > 0.7 else ("grey" if c.v > 0.3 else "black")
	var h := c.h * 360.0
	if h < 15.0 or h >= 340.0:
		return "pink" if c.v > 0.8 and c.s < 0.6 else "red"
	if h < 45.0:
		return "orange"
	if h < 70.0:
		return "yellow"
	if h < 165.0:
		return "green"
	if h < 200.0:
		return "teal"
	if h < 255.0:
		return "blue"
	if h < 290.0:
		return "purple"
	return "pink"

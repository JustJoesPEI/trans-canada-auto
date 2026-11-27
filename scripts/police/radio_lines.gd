class_name RadioLines
extends RefCounted
## What the police say over the radio during a chase (docs/design.md
## section 7, "The FIP's running jokes", and section 8). Short lines, by
## topic; PoliceRadio picks one it hasn't used lately. Aimed at the
## institutions (the city, the FIP, budgets, paperwork, jurisdiction),
## never at victims, real people or anyone for who they are. No real
## officers, politicians or services by name: "Charlatown Police" and the
## "Federal Island Patrol" are our own.
##
## Each line is [who, text]. Who: "dispatch" (city dispatch), "city" (a
## city unit), "fip" (an FIP unit), "fip_hq" (FIP command), "tac" (the
## tactical unit), "ibbb" (the Island Boo-Boo Bus) and "iwwb" (the Island
## Wee-Woo Brigade). An exchange is an Array of lines said in order.
## {street} is replaced with the street the player is on, {colour} and
## {car} with what they're driving, {unit} with a unit number.

const LINES := {
	# A crime called in: level 1, someone called your mother.
	"call_in": [
		[["dispatch", "Report of a paintball incident on {street}. Caller says it's 'their good jacket'."]],
		[["dispatch", "Paint complaint near {street}. Any unit not on break."]],
		[["dispatch", "Caller reports a {colour} {car} on {street}. Caller is your mother, apparently."]],
		[["dispatch", "Paint on a vehicle, {street}. The owner would like it noted it was just washed."]],
		[["dispatch", "Paintball mischief, {street}. One unit, no lights, it's a weeknight."]],
		[["city", "City {unit}, I'll take it. I was going that way for a muffin anyway."]],
		[["dispatch", "Disturbance on {street}. Caller wants to know if this is what their taxes are for."]],
	],
	# Level 2: the city police.
	"level_2": [
		[["dispatch", "All city units: {colour} {car} on {street}. This is now a whole thing."]],
		[["dispatch", "Suspect fled a cruiser. That's a level two. Somebody tell the Chief before he reads it on Facebook."]],
		[["city", "City {unit}, in pursuit on {street}. Requesting someone else do the report."]],
		[["dispatch", "Units responding: {count}. That's everybody. We're short-staffed, so make it count."]],
		[["dispatch", "Escalating to a pursuit. Overtime has been pre-approved, which has never happened before."]],
	],
	# Level 3: the city calls the FIP.
	"fip_called": [
		[["dispatch", "City requesting FIP assistance on {street}."], ["fip_hq", "That's a city matter."], ["dispatch", "It's past the bypass."], ["fip_hq", "We'll need that request in writing."]],
		[["dispatch", "Requesting federal backup."], ["fip_hq", "Backup is unavailable. We're a few thousand officers short. Please hold."], ["fip_hq", "...Fine. Units en route. ETA: after the paperwork."]],
		[["dispatch", "FIP, we need you on {street}."], ["fip_hq", "Do you even know who we are?"], ["dispatch", "That's why we're calling."], ["fip_hq", "Units responding. The city will be billed."]],
		[["fip_hq", "FIP taking command of the pursuit. The city will be invoiced for the privilege."], ["dispatch", "We didn't ask you to take command."], ["fip_hq", "And yet."]],
		[["dispatch", "Calling in the FIP."], ["fip_hq", "Acknowledged. We've accepted all the recommendations from the review of the last review and will implement them shortly."]],
	],
	# Level 4: Federal Overreach.
	"level_4": [
		[["fip_hq", "Deploying the Tactical Unit. Funded through the Island Safety Initiative."]],
		[["tac", "Tactical rolling. We just got funding for this. We are going to use it."]],
		[["fip_hq", "Paint Tank is authorised. Nobody ask what it cost."], ["dispatch", "What did it cost?"], ["fip_hq", "Four point two."]],
		[["tac", "Paint Tank on the move. Drone team, launch."], ["tac", "...Drone did not launch. Drone has never launched."]],
		[["fip_hq", "Harvesters are in position. The potato board has been very cooperative."]],
	],
	# Someone has eyes on the player.
	"spotted": [
		[["city", "City {unit}, eyes on a {colour} {car}, {street}."]],
		[["fip", "FIP {unit}, I have the suspect on {street}. We always get our man."]],
		[["city", "Got 'em. {street}. Don't make me run, I just ate."]],
		[["fip", "FIP {unit}, visual on {street}. We have your licence plate, your face and your group chat."]],
		[["city", "{colour} {car}, {street}. That's them, unless it's someone else."]],
		[["fip", "Contact, {street}. Sorry about this, by the way."]],
	],
	# Lost sight of the player.
	"lost": [
		[["city", "Lost visual near {street}. They went... somewhere."]],
		[["fip", "Lost them. This will be in the review."]],
		[["dispatch", "All units, last seen {street}. Spread out and check the lots."]],
		[["city", "Lost them at the lights. I stopped. It was red."]],
		[["fip", "No visual. Logging it as a 'tactical repositioning'."]],
	],
	# Searching the circle.
	"searching": [
		[["dispatch", "Units, search grid on {street}. Check the driveways, they love a driveway."]],
		[["city", "Checking the Tim Hardly's lot. For the suspect. Not for a coffee."]],
		[["fip", "Grid search under way. Some of us have some confidence in this."]],
		[["dispatch", "Slow down and look. And use your signals, people are filming."]],
		[["city", "Doing another lap of {street}. It's very scenic."]],
	],
	# An officer painted out.
	"officer_out": [
		[["city", "I'm out. I'm hit. I'm going to need a form for this."]],
		[["city", "Officer out. Calling my union rep."]],
		[["fip", "I'm out. That's going in my report."]],
		[["city", "I'm out. Sitting this one out on the curb. Checking my overtime."]],
		[["fip", "Hit! Do you know who I am?"], ["dispatch", "...No?"]],
		[["fip", "Out. This uniform was dry-clean only."]],
		[["city", "I'm out. Starting the paperwork. Somebody bring me a pen."]],
	],
	# A police vehicle stalled by paint.
	"vehicle_stalled": [
		[["city", "City {unit}, my cruiser's done. Engine's full of paint. Continuing on foot. Slowly."]],
		[["fip", "FIP {unit}, vehicle disabled. That's federal property, by the way."]],
		[["dispatch", "Another cruiser down. Fleet maintenance is going to cry."]],
		[["fip", "SUV's gummed up. Proceeding on foot, as per the review."]],
	],
	# Replacements on the way.
	"replacement": [
		[["dispatch", "Sending a replacement unit. It's the one with the wobbly seat."]],
		[["fip_hq", "Replacement en route from the mainland. Toll waived."]],
		[["dispatch", "Backup's coming. Reserve Constable Gerald, seventy-one. Be nice."]],
		[["fip_hq", "Another unit dispatched. Please hold. Your pursuit is important to us."]],
	],
	"roadblock": [
		[["fip", "Roadblock set up ahead on {street}. Two SUVs and a sense of purpose."]],
		[["city", "Roadblock's up. Left a gap on the sidewalk, that's policy."]],
		[["fip", "Blocking {street}. If they go round it, that's on the city's sidewalk budget."]],
	],
	"harvester": [
		[["tac", "Harvester in position on {street}. Very PEI."]],
		[["tac", "We've borrowed a potato harvester. It's blocking {street}. The farmer wants it back by Thursday."]],
	],
	"strip": [
		[["fip", "Deploying the paint strip. Evidence Paint, fourteen-month procurement."]],
		[["city", "Strip's down on {street}. Mind your own tyres, it's slippery."]],
		[["fip", "Paint strip out. Approved after a fourteen-month procurement process."]],
	],
	"leaning_out": [
		[["fip", "Passenger, lean out and paint the windscreen. Aim for the evidence."]],
		[["city", "My partner's leaning out. Please don't tell the Chief."]],
	],
	"missed_turn": [
		[["city", "Missed the turn! Missed the turn! Turning round."]],
		[["fip", "Overshot the junction. That's on the GPS contract."]],
		[["city", "Went straight. In my defence, so did the last three guys."]],
		[["fip", "Missed it. Recalculating. Do not put that on the radio. ...Oh."]],
	],
	"paperwork": [
		[["fip_hq", "FIP units are on the way. Forms 12-B through 12-F are being filed."]],
		[["fip_hq", "Requisition approved. Units rolling as soon as someone finds the keys."]],
	],
	"pit": [
		[["fip", "Executing PIT. Sorry. Sorry about that."]],
		[["city", "Tapped 'em. Gently. It's a lease."]],
	],
	"tank_hit": [
		[["tac", "Direct hit. That's a lot of Evidence Paint. Like, a lot."]],
		[["tac", "Cannon hit confirmed. Worth every penny of the four point two."]],
	],
	"boxed_in": [
		[["city", "Got 'em boxed. Hands where I can see 'em. Please."]],
		[["fip", "Suspect contained. We always get our man. This time, anyway."]],
	],
	"pulled_over": [
		[["city", "They pulled over. Very polite. Writing it up."]],
	],
	"car_stalled": [
		[["dispatch", "Suspect vehicle's stalled. All units, move in on foot."]],
		[["fip", "Their engine's done. Get out there, and mind the paint."]],
	],
	"switched_car": [
		[["city", "They're in a different car now. A {colour} {car}. Got it."]],
		[["fip", "Suspect has changed vehicles. A {colour} {car}. Updating the file."]],
	],
	"on_foot": [
		[["city", "Suspect on foot. I'm getting out. Somebody hold my coffee."]],
		[["fip", "Suspect on foot. Pair up, use cover, the usual."]],
	],
	"heard_shots": [
		[["city", "Shots, paintball, near {street}. Sounded like the expensive kind."]],
		[["fip", "Heard firing near {street}. Moving to investigate, eventually."]],
	],
	"escaped": [
		[["dispatch", "All units, stand down. Suspect's gone. Nobody saw a thing, apparently."]],
		[["fip_hq", "Pursuit ended after a successful review. The city will be billed."]],
		[["dispatch", "Lost 'em. Back to patrol. And somebody return the potato harvester."]],
		[["dispatch", "We're calling it. Overtime ends now. Sorry, Gerald."]],
	],
	"caught": [
		[["dispatch", "Suspect in custody. Two years less a day, probably."]],
		[["fip_hq", "Arrest made. The FIP would like to thank itself."]],
		[["city", "Got 'em. Can somebody else do the report? Anybody?"]],
	],
	"overtime": [
		[["fip_hq", "Tactical Unit, return to base. You've exceeded the overtime budget."], ["tac", "We were winning."], ["fip_hq", "That's not a line item."]],
	],
	"impound": [
		[["dispatch", "Suspect's vehicle is going to the impound lot. Open Tuesdays, ten to eleven-thirty."]],
	],
	# Someone hit by the player's car: the Island Boo-Boo Bus called.
	"struck": [
		[["dispatch", "Pedestrian struck, {street}. Boo-Boo Bus en route."], ["ibbb", "IBBB responding. How bad?"], ["dispatch", "They're asking for a lawyer and a coffee."]],
		[["dispatch", "Hit and run on {street}. A {colour} {car}. On the sidewalk, caller says, which is new."]],
		[["dispatch", "Person versus {car}, {street}. The person would like that on the record."], ["ibbb", "Boo-Boo Bus rolling. Tell them not to get up."]],
		[["ibbb", "IBBB on the way to {street}. Is the Brigade coming?"], ["dispatch", "Nobody called the Brigade."], ["iwwb", "Wee-Woo Brigade responding."]],
	],
	# More than a couple hit.
	"struck_more": [
		[["dispatch", "Another pedestrian on {street}. Same {car}. Who's driving this thing?"]],
		[["ibbb", "IBBB requesting a second bus. And maybe a second dispatcher."], ["dispatch", "We have one dispatcher."], ["ibbb", "Then a coffee."]],
	],
	# A spree: level 3.
	"spree": [
		[["dispatch", "All units, mass casualty event downtown. Suspect vehicle is the same {car} as Tuesday."]],
		[["dispatch", "Multiple pedestrians struck on {street}. FIP, this one's yours."], ["fip_hq", "Since when?"], ["dispatch", "Since the sidewalk."]],
		[["iwwb", "Brigade on {street}. Nothing's on fire, but we're staying."], ["dispatch", "Copy, Brigade."], ["iwwb", "Kevin, put the hose down."]],
	],
	# The Brigade turns up during a chase.
	"brigade": [
		[["iwwb", "Wee-Woo Brigade on scene, {street}. Who's in charge?"], ["city", "We are."], ["iwwb", "Since when?"]],
		[["city", "Why is there a fire truck behind me?"], ["iwwb", "We heard sirens."], ["city", "They're OUR sirens."]],
		[["iwwb", "Brigade, we'll set up a perimeter."], ["dispatch", "That's a police thing."], ["iwwb", "Then do it."]],
		[["city", "Brigade's here. For a paint call."], ["iwwb", "We go to everything. Unlike some."]],
		[["iwwb", "Any of you lot need a hand? We've done the training."], ["city", "We've done the training too."], ["iwwb", "Have you, though."]],
	],
	"patrol": [
		[["city", "City {unit}, on patrol. Quiet night. Somebody just parked in a loading zone."]],
		[["fip", "FIP {unit}, patrolling the ring. Now hiring. Seriously. Anyone."]],
		[["dispatch", "Units be advised, council's touring the potholes on {street}. Act natural."]],
	],
}


## The lines for a topic, each an exchange (Array of [who, text]).
static func topic(name: String) -> Array:
	return LINES.get(name, [])


## How a speaker shows on the HUD, with a unit number where it has one.
static func speaker(who: String, unit := 0) -> String:
	match who:
		"dispatch":
			return "CITY DISPATCH"
		"city":
			return "CITY %d" % unit if unit > 0 else "CITY"
		"fip":
			return "FIP %d" % unit if unit > 0 else "FIP"
		"fip_hq":
			return "FIP COMMAND"
		"tac":
			return "FIP TACTICAL"
		"ibbb":
			return "BOO-BOO BUS"
		"iwwb":
			return "WEE-WOO BRIGADE"
	return who.to_upper()


## A line's text with its blanks filled.
static func fill(text: String, vars: Dictionary) -> String:
	for k: String in vars:
		text = text.replace("{%s}" % k, str(vars[k]))
	return text

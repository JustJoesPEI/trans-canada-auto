class_name KinbookLines
extends RefCounted
## What's on Kinbook, the town's social media (Kinbook, on the phone).
## Three corners of it: Charlatown Rants & Raves (anonymous complaints and
## thank-yous), Are We Dating the Same Fella? (anonymous warnings about
## men), and ChipIn fundraisers (the town's GoFundMe, mostly for things
## people did to themselves). The comments are half the joke.
##
## The voice is docs/radio.md's: dry, specific, true. The joke's on prices,
## landlords, the province, the police and the man with the lifted truck,
## never on someone who's actually struggling. Made-up people only; first
## names and an initial, the way these groups look.

const GROUPS := {
	"rants": "Charlatown Rants & Raves",
	"dating": "Are We Dating the Same Fella? (Island)",
}

## Rants & Raves and the dating group: {group, text, likes, comments: [[who, text]]}.
const POSTS := [
	{"group": "rants", "likes": 412, "text": "RANT: To the man at Countess Auto Saturday morning who told the cashier he \"just needed one bolt.\" I was behind you. You had a winch, a tarp and a pressure washer. You did not have a bolt.",
		"comments": [["Shelley M.", "That's my husband."], ["Trudy K.", "That's everyone's husband."]]},
	{"group": "rants", "likes": 88, "text": "RANT: Paid $6.49 for a block of cheese at the Megastore and it's the size of a domino.",
		"comments": [["Lorne P.", "Grow your own cheese"], ["Heather D.", "Lorne that's not how cheese works"]]},
	{"group": "rants", "likes": 156, "text": "RANT: Whoever keeps parking across two spots at SoBuys in the white Halfton. We all know it's you. Your business name is on the side of the truck.",
		"comments": [["Wanda F.", "Name and shame!!"], ["Admin", "No names please."], ["Wanda F.", "It's ON THE TRUCK"]]},
	{"group": "rants", "likes": 301, "text": "RANT: Week three of the orange cones on Grafton. Nobody has worked there. Not once. The cones have a routine now. They've made friends.",
		"comments": [["Doug R.", "Those cones were there when I was born"], ["Paulette G.", "Different cousin's contract this year"]]},
	{"group": "rants", "likes": 64, "text": "QUESTION: Anyone know why there were three police cars and an FIP truck on University last night? Asking for a reason.",
		"comments": [["Brent S.", "Heard it was the Premier"], ["Marlene T.", "Which one"]]},
	{"group": "rants", "likes": 233, "text": "RANT: Landlord put my rent up $400 for \"improvements.\" The improvement is a new lock. On my door. That he has the key to.",
		"comments": [["Colby A.", "Report him to the rental office"], ["Siobhan L.", "The rental office is also him"]]},
	{"group": "rants", "likes": 190, "text": "RAVE: To the Island Electric crew who got our power back after four days. RANT: To Island Electric, for the bill that came the next morning.",
		"comments": [["Reggie B.", "Both can be true"], ["Bernice H.", "Mine went up sixty dollars and I was in Florida"]]},
	{"group": "rants", "likes": 527, "text": "RANT: Eleven hours in Emergency last night. The man beside me came in for his ankle. He left with a beard.",
		"comments": [["Kayleigh J.", "Only eleven? Lucky"], ["Gord W.", "Bring a lunch next time. And a hobby."]]},
	{"group": "rants", "likes": 41, "text": "RAVE: To the lady who let me in at the Tim Hardly's drive-thru. You restored my faith. RANT: To the guy behind me in the Dodgy who did not.",
		"comments": [["Clayton V.", "He was in a hurry to sit in the same line"]]},
	{"group": "rants", "likes": 298, "text": "QUESTION: Is there a family doctor taking patients ANYWHERE on the Island?",
		"comments": [["Tanner O.", "lol"], ["Ana C.", "Alberta"], ["Doug R.", "My vet is very good with people"], ["Darlene M.", "Join the list! Year five for me"]]},
	{"group": "rants", "likes": 77, "text": "RANT: To the tourist who stopped dead in the middle of Grafton to take a picture of a church. It's a church. We have four hundred of them.",
		"comments": [["Priya N.", "They're just excited"], ["Lorne P.", "Be nice, they spend money"], ["Wade E.", "Spend it faster"]]},
	{"group": "rants", "likes": 112, "text": "LOST: Black and white cat, answers to Gary. Does not actually answer to Gary. Last seen judging me from the neighbour's deck.",
		"comments": [["Jean-Guy B.", "Check the Megastore. Everyone ends up at the Megastore."], ["Trudy K.", "He's on my deck now. He's judging me too."]]},
	{"group": "rants", "likes": 365, "text": "RANT: Someone stole the patio set off my deck. If you're reading this, it's from Breezy Home and you're on the hook for the payments now. Forty more weeks. Enjoy, buddy.",
		"comments": [["Heather D.", "Best revenge on the Island"], ["Mohammed A.", "That's not a punishment that's a sentence"]]},
	{"group": "rants", "likes": 59, "text": "RANT: They paved my street in June and dug it up in August. It's November. There's a hole. The hole has a cone. The cone has a sign. The sign says \"Sorry for the inconvenience.\" It's been sorry for five months.",
		"comments": [["Wanda F.", "At least it's polite"]]},
	{"group": "rants", "likes": 144, "text": "RANT: Sold my mother's house in Brighton. Over asking. Lovely couple from Ontario. Drove by today and it's an Airbnb with a sign that says \"The Island Experience.\" Ma's clothesline is still up. It's in the pictures.",
		"comments": [["Bernice H.", "Book it and leave a bad review"], ["Siobhan L.", "$412 a night, I checked"]]},
	{"group": "rants", "likes": 23, "text": "RAVE: To whoever paid for my coffee at Tim Hardly's this morning. RANT: You paid for a small. I always get a large. Now I owe you and I'm still tired.",
		"comments": [["Colby A.", "Most Island post ever written"]]},
	{"group": "rants", "likes": 208, "text": "QUESTION: Did they ever catch whoever painted the cruiser outside the police station? Asking because it's still painted.",
		"comments": [["Reggie B.", "Evidence"], ["Tanner O.", "Budget"], ["Paulette G.", "Both"]]},
	{"group": "rants", "likes": 96, "text": "RANT: The bridge is free to come on and $20 to leave. Every time I go to Moncton I feel like a lobster checking out of a trap.",
		"comments": [["Gord W.", "Don't go to Moncton then"], ["Ana C.", "Gord where do you buy your pants"]]},

	{"group": "dating", "likes": 134, "text": "Anyone know this man? Says he's 6'1\", a \"business owner\" and \"new to dating.\" I've seen him on here four times. The business is a food truck. It doesn't have wheels.",
		"comments": [["Anonymous", "He told me 6'1\" too. He is not 6'1\" in any direction."], ["Anonymous", "RUN"]]},
	{"group": "dating", "likes": 211, "text": "Matched with a guy whose hobbies are \"fishing, travel and my truck.\" First picture, him holding a fish. Second picture, a different fish. Third picture, the truck.",
		"comments": [["Anonymous", "That's every man on the Island"], ["Anonymous", "That's my brother. Love him. Run."]]},
	{"group": "dating", "likes": 388, "text": "PSA: when he says he's \"basically separated,\" he means he sleeps in the basement. Ask me how I know.",
		"comments": [["Anonymous", "I'm the wife. Hi."], ["Anonymous", "The basement is very nice, for the record"]]},
	{"group": "dating", "likes": 259, "text": "Went on a date with a guy from Montague. Turns out we're third cousins. We figured it out at dessert. He still asked for a second date.",
		"comments": [["Anonymous", "Island dating"], ["Anonymous", "Third is fine. I checked."]]},
	{"group": "dating", "likes": 176, "text": "Has anyone dated a Tyler? Drives a lifted black truck, says he \"doesn't do drama\"?",
		"comments": [["Anonymous", "Which Tyler"], ["Anonymous", "There's forty of them"], ["Anonymous", "Yes. All of them. All of them are that Tyler."]]},
	{"group": "dating", "likes": 92, "text": "First date at Wyoming's. He asked to split the bill. Then he used my coupon.",
		"comments": [["Anonymous", "Keep the coupon book next time"]]},
	{"group": "dating", "likes": 640, "text": "UPDATE: I was the girlfriend. She was also the girlfriend. We met because of this group. We're going for brunch now. He's paying. He just doesn't know it yet.",
		"comments": [["Anonymous", "This is what the group is for"], ["Anonymous", "Can I come"]]},
	{"group": "dating", "likes": 147, "text": "He said he'd \"take me somewhere fancy.\" We went to the Maple Tire to look at a smoker. Then he bought the smoker.",
		"comments": [["Anonymous", "Did he at least let you hold the receipt"]]},
	{"group": "dating", "likes": 118, "text": "Anyone know a guy, early 40s, says he \"owns property\"? It's his mother's house. He owns the basement suite. He also rents it out. To himself.",
		"comments": [["Anonymous", "That's my landlord"], ["Anonymous", "That's my landlord's son"]]},
]

## ChipIn fundraisers: {by, title, raised, goal, text, comment: [who, text]}.
const CHIPINS := [
	{"by": "Brent S.", "title": "Help Brent Get His Truck Out of Impound", "raised": 40, "goal": 600,
		"text": "Brent made some mistakes (the police chase). Brent's truck shouldn't have to pay for Brent's mistakes.",
		"comment": ["Brent's mom", "$40. That's it, Brent."]},
	{"by": "Kayleigh J.", "title": "Mittens Needs Her Teeth Cleaned", "raised": 2450, "goal": 1800,
		"text": "THANK YOU EVERYONE!!! We went over! Anything extra goes to Mittens' birthday.",
		"comment": ["Darlene M.", "Can someone do one of these for my teeth"]},
	{"by": "Wade E.", "title": "Wade's Speeding Tickets", "raised": 15, "goal": 2200,
		"text": "Wade drives for SpudDash and has had a run of bad luck (doing 140 on the Arterial, three times).",
		"comment": ["Admin", "Wade, this is the fourth one of these."]},
	{"by": "Shelley M.", "title": "Kleenex for Shelley", "raised": 12, "goal": 25,
		"text": "Shelley has a cold and is out of tissues. Every bit helps.",
		"comment": ["Trudy K.", "Get well soon. Here's two dollars."]},
	{"by": "Darren P.", "title": "Darren's Interlock", "raised": 210, "goal": 1400,
		"text": "Darren needs an ignition interlock to get back to work. Darren would like everyone to know he only had two.",
		"comment": ["Breathe Easy Interlock", "See you soon, Darren!"]},
	{"by": "Garth R.", "title": "Times Are Tough for Property Owners", "raised": 0, "goal": 25000,
		"text": "Interest rates are up and my fourth Airbnb is struggling. Any amount helps a local landlord through a hard time.",
		"comment": ["Siobhan L.", "I'll chip in when you fix my sink, Garth"]},
	{"by": "Kirkwood Drive Residents", "title": "Fix the Pothole on Kirkwood", "raised": 3200, "goal": 3000,
		"text": "UPDATE: We raised it! The province says we're not allowed to fix their pothole without a permit. The permit is $3,400.",
		"comment": ["Doug R.", "Start a ChipIn for the permit"]},
	{"by": "Tanner O.", "title": "Send Our Family to Disney", "raised": 85, "goal": 14000,
		"text": "We've had a really hard year. We deserve this. Florida or Disney Paris, depending.",
		"comment": ["Lorne P.", "Depending on what Tanner"]},
	{"by": "Reggie B.", "title": "New Boat for Reggie", "raised": 60, "goal": 48000,
		"text": "Boat sank. Not getting into how. Everybody knows how.",
		"comment": ["Clayton V.", "We all know how, Reggie"]},
]

## Posts about the player's own chases ({colour}, {car}, {street} filled
## in, like the police radio). By what happened.
const ABOUT_YOU := {
	"chase": [
		{"text": "RANT: To the {colour} {car} that just went flying down {street} with half the police on the Island behind it. Some of us are trying to get to Tim's.",
			"comments": [["Marlene T.", "Saw it! Nearly took my mirror"], ["Brent S.", "My cousin's following it now"]]},
		{"text": "QUESTION: What's going on near {street}? Sirens for ten minutes and a {colour} {car} went by on the sidewalk.",
			"comments": [["Wanda F.", "Somebody's getting two years less a day"], ["Gord W.", "Less a day"]]},
		{"text": "There's a {colour} {car} leading the entire police force around {street} and honestly it's the most organized I've seen them.",
			"comments": [["Reggie B.", "Overtime's going to be something"]]},
	],
	"caught": [
		{"text": "UPDATE: They got the {colour} {car} near {street}. Two years less a day. Out by supper, probably.",
			"comments": [["Tanner O.", "Out by supper lol"], ["Heather D.", "He'll be back on here by Friday"]]},
		{"text": "Police finally caught that {colour} {car}. Took eleven cruisers and an FIP truck. One guy. Your tax dollars.",
			"comments": [["Doug R.", "Four point two million, I heard"]]},
	],
	"escaped": [
		{"text": "Did they ever catch the {colour} {car}? Police went up and down {street} for an hour and then just went for coffee.",
			"comments": [["Paulette G.", "No. Same as always."], ["Jean-Guy B.", "My husband saw it go into a car wash"]]},
		{"text": "So the {colour} {car} got away. The police have \"a strong lead.\" The lead is that it was a {colour} {car}.",
			"comments": [["Colby A.", "Case closed then"]]},
	],
}

## How long ago, for the posts that aren't yours.
const AGO := ["4 min", "12 min", "38 min", "1 h", "2 h", "3 h", "5 h", "Yesterday", "Yesterday", "2 d"]


static func fill(text: String, vars: Dictionary) -> String:
	for k: String in vars:
		text = text.replace("{%s}" % k, str(vars[k]))
	return text

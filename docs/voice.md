# The game's voice

How Trans-Canada Auto sounds, worked out with Joe a piece at a time.
**Every word a player reads or hears follows this:** radio, ads, signs,
billboards, people on foot, the police radio, jail screens, job and
delivery text, phone apps, Kinbook, shop names, loading-screen captions,
tutorials, menus, mission text. A new feature isn't finished until its
words are in this voice.

The short version: **a sketch show about the Island, written by someone
who lives here.** Dry, specific, true, aimed up, and a send-up of a
certain crime-sandbox series while it's at it.

## The rules

1. **Straight face, honest line.** Nobody knows they're funny. Everyone
   plays it sincere, and the true thing slips out near the end: what the
   company really thinks, what the customer won't admit, what the
   province actually did.
2. **Grown-up worries, not gags.** Rent, the house that was $150,000 ten
   years ago, the doctor list, eleven hours in Emergency, the power bill,
   the kid still in the basement at 37. The joke is that it's true.
   Clever beats silly: no puns, no wacky names for the sake of it.
3. **Specific and local.** Saturday morning at Countess Auto, the riding
   mower after the licence goes, Ontario buyers, the Tim's line out onto
   Riverside, "where the Zellers used to be", "who's your father?", the
   bridge you only pay to leave. A real Island habit beats a general joke
   every time. Use real streets and places; look up the current news
   when a joke's about it (the power company's rate fight, the premiers).
4. **Aimed up.** The landlord, the lender, the conglomerate, the
   province, council, the police and the FIP, the parties, the repeat
   drunk driver, the man with the lifted truck. Never the person who's
   struggling: the renter, the patient, the borrower are never the joke.
   Never anyone for their race, religion, sexuality, disability or
   anything else they're born with.
5. **Make fun of the bad thing, never make it cool.** Drunk drivers are
   the joke, with their "I only had two" and the businesses that live off
   them. No line that would work on a T-shirt for the wrong people.
6. **Made-up names only.** The world brands in the README's table;
   stand-ins for everyone else (the Blues and the Reds, the Fortress
   family of companies, the FIP). Close enough that Islanders get it,
   never a real politician, officer, party, business or private person.
   Never a claim about a real company (the cousins and the paving
   contract are "the same family").
7. **Everyone knows everyone, lightly.** "That'll be on Kinbook in ten
   minutes" is the joke. "Your mother knows" is a seasoning, not the
   meal: once in a while, not every other line.
8. **Vary the format.** A nature documentary, a phone menu, a press
   conference, a brand film, four attack ads back to back. The format is
   half the joke.
9. **Short, and end on the punchline.** Lines short enough to read at a
   glance. The last line is the punchline or the tagline, never an
   explanation of it.
10. **Adults are the audience.** Some swearing (the FIP says "goddamn"),
    not every line. No drug jokes. Nothing gross. Dark is fine when the
    target's right (the funeral home ad is the edge, and it lands on the
    health system).
11. **The send-up of the other series.** We do what it does, our way:
    the over-the-top police chase, the parody brands, the radio ads, the
    phone. Where it's anonymous, we're a town where everyone knows who
    you are.

## How dark or trashy, by place

| Where | How far it goes |
|---|---|
| Radio ads, billboards, signs | The sharpest: pointed, political, some dark (the funeral home ad, Cash-style lenders) |
| People on foot, SpudDash, jobs | Dry and quick, one line, grown-up worries |
| Police radio, jail screens | Institutions bickering: budgets, jurisdiction, paperwork, "four point two" |
| Kinbook | The trashy corner: call-outs, comment wars, who dated who (implied, never explicit), vague posts fishing for "u ok hun" (`docs/kinbook.md`) |
| Menus, tutorials, controls | Plain and clear first; one dry line at most |

## Tested with Joe: what landed and what didn't

| Landed | Why |
|---|---|
| Countess Auto as a nature documentary: "He went for one bolt" | A true Island Saturday, a format that's half the joke |
| Island Dream Homes: "You can't live here, but your money can" | Aimed at the speculators, true |
| MedLine Anywhere: "You're still on the list. This just helps you feel like you're not." | The honest last line |
| Breathe Easy Interlock: "Our customers are the most loyal in the country." "Please don't call a cab." | Mocks the drunk driver and the business, points at the right choice without a lecture |
| McGuinness Funeral Home: a life of waiting, "Finally, no wait" | Joe's idea; dark, but the target's the health system |
| Early Years, Eventually: the dad's "back in my day" rant | Joe's rant, given someone to argue with |
| Island Electric's phone menu, Election Week's four ads | Built from the real news, no real names |
| Kinbook's comment threads: "Halibut was 2019 for me" | The comments are the joke, and it's true of the Island |

| Didn't land | Lesson |
|---|---|
| A husband sneaking off to Maple Tire | Right joke, wrong store: it's Countess Auto (Princess Auto) and Saturday mornings. Get the local detail exactly right |
| The judge who's related to you | Not a real Island issue. Pointed only works if it's true here |
| "It's a lifestyle" for drunk driving | Would end up on a T-shirt for the wrong people |
| Payday lender "Cash Island" | Fine, but rent-to-own (Breezy Home: financing paper towel) is the truer Island target |
| Grocery CEO, tourism, hiring ads | Too general; could be any town |
| Kinbook's first, polite version | Too tame. The real groups are trashy, the comments go off on tangents |
| A real company named (Canada Packers, Sandspit) | Stand-ins or places only |

## Where the words live

- Radio ads: `docs/radio.md`
- Kinbook: `docs/kinbook.md` (the cast and running jokes), `scripts/ui/kinbook_*.gd`
- People on foot: `scripts/people/pedestrian_lines.gd`
- Police radio: `scripts/police/radio_lines.gd`; jail: `scripts/wanted/jail_lines.gd`
- SpudDash: `scripts/economy/spuddash_lines.gd`
- World brands: the README's table

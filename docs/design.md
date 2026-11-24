# Game design: online Charlatown

What the game is when it goes online, and how each piece works. This is
the plan we're building toward, worked out before any of it is built, so
every piece can be polished when it's built instead of reworked later.
**Nothing goes in this file that isn't one of the features below.** New
ideas go in "Parked ideas" at the bottom until we decide to take one on.

Numbers here are starting points for tuning, not final values. Each is
marked where it lives in code once it's built.

## What the game is

A driving sandbox in a real town, with the town's humour and a send-up of
a certain crime-sandbox series, where 40 to 48 people share the map at
once and keep running into each other. You can compete when you want, but
there's no blood, no killing, no drugs and nothing seedy. On foot you carry
a paintball marker. Nobody dies, you get painted.

**The pillars, in order. When two pull against each other, the higher one wins:**

1. **The town is the star.** Real streets, real buildings, real addresses.
   Someone who plays for a week should know Charlottetown better. A new
   delivery driver could learn their routes here.
2. **Other people are always nearby.** The map is small and full. Events
   pull people together so you keep running into them.
3. **Driving feels good.** Everything else happens around the cars.
4. **Funny, not kiddy.** Adult humour that's local and political, with
   made-up stand-ins. It should look cool to teenagers and adults alike.
5. **Competitive when you want it, never forced.** Every competitive
   thing is opt-in: you show up to an event to join it.

**It is not a paintball sim.** The marker is your on-foot toy, the way a
phone or a fist is in the other series. There's no loadout screen, no
gear stats and no ballistics menu. The gear (masks, jerseys, pods) is
something you wear because it looks good.

---

## 1. Sessions and the server

### Size
- **48 players on one server**, all on one map (inside the bypass).
- Servers fill to 48. Once a server has 40 players it's taken out of
  matchmaking for new solo joins, which leaves room for parties and
  friends joining by invite.
- **Parties of up to 8** join together and stay on the same server and
  the same event team.
- A server is a session, not a persistent world. Your money, cars,
  cosmetics, rank and leaderboard times are saved to your account. The
  state of the world isn't (paint, where cars are parked, events running).

### Who decides what
An authoritative dedicated server (headless Godot) decides everything
that matters for winning or for money: hits, outs, coverage, cargo
condition, event scores, payouts. Clients predict their own movement and
shots so everything feels instant, and the server corrects them.

| Thing | Decided by | Sent how |
|---|---|---|
| Your own car and body | You (predicted), checked by the server | Inputs up, state down |
| Other players' cars | Server | State snapshots, nearby ones often |
| A shot | Server confirms the hit | Only "fired: origin, direction, time, seed" |
| Splats on walls and ground | Each client, from the shots | Not sent at all |
| Paint on cars and players | Server | Hit list per car (see 3) |
| Cargo condition | Server | A number per load |
| Events | Server (the event director) | Event state, a few times a second |

### Sending less for faraway things
How often you hear about another player depends on how far away they are:

| Distance | Updates a second | What you get |
|---|---|---|
| Under 150 m | 30 | Everything: position, wheels, lights, horn, animation |
| 150–600 m | 10 | Position, heading, speed, lights |
| Over 600 m | 2 | A dot on the map and a far LOD if it's in view |

Shots from more than 300 m away aren't sent to you. Splats that far away
are smaller than a pixel anyway.

**Polish bar:** a car 20 m away never stutters, warps or slides sideways.
When the server corrects your own car you never feel it unless you were
really out of sync. Test with 100 ms of lag and 2% packet loss as the normal case.

---

## 2. The paintball marker

### Feel
- **Semi-automatic:** one ball per pull, up to 8 a second if you pull fast.
  Holding fire fires at 5 a second. You never run out mid-fight in a way
  that feels unfair.
- **Hopper of 40 balls.** A reload takes 1.6 s, with a visible pod swap.
  Topping up happens automatically when you're not aiming, so you rarely
  reload in the open.
- **Ball speed 75 m/s with a visible arc.** The ball drops noticeably past
  about 35 m and isn't worth shooting past 60 m. You can see the balls in
  flight: bright, with a short streak.
- **Spread** is tight while you stand still, wider while you run, and
  widest from the hip. Aiming (already built) tightens it.
- **Feedback when you hit someone:** a crisp "thwack" only the shooter
  hears, a small tick on the crosshair, and the splat. Out-confirms get a
  heavier sound and a ref whistle.

### Hits and outs (only inside events)
- **3 hits and you're out.** A head hit counts as 2. Hits wear off after
  6 s without being hit, one at a time, so a single stray ball doesn't
  follow you around.
- **Being out:** the ref whistle, your hands go up, and your marker
  lowers and can't fire. You walk off (a short "walk of shame" animation)
  and respawn after the event's respawn time (see each event). Outs are
  never shown with blood or falling down. You just stand there, painted,
  looking annoyed.
- **The rule outside events:** shooting a player who isn't in an event
  with you only paints them. They're never out and nothing else happens
  to them. You become wanted (see 7). Shooting a car paints it the
  same way. That keeps free roam fun to mess around in and hard to grief.
- **Friendly fire:** off. Hitting a teammate paints them but doesn't count.

### Shooting from cars
You can't shoot while you're driving. A passenger can lean out and shoot
at 0.5× the fire rate with wider spread. That makes a two-person car a
real team: one drives, one shoots. It matters most in Escort.

**Polish bar:** in a blind test, shooting feels more like a good arcade
shooter than a sim. You always know when you've hit, when you've been
hit, and how many more hits you can take (pips on screen, plus visible
splats on your own body).

---

## 3. Paint on the world

Splats are the main visual signature of the game. They must look great
and cost almost nothing.

### How long it lasts

| On | Lasts | Cleared by |
|---|---|---|
| **Cars** | Until cleaned | A car wash (about 8 s inside), rain (about 3 min of driving in it), driving into the harbour |
| **Players** | Until respawn | Respawning, going home, jumping in the harbour, rain (about 2 min) |
| **Walls, ground, props** | 20 min, fading over the last 2 | Age, the cap (oldest go first), rain (an area is clean in about 60 s) |

### Cars
- The server keeps the **last 32 hits on each car** (where on the car in
  its own space, the colour, the size). That's the car's paint, and it's
  what late joiners are sent. It's tiny.
- **Coverage** (0–100%) comes from those hits: the car's surface is split
  into about 24 panels (bonnet, roof, each door, bumpers and so on), each
  panel fills as it's hit, and coverage is the average. Escort and the
  delivery tips use it.
- **Drawn in the car's paint shader**, not with Decal nodes (decals don't
  work on the Compatibility renderer that old or basic graphics chips
  fall back to): the shader gets the 32 splats as a
  uniform array and draws each as a splat shape in object space. That's
  one material change and no extra draw calls. It works on every graphics setting.
- **Windscreen:** a hit on the windscreen blurs the driver's view in that
  spot. The wipers (a key) clear it in two sweeps. Rain wipes it on its own.
- **Drips:** fresh splats run a little for the first 20 s, done in the shader.

### Players
The same as cars on a smaller scale: the last 16 hits per body, drawn in
the body's shader. Splats show on clothes and on the mask.

### Walls, ground and props
- Each client makes these itself from the shots it hears about. They aren't sent.
- They're drawn as **flat quads in one MultiMesh pool**, laid on the
  surface the ball hit, with a few splat shapes from a texture array.
  Those are the cheap flat quads for repeated features from
  `docs/world_art.md`.
- **The cap depends on graphics settings:** 4000 on High, 2000 on
  Medium, 800 on Low. When it's full, the oldest splat goes first.
- **Event sites remember a mess level.** When an event ends, the server
  stores how many shots landed there. A player who joins or drives up
  later gets the site sprayed with that many seeded splats. So you see
  the aftermath at the Walmart lot even if you weren't there.
- They go through `tools/world_budget.gd` like everything else.

### Colours
Each player has a paint colour from a fixed set of 12, picked so that
any two read differently and none look like blood. There's no dark red,
and all of them are saturated and bright (neon orange, teal, hot pink,
lime, electric blue, yellow and so on). Events use team colours instead
(two from the set, chosen for contrast).

**Polish bar:** a painted truck reads as "that truck got lit up" from
100 m away. Splats sit on the surface they hit, never float, and never
flicker on a curb. The Low setting still shows paint on cars and players.

---

## 4. The event director

Every few minutes the server starts something somewhere and tells
everyone. This is what pulls 48 people into the same parking lot.

### How many at once
- **One event for every 14 players**, rounded up, with a minimum of 1 and
  a maximum of 4. At 48 players that's 4 events at once.
- There's a gap of 2 to 5 minutes before a new one starts after one ends.

### Where
Sites are hand-placed in a list (`data/event_sites.json`): parking lots
(Walmart, the malls, the Civic Centre, the university), parks,
the waterfront, school yards after hours, the exhibition grounds. Each
site says which event types it suits and has its zone shape.

To pick a site, the director scores every one that suits the event:
- **+ players within 1.5 km** (bring it to the people, but not on top of them)
- **− used in the last 3 events** (keeps it moving round town)
- **− within 800 m of an event that's running** (spreads them out)
- **+ a little randomness** so it's not predictable

### Which type
The director weights the six types by what's been run recently (no type
twice in a row) and how many players there are. Escort and Turf Claim
need at least 8 players nearby, the others 4.

### What every event goes through
1. **Announce (90 s).** An icon on the map and the minimap, a phone ping
   with how long it'd take you to drive there, a radio stinger and a line
   from the DJ. The site's zone shows: cones, tape and a bylaw
   "PERMITTED EVENT" sign.
2. **Live** (each type's own length). Players in the zone are in. Some
   types let you join after they start, others lock (see each).
3. **Results (20 s).** A scoreboard, payouts, a one-line joke from the
   radio about how it went.
4. **Aftermath.** The paint stays (see 3). The site is resting and won't
   be picked again for a while.

### Joining and leaving
- You join by **being in the zone when it starts** (or, for types that
  allow it, by entering while it's live). There's no menu and no queue.
- A prompt shows when you're in the zone: "In. Scrimmage starts in 0:42."
  Pressing a key opts out and you're treated as a bystander.
- **Teams** are balanced by the server when the event starts. A party
  stays on the same team, and teams are kept even by count first, then
  by rank.
- **Leaving the zone** during a live on-foot event gives a 10 s warning
  and then counts as out. Events where you drive have a bigger zone (see each).
- **Bystanders** inside a zone can't shoot event players and can't be
  shot out. Their shots go through event players as if they weren't there.

### Rewards
- Every event pays **cash and rep**. Winners get the most. Everyone who
  stayed to the end gets at least 30% of the winner's pay, so showing up
  is always worth it.
- **+15% for each friend in your party who also played it** (up to +45%).
  This is the "invite your friends" reward.
- Cash buys cars and cosmetics. There's no pay-to-win.

**Polish bar:** from anywhere on the map you can see within a few
seconds what's happening, where, and how long until it starts. Getting
into an event never takes a menu. An event never starts with 1 person in
it: if fewer than the minimum are in the zone at the start, it's cancelled
with a radio joke and those players get a small showing-up payment.

---

## 5. The events

### Hot Potato (the tag race)
A literal potato. Whoever has it scores. Everyone else wants it.

- **Players:** 4–16. You can join while it's live.
- **Length:** 5 min.
- **Zone:** about 1 km across, centred on the site. It's mostly a driving event.
- **Start:** the potato spawns in the middle of the lot on a pallet. The first to touch it has it.
- **Scoring:** 1 point a second while you have it. The most points at the end wins.
- **Tagging:** to take the potato,
  - in a car, touch the carrier's car at more than 10 km/h relative speed, or
  - on foot, get within 1.5 m of the carrier and press interact.
  - The new carrier can't be tagged for 3 s (no tag-backs).
  - Paintball hits don't take the potato. They just paint the carrier.
- **The carrier is easy to find:** their car's roof has a big potato on
  it and the car leaves a faint trail of steam. They show on everyone's
  map, with the spot updating every 4 s.
- **Leaving the zone with the potato** drops it at the edge.
- **Polish:** the potato makes a cartoonish sizzle that gets louder the
  longer one person has had it. The radio commentates on whoever's
  holding it ("Still the guy in the Corolla. Somebody do something").

### Scrimmage
A quick team paintball fight in a parking lot.

- **Players:** 8–24 (4v4 to 12v12). It locks when it starts.
- **Length:** 6 min, or first team to 30 outs.
- **Zone:** the lot. On foot only. The parked cars, carts, dumpsters and
  planters are the cover. If you drive into the zone while it's live,
  you're a bystander.
- **Respawn:** 5 s, at your team's end of the lot. You can't be shot for
  2 s after respawning, unless you fire first.
- **Win:** more outs at the end. A tie goes to whichever team took the
  last out.
- **Polish:** team colours on jerseys (a pinny over your own clothes),
  spawn ends marked with team flags, a ref whistle for each out, and a
  big horn at the end. The lot's existing cars are cover, so every
  Scrimmage plays a little differently with the real layout.

### Escort (Paint the Van)
One team gets a load across town. The other team tries to paint it.

- **Players:** 8–20. Escort team about 40%, painters about 60%. It locks
  when it starts.
- **Length:** up to 8 min.
- **The van:** a delivery van or a small truck with a real load (Cargo,
  strapped down with TieDowns) spawns at the site. The escort team
  chooses its driver in the first 10 s: whoever gets in first.
- **Route:** the destination is 2 to 3.5 km away, chosen from the
  site's list. The driver picks the route. Every road is allowed.
- **Escort win:** the van reaches the destination with **coverage under
  50% and cargo condition over 40%**.
- **Painter win:** coverage reaches 50%, or cargo condition falls to 40%, or time runs out.
- **How it plays:**
  - Painters paint the van from foot or from a passenger seat. Their
    own cars can block it and box it in. Ramming is allowed, but the
    real cargo physics punish it: a hard hit can shift or tip the load,
    which works for painters and against the escort.
  - The escort team gets the van through and can block painters with
    their own cars. Hitting a painter 3 times puts them out for 10 s.
  - The van's windscreen gets painted too (see 3), so the escort's
    passengers can only keep the driver's view clear by keeping painters off it.
- **Zone:** the whole map is in play for players in the event. Their map
  shows the van and the destination.
- **Polish:** coverage shows as a big bar at the top, the van's
  progress as a line on the route. The radio calls it like a sports
  broadcast. Arriving plays a loading-dock horn and a customer line.

### Turf Claim
Hold the lot.

- **Players:** 8–24, two teams. You can join while it's live (the team
  with fewer players gets you).
- **Length:** up to 6 min. The first team to hold the zone for 3 min in total wins.
- **Holding:** a team holds the zone while it has more players standing
  in it (on foot) than the other team. Equal numbers means contested and
  nobody's clock runs. Cars in the zone don't count. You have to be on foot.
- **Respawn:** 8 s, at the team's spawn about 150 m away (so getting
  back is a short drive or a run).
- **Polish:** the zone's ground slowly takes the colour of whoever is
  holding it (a shader on the event ring, not a texture). At the end the
  lot is covered in the winning team's colour for the aftermath.

### Flash Race
A start line appears. You have 60 seconds.

- **Players:** 2–16. It locks at the start.
- **Announce is shorter:** 60 s instead of 90, so it really is a flash.
- **Route:** a hand-made checkpoint route of 2–6 km on real streets
  (`data/race_routes.json`). Each route has its own leaderboard.
- **Start:** a standing start in a grid at the line. Cars are placed in
  the order they arrive. A 3-2-1 countdown, with lights.
- **Traffic stays on.** That's the town. Contact between racers is allowed.
- **Checkpoints:** big, readable gates. Missing one shows a "back" arrow.
  A short cut that skips one doesn't count.
- **Finish:** the order across the line. 90 s after the winner finishes
  it ends for everyone else.
- **Leaderboards:** each route keeps your best time, your friends'
  times and the all-time top 100, with the car you used. These are saved
  to your account, so you can brag about "the Mt Edwards run" outside
  the game.

### Car Meet
The chill one. People park, look at each other's cars and vote.

- **Players:** 4–30. You can join while it's live.
- **Length:** 6 min.
- **Zone:** the lot, with parking spots marked out. Park in one to enter
  your car. You can enter one car.
- **Voting:** walk up to any entered car (not your own) and press
  interact to vote for it. You get one vote, and you can change it until the end.
- **No shooting:** the permit says so. Shooting inside the zone gets you
  straight to wanted level 2, a "not at the car meet, buddy" from the DJ,
  and you're removed from the meet.
- **Win:** the most votes. A tie goes to the car entered first.
- **Painted cars are allowed and very much encouraged.** A paint-covered
  car can win, and it's often funnier when it does.
- **Polish:** a camera-flash sound when someone votes, the car's
  name and owner shown over each entered car, music from a parked car
  with its doors open in the middle of the lot.

---

## 6. Deliveries and SpudDash

The everyday thing to do between events, and the way you learn the town.
SpudDash is the in-game delivery app, a parody of the real ones.

### Jobs
- Jobs are on your **phone** (a SpudDash screen). Each shows the pickup
  and drop-off as **real street addresses**, the load, the vehicle it
  needs, an estimated time and the pay.
- There are always 3 to 5 jobs on offer, from places near you. A new set
  comes every couple of minutes.
- **Vehicle classes** set what you can take: your own car (small bags
  and boxes), a van (crates), a truck (pallets, which need a forklift at
  one end or both, using the existing forklift and Cargo).
- **Each job has a client and a line of text**, written for laughs ("Two
  dozen eggs for the potato lobby's breakfast meeting. They're very
  nervous about eggs").

### Cargo condition
- Condition comes from the real cargo physics that are already built:
  hard hits, the load sliding, tipping, falling off. The server tracks it
  as 100% down to 0%.
- **Fragile loads** (eggs, a wedding cake, a lobster tank, glass) lose
  condition faster. **Tough loads** (bricks, potatoes, lumber) barely do.
- Falling off isn't a fail. You can put it back (by hand or forklift),
  but condition drops a lot.

### Pay and tips
```
pay = base × time × condition × local_knowledge
tip = pay × customer_mood
```
- **time:** 1.2 at half the estimate or faster, 1.0 at the estimate,
  then down to 0.6 at twice the estimate. A delivery can't fail on time.
- **condition:** from the cargo, 0.3 at 0%, 1.0 at 100%.
- **local_knowledge:** depends on the GPS mode (below).
- **customer_mood:** 0–25%, from condition and from **paint coverage**
  on the vehicle. A painted van loses some tip ("My order arrived
  orange"). The customer's rating comes with a line of text.

### GPS modes and local knowledge
You choose for each job:

| Mode | You see | Pay × |
|---|---|---|
| **Route** | The usual line on the road and the minimap | 1.0 |
| **Directions** | Turn-by-turn by street name only: "Left on Kent, right on Prince" | 1.15 |
| **Address** | Just the address. You find it. | 1.35 |

Street names are on the signs (already built), so Address mode is
always possible, just harder.

### Co-op
- A second player can ride along on a job and gets 50% of the pay
  (paid on top, not split). On truck jobs, one can drive while the other
  loads with the forklift.
- During a job, other players outside events can still paint your van
  (they become wanted for it). It costs you some of your tip but nothing else.

**Polish bar:** a delivery is fun on its own without anything else in
the game, the way a good delivery game is. The cargo feels heavy and
moves in a way you can read and plan for. The text is actually funny.

---

## 7. The police and the FIP (the wanted level)

What happens when you paint people or cars outside events. It's a chase
and a joke, never a punishment that ends your fun. **Speed and driving
never count.** Drive however you want.

Two forces, both made-up stand-ins:

- **Charlatown Police.** The city police (our Charlottetown Police
  Services). The cars already exist: white with a navy band, POLICE on
  the doors, the light bar and siren (`PoliceGear`, livery "police" in
  `car_models.gd`). They work inside the bypass.
- **The Federal Island Patrol, "the FIP."** Our stand-in for the
  Mounties. Big SUVs in knock-off federal colours (close enough that
  anyone gets it, different enough that it's ours: the band, the crest
  and the words are all our own). They patrol the outer ring (Riverside
  Drive, the Arterial, Upton Road, Capital Drive) and only come into
  the city when the city police call for backup. Their attitude: "Do you
  even know who we are? We're the goddamn FIP."

### Wanted levels

A spoof of the other series' over-the-top police chases: it starts as
one bored cruiser and ends with the FIP's very expensive toys. Each
level is a step up in craziness, and each one is still escapable.

| Level | Called | You got here by | What comes |
|---|---|---|---|
| 1 | **"Someone called your mother"** | Painting players who aren't in an event with you, their cars, or parked cars | One city cruiser comes to the area and searches it |
| 2 | **"Charlatown Police"** | Keeping it up, painting a cop, shooting at a Car Meet, or driving off while a cop has their lights on you | 2–3 cruisers chase you, two officers in each. They get out and come at you on foot with paintball markers |
| 3 | **"The FIP"** | Keeping it up at level 2, or painting the FIP on the ring roads (straight to 3) | The city calls the FIP in for backup. 4–5 vehicles. It gets aggressive: passengers lean out and paint your car, and they try PIT manoeuvres |
| 4 | **"Federal Overreach"** | Keeping it up at level 3 for about 2 more minutes, or painting the Tactical Unit's vehicle | The FIP Tactical Unit: the Paint Tank, harvester roadblocks, everything (below). It only lasts so long |

- The level is shown at the top of the screen with its name and a
  search circle on the map while they're looking for you.
- **The server runs the police** and keeps at most about 12 police
  vehicles out at once (plus one Paint Tank), shared among everyone
  who's wanted.

### Level 3: the chase gets aggressive
- **Leaning out.** Every police vehicle carries two officers. At level
  3 the passenger leans out the window and paints your car, the same
  way a player passenger does (section 2): slower fire, wider spread.
  They go for the windscreen, so you're working the wipers.
- **PIT manoeuvres.** A police vehicle can tap your back corner and
  spin you out, above about 40 km/h. It's a spin, not a crash: no
  damage beyond what the cargo physics do to your load, and you can
  drive away at once if they haven't boxed you in.
- **Paint is how they track you.** The more paint on your car, the
  longer they keep sight of it (coverage over 50% doubles how far they
  can spot you). A car wash both clears the wanted level and stops you
  being the bright orange car everyone's chasing.

### Level 4: Federal Overreach
The FIP's tactical unit shows up with gear bought for a city ten times
the size. The joke is the budget, and the radio and the jail panels
lean into it.

- **The Paint Tank.** A decommissioned armoured vehicle the FIP "just
  got funding for", with a paint cannon on the roof. It's slow and you
  can outrun it, but one cannon hit covers your whole car (100%
  coverage, windscreen blind until you wipe) and makes you easy to
  track. Its shots splat a huge area of road, which stays as an
  aftermath like an event site (section 3).
- **Harvester roadblocks.** A potato harvester rolled across the road,
  with an SUV either side. Very PEI. You go round, through a yard, or
  the other way.
- **More of everything.** The level 3 chase keeps going round the tank.
- **It runs out of overtime.** Level 4 lasts at most about 2 minutes.
  Then the radio announces the tactical unit has "exceeded its overtime
  budget" and the tank goes home, dropping you to level 3. That's what
  keeps it escapable, and it's part of the joke.

### How they catch you
- **On foot:** officers paint you out the same way events do: 3 hits,
  a head hit counts as 2. They aim like decent players, not perfect ones.
- **In a car:** they box you in. Stuck below about 5 km/h for 3 s with
  a police vehicle touching you and you're pulled over: caught.
- **Cartoon chaos, nobody gets hurt.** Spins, boxing in, paint and
  roadblocks. Never a crash shown as an injury, never anyone hit by a car.

### Keeping it fun, not hard
- The police drive about as fast as an ordinary car: a quick car can
  outrun them on the ring roads, and an old pickup can't.
- They take turns: only two vehicles are trying to box you in at once;
  the rest follow and cut off.
- No police at all inside an event zone that's live, so a chase never
  wrecks an event (and an event isn't a hiding place past level 1).
- Escaping should take about 1 minute at level 2, 2 at level 3 and 3 at
  level 4 for a decent driver. These are the numbers to tune toward.

### Getting away
- Get out of sight and outside the search circle, then stay out of
  sight: 30 s at level 1, 45 s at 2, 60 s at 3 and 4. Each level drops
  one at a time.
- **A car wash** washes off the evidence: straight back to 0. At level
  4 the car washes near the chase are "closed by order of the FIP" (one
  open, somewhere, and finding it is the escape).
- **Joining an event** clears level 1 only. You can't hide in an event
  once it's serious.

### Getting caught: Two Years Less a Day
Every arrest ends with comic-book panels, in the same inked, halftoned
style as the loading screens (`tools/make_branding.py`):

1. A judge bangs the gavel: **"Two years less a day."**
2. **"Time served: less a day."**
3. You walk out of the station with a fine (bigger at each level).

Caught at level 4, a fourth panel: **"Cost to taxpayers: $4.2 million.
Fine: $85."**

You're back outside the station in about 15 seconds. You don't lose a
day, a car or anything you own.

**About one arrest in eight, the case falls apart instead.** No fine,
and the radio news reports it with a straight face. Some of the lines:

- "The evidence was misplaced. Case dismissed."
- "Evidence locker flooded. Again."
- "The officer's notebook was used to prop a door. Case dismissed."
- "Court backlog. Your hearing is set for 2031. Free to go."
- "Released on a promise to appear. Nobody appears."

### The FIP's running jokes
All aimed at the institution, current, and true enough to sting:

- **Always short-staffed.** Backup is "unavailable, we're a few thousand
  officers short, please hold." FIP "Now Hiring. Seriously. Anyone."
  billboards on the ring roads. Some officers are visibly retirees
  brought back as reserves ("Reserve Constable Gerald, 71").
- **Jurisdiction.** The city and the FIP bicker over the radio when
  they're called in: "That's a city matter." "It's past the bypass."
  "We'll need that request in writing." Their arrival time is given as
  "after the paperwork." Every call ends with the city being billed.
- **"Do you know who we are?"** Self-important, and nobody's sure who
  they answer to. They know everything about you ("we have your
  licence plate, your face and your group chat"), and won't say how.
- **Trust.** A billboard: "The FIP. Some Islanders have some confidence
  in us!"
- **The budget.** The Paint Tank, the tactical unit, the drone that
  never launches. "Funded through the Island Safety Initiative" on the
  side of everything.
- **The recommendations.** "We've accepted all the recommendations from
  the review of the last review and will implement them shortly."
- **The classics.** The hat, the dress uniform for no reason, the
  horses (a horse trailer hitched to an SUV now and then), "we always
  get our man" (they don't), and saying sorry while arresting you.

Off-limits, here as everywhere (see 8): real tragedies, the people hurt
in them, and real officers by name. The joke is the institution, never
the victims.

---

## 8. Humour

The game's voice. The writing for everything above (radio, jobs,
tickets, loading-screen captions, signs) follows this.

- **Local first.** The bridge toll you only pay leaving, pothole season,
  tourist traffic in July, the potato lobby, the ferry against the
  bridge, everyone knowing everyone, "come from away", the one road
  everyone takes even though it's always backed up.
- **Pointed and true, aimed up.** Like the crime-sandbox series or a
  sketch show: not afraid to poke at real, current local issues, and
  some people will be offended. The justice system (two years less a
  day, lost evidence, court backlogs), the police and the FIP, council,
  the province, permits, committees, consultations, ribbon cuttings, the
  parking authority. The joke is always on institutions and the people
  with power, never on victims, real private people, or anyone for their
  race, religion, sexuality, disability or anything else they're born
  with. Never real politicians, officers or parties by name. Use made-up
  stand-ins, close enough that Islanders get it.
- **Brands are parodies.** Made-up names for every business, the way the
  map's ads already do it.
- **Adults are the audience, but nothing's gross.** No sex jokes, no
  drug jokes, no slurs, no punching down. Some swearing is fine (the
  FIP says "goddamn"), but not every line. It's dry, quick and specific.
- **The radio carries most of it.** One station (or two) with a DJ, ads
  and call-in segments. It reacts to events in the game (see each event's
  polish line), which makes the town feel alive with very little code.

---

## 9. Build order

Each step is finished and polished before the next starts, and each is
something you can play and show people.

1. **Online with 4 players.** A dedicated server, cars and people moving
   smoothly, sending less for faraway players. Tested with lag.
2. **Paint.** Shots over the network, splats on cars, players and the
   world, the car wash and rain, coverage.
3. **The event director, Hot Potato and Scrimmage.** Announce, zones,
   teams, results and rewards, from start to finish.
4. **SpudDash.** Jobs with real addresses, cargo condition, the GPS modes, tips.
5. **48 players.** Load testing, server hosting, matchmaking, parties.
6. **Escort, Turf Claim, Flash Race (with leaderboards), Car Meet.**
7. **The police and the FIP.** Wanted levels, the chase and arrests, the jail panels.
8. **Rain.** See "Decided". Turns on the rain lines in section 3.
9. **Proximity and party voice.** See "Decided".
10. **The radio.** Grows alongside everything from step 3 on.

## Decided

- **Hosting: OVHcloud VPS in Beauharnois, Quebec.** Close to the Island
  (about 25–40 ms from the Maritimes), unmetered bandwidth (a full server
  sends about 1 MB/s, which the big clouds bill for), and DDoS protection
  included. One VPS-2 (4 cores, 8 GB, about US$10 a month) for playtests
  through step 4, a VPS-3 (6 cores, 12 GB, about US$14) for 48 players,
  and one more per full server after that. How many players one server
  can hold is measured with fake players before step 5, since the
  server runs every car's physics. Accounts and leaderboards start as a
  small database on the same VPS, reached through a playtca.ca
  subdomain with a free Let's Encrypt certificate. Not
  chosen: AWS, Google Cloud and DigitalOcean (charges for outgoing
  traffic), Hetzner (2026 price rises, no Canadian location), Oracle's free
  tier (free accounts get shut down without warning; fine for tinkering).
- **Accounts: our own, in our own database.** Money, cars, cosmetics,
  rank and leaderboard times belong to the account, not to a storefront
  or another company, so a player keeps everything across Steam, itch.io
  and computers. Done in three stages:
  1. **While testing: no sign-up.** On first launch the game makes a
     secret key and keeps it on the computer, the server makes an account
     from it, and the player picks a name. Lose the key (a reinstall, a
     new computer) and the account is gone, which is fine for testing.
  2. **Before launch: email codes, no passwords.** A player types their
     email, gets a short code, types it in. That signs them in on any
     device and links the testing key to the account. We never store
     passwords. Sending the emails costs a few dollars a month at most,
     through a transactional email service.
  3. **Steam, when the game goes on Steam:** a storefront and a second
     way to sign in. Steam's login ticket is checked by our server and
     linked to the same account. It also gives us a store page with
     wishlists, Next Fest, one-click "join friend", what you're doing in
     your friends list ("racing on the bypass"), voice chat and
     achievements, through the GodotSteam add-on. The US$100 fee comes
     back once the game earns US$1,000 on Steam. Steam's chat lives
     in its overlay, not inside the game, so **in-game text chat is our
     own** (simple, over the game's own connection).

  Players will mostly come from the Island (word of mouth, local social
  media and news), not from Steam on its own. Steam is for looking
  legitimate, easy installs and updates, and friends joining friends.
  Not chosen: Discord as the account (ties players to another company),
  storing passwords ourselves.
- **Download only: no browser version.** The game has outgrown the
  browser: its renderer, memory and threads would mean cutting most of
  what makes the town look good, and browsers can't use the fast
  connection online action needs (UDP). So the game is a download
  (Windows first), and online play uses Godot's ENet over UDP. Instead,
  **it has to run well on a low-end PC**: the Low graphics setting, the
  Compatibility renderer fallback for old graphics chips and the drawing
  budgets (`tools/model_budget.gd`, `tools/world_budget.gd`) are what
  keep it playable there, and every feature here has to look right on Low.
- **Rain comes later, as its own step.** There's no weather in the game
  yet. Until rain is built, paint comes off with the car wash, the
  harbour and the timers in section 3; everything in section 3 that
  mentions rain switches on when rain is built. Rain is done properly in
  one go: wet, shiny roads, puddles, rain around the camera, the sound on
  the roof, a little less grip, working wipers, and one weather for the
  whole server.
- **Chat: text first, proximity voice after the 48-player step.**
  Online starts with text chat (nearby, party and event channels) and
  quick reactions. Proximity voice (you hear people near you, quieter
  with distance) and party voice (your friends anywhere on the map)
  come right after step 5. Voice follows the same rules as everything
  else competitive in the game: opt-in, never forced on you, and easy to
  get away from.
  - Voice is off until you turn it on. Push-to-talk is the default.
  - Mute anyone with one button (from the player list, or by looking at
    them). Block hides their chat and voice from you for good. Report
    sends the server the last 30 s of their text and who they were near.
  - Text chat has a word filter, on by default.
  - The account (see above) is what a block or a ban sticks to.
  These are built with chat, not after it: none exist in the game yet.

## Parked ideas

Ideas we liked but aren't building now. They don't go into the plan
above until we decide to.

- **Crews and turf across the map:** neighbourhoods taking the colour of
  the crew that holds them, won through events there.
- **A laser tag arcade** as one building in town.
- **The water truck:** a city water truck you drive round spraying
  paint off buildings, as a job or a mission (cleaning up after an event,
  say).

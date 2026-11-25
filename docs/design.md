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

**It is not a paintball sim.** The marker is your on-foot weapon, the
way guns are in the other series: you can buy bigger and sillier ones
and go on a rampage with the police if that's your night (section 2).
But there's no loadout screen, no gear stats and no ballistics menu.
The gear (masks, jerseys, pods) is something you wear because it looks
good.

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

### Markers and throwables you can buy
Like the guns in the other series: more money, bigger toys. Every one
is a different kind of fun, not just a bigger number, and each has a
made-up brand and a name. You own what you've bought and carry all of
it; a weapon wheel (hold a key) swaps between them. Prices get tuned
with the economy.

| What | Shown as | Called | How it plays |
|---|---|---|---|
| Stock marker | Paintball gun | "The Islander" (free) | Semi-auto, as above |
| Pump marker | Sniper rifle | "The Farmhand" | 1.5 shots a second, very accurate, out to 80 m. Each hit counts as 2. Has a scope: aiming looks down it (about 3x) |
| Full-auto | Rapid-fire gun | "The Lobbyist" | 15 a second, wide spread, a 100-ball hopper that empties fast. Hits count 1 |
| Paint grenades | Paint grenades | "Jam Jars" (carry 4) | Thrown, burst after 1.5 s: 2 hits on everyone within 3 m, and +15% coverage on a car |
| Paint launcher | Bomb launcher | "Tourist Season" (4 rounds) | Lobs paint bombs: 2 hits on everyone within 5 m, a direct hit on a car is +30% coverage. Slow to reload |

The plain "Shown as" label is what the weapon wheel, the HUD and the shop
lead with; the made-up name is the nickname under it (the names alone
don't say what each one is).

- Ammo is cheap and topped up at any convenience store, or for free at
  your home. You never have to grind to go out and have fun.
- **In events:** Scrimmage and Turf Claim are "league rules": the
  Islander and the Farmhand only, so they stay fair. Every other event,
  and free roam, anything goes.

### Controllers and aim assist
Controller and mouse players share every server and every event, so
controller aiming has to be good enough to compete without being a
crutch. Other games disagree on how far to go: Overwatch turns aim
assist off against PC players, Rainbow Six Siege has none and keeps
PC players apart, and Apex keeps it but cut it on PC (by 25% for a
controller on PC in 2024) after years of complaints that its
"rotational" assist tracked targets for you. We take the middle: help
the stick with what a stick is bad at (small corrections, following a
moving target), never aim for you, and never in a way a mouse player
can't see.

**First, the stick has to feel good.** Most "I need aim assist" is really bad stick handling:
- Adjustable inner and outer deadzones, a response curve (exponential
  by default, with linear as an option), separate look and aim
  sensitivity.
- **Turn boost:** holding the stick at the edge for 0.2 s ramps the turn
  speed up, so you can whip round to someone behind you, the way Halo
  and Destiny do it.

**Then two kinds of help, while aiming only (holding Aim), with a
controller only:**
- **Slowdown.** When the crosshair is over or just beside a target,
  look speed drops to 60%. It makes small corrections easy and does
  nothing if you don't put the crosshair there yourself.
- **Tracking.** When you or the target is moving and the crosshair is on
  them, the camera follows 40% of the target's movement across your
  view. You still do the other 60%. It's full strength out to 25 m and
  fades to nothing by 40 m, so it helps in a close fight and does
  nothing at range.

**Never:**
- no snapping onto targets against players,
- no bending paintballs towards targets (everyone's hits are the same),
- no help through walls or cover (it checks line of sight),
- no help onto anyone who's out, or anyone you can't hit (bystanders
  in an event zone),
- no help with a mouse, ever.

**Against the police it's a little stronger.** They're the computer, not
a person, so free-roam fights with officers get a gentle snap when you
start aiming: if an officer is within 25 m and 8° of the crosshair, the
crosshair eases onto them over 0.15 s. That's close to the other
series' "assisted aim". It's off in events, and off against players
everywhere.

**Settings:** aim assist Standard, Low (half strength) or Off, and the
stick settings above.

**Polish bar:** in a test range, a good controller player and a good
mouse player land about the same share of hits on a moving target at
10–25 m (within about 10%). The mouse player is clearly better past
40 m, and the controller player never feels the camera fighting them.

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
| **Route** | The way drawn on the minimap (and the town map), the turns, the pin | 1.0 |
| **Directions** | Turn-by-turn by street name only: "Left on Kent, right on Prince", and the pin | 1.15 |
| **Address** | Just the address. You find it. | 1.35 |

Street names are on the signs (already built), so Address mode is
always possible, just harder.

The way is never drawn on the road itself: only on the minimap and the
map. Waypoints you set yourself on the map always get Route. The modes
are `Gps.set_waypoint(at, name, mode)` with "route", "directions" or
"address" (scripts/ui/gps.gd); the turn panel over the minimap, the
route on the minimap and map, and the pin and distance follow it.

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

## 6½. Money: jobs, stores and property

What money is for, and how you earn it. The loop: **earn** (SpudDash, then
trucking jobs, then events) → **spend** (cars, trucks, gear, upgrades,
parking and property). Each step up opens the next way to earn: a better
car makes deliveries quicker, a trucking licence opens bigger jobs. Most
real buildings stay scenery: only our own stores and a few service places
do anything, and only they (and places you've found) get map icons.

### Decided
- **The trucking company is Delayed & Lost Trucking**, our Day & Ross.
  It runs out of the truck yard on Riverside Drive (the McQuaid's lot,
  map_config.json "work_yard"), rebranded: their trucks, signs and a
  dispatch window where you pick up work. *As built:* a two-storey
  dispatch office by the gate on Garfield Street (the window and the
  Surplus counter at its door), a truck shop with four bays and a
  warehouse with loading docks down the yard's east side, all in the
  company's white, black and orange, inside a barbed-wire fence.
- **You can buy your own trucks** and customize them, like cars. The
  company lends you one for each job until you do. Delayed & Lost sells
  its retired fleet at the yard ("Delayed & Lost Surplus": as described,
  mostly).
- **Armour is consumable, like body armour in other games**: an armour
  bar beside your hit pips that takes paint hits first. Plates bought at
  Ervin's fill it; when it's gone, hits count toward being out again.
- **The hotel is the Delta at the bottom of Queen Street** (OSM way
  28326186, the 27 m tower by the water), as the **Gamma Prince Edward**.
  A suite there comes with spaces in its underground parking, and you
  can make it home (you start the game there).
- **No fuel.** Gas stations sell paint, throwables and armour instead.
- **Armour, as built:** up to 3 plates worn, $150 each; a plate takes one
  hit (a head hit, worth 2, breaks two). Only hits that would count use
  plates, so outside events they're left alone. Kept in the save
  (GameState.items "armour").
- **Tow straps stay free:** every vehicle carries a 9 m strap, so nobody
  is ever stuck for want of one. Maple Tire sells a 15 m recovery strap
  that works as soon as you have it.
- **The map shows what you can use.** By default only places you can do
  something at (counters: stores, food pickups, job boards, dealers,
  parking, your place, the police, car washes) and the big landmarks to
  find your way by (parks, water, the civic buildings). Churches,
  schools, banks and other brands' stores are behind a "Points of
  interest" toggle, off to start with.

### Earning
**SpudDash** (section 6): food runs in your own car, from restaurant
drive-thrus to real house numbers. The starter job, from the first minute,
about $80–250 a run. As built (scripts/economy/spuddash.gd): orders
come from the food places within 1.2 km of you (the brands' drive-thrus,
and downtown the town's own restaurants under made-up names,
data/city/kitchens.json) to homes and apartments 250–1,300 m from them.
You stop at the drive-thru (or out front) and walk it to the door at the
other end. Food condition drops with hard hits, big jolts and rolling,
faster for fragile orders; the tip's mood is 25% × the food (none at 35%
or less) × the paint (none at 35% coverage).

**Delayed & Lost** (the yard's dispatch window; a truck lent for the job):

| Job | Truck | What you do |
|---|---|---|
| Tow | Rollback | Breakdowns and badly parked cars to the yard or the impound lot |
| Building supplies | Flat deck with a crane (the Fjord F-750 Picker) | Pick up at one to three hardware stores (The House Depot, Hearth Hardware, Countess Auto), drop at houses: lumber on the lawn, pallets in the driveway, set over the fence from the street with the crane |
| Freight | Hauler and flatbed trailer | Longer hauls between big sites (the Megastore, the oil terminal, Red Shores), backing up to the dock |
| Yard | Forklift | Load your own truck before you go |

*As built (building supplies, `supplies.gd`, `crane_tool.gd`):* the
order waits on the ground in each store's lot and goes on the deck with
the crane (legs down first; then the driving controls work it: steer
swings, throttle and brake luff the boom, Y/H fold it out and telescope,
R/G the hook, T hooks or lets go, Space folds up). Each house has a 2.5 m
ring on the ground, 5–8.5 m in from the middle of the street (in reach
of a truck at the curb); the drop counts once the right load sits in it,
upright and off the hook. Condition: −12% a hard knock (a drop, a load
banging the headboard), −25% a load left on its side. Pay is $300 +
$140 a load + $0.20 a metre of the route + $80 a store after the first,
kept to $500–1,500 before the time and condition factors. The crane
lifts 8.5 tonne-metres (2,500 kg close in, about 1,200 kg at its full
7 m reach): a pallet of bricks has to come in a little. Until the
dispatch window is built, the orders are a counter at the yard's crane
truck.

The **licence ladder** is a count of finished jobs (GameState.jobs_done),
no experience points: three SpudDash runs open tows, three tows open the
crane truck, three of those open freight (DelayedLost.LICENCES, for any
code that needs to know).

How a Delayed & Lost job runs (scripts/economy/delayed_lost.gd): the
window lists offers of each open kind (locked ones say what they need);
taking one lends its truck (and a trailer for freight) in a free yard
bay, with a first stop to get in it, unless you're in your own truck of
that model or one of the yard's; bringing the lent truck back is the last
stop, or it's towed back for $150 if you give up with it out of the yard.
A tow's pickup counts once the car is strapped on with the deck up, and
knocks on the way cost pay; freight's drop pays by the loads still on the
trailer. Freight sites: the Megastore, Ervin's Marine Terminal (the oil
terminal), Red Shores and the Seaport.

**Events** pay as in section 4.

### Spending
- **Maple Tire** (big box): car gear: a recovery strap, winches, roof
  lights, lift kits, all-terrain tires (they matter in the mud and sand),
  roof racks. All but the strap go into your items (GameState.items) for
  the custom shop to fit. **Maple Money**: 5% back on the cash paid, kept
  in cents, spent before cash there.
- **Ervin's** (every gas station): paintballs (every hopper full), Jam
  Jars, the markers, armour plates; at the door on foot and at the pumps
  from the car. Masks wait for clothes that can show one.
- **The custom shop** (a new place): upgrades for cars and trucks you own:
  engine (CarParts), tires, suspension and lift, a front winch, paint and
  wraps, horns, tint. Kept in the vehicle's mods.
  *As built:* **Red Dirt Kustoms**, in the Mufflercentre at Belvedere
  Avenue and Brackley Point Road (OSM way 361875733), a bay you drive into
  on the south side. Engine stages 1–3 ($3,000, $7,500, $18,000, in order),
  performance / all-terrain / mud tyres ($1,800 / $2,400 / $4,200; the
  last two win back 45% / 70% of the grip soft ground takes away,
  "tyres.offroad"), sport suspension or a lift kit ($3,500 / $4,800), big
  brakes, short gearing, weight reduction, a winch ($3,500), horns and
  paint in twelve named local colours ($1,200, trucks $2,500): about
  $50,000 for a full build. Maple Tire kits ("winch_kit", "lift_kit",
  "all_terrain_tyres" in GameState.items) are fitted for $250–600 labour.
  Work trucks take all but the car-only parts. No tint or wraps yet: the
  glass and paint are baked into each model's shared meshes, so they'd
  need a way to vary those without a new mesh per car.
- **Dealers** (already selling), plus a **used lot** at Reliable Motors on
  John Yeo Drive with beaters at $3,000–8,000, and the **Delayed & Lost
  Surplus** trucks.
  *As built:* **Mostly Reliable Used Cars**: the 12 cars nearest the
  showroom are new Dodgys, then up to 14 older models (map_config.json
  "used_lot") at $3,495–7,995, each with its mileage and a note, priced by
  its spot so it doesn't change. **Selling** (there or at the custom shop):
  half what you paid plus a quarter of what the shop put into it.

### Property: where your vehicles live
How many vehicles you can keep is how many spaces you have
(GameState.storage_spaces): one free (the street), plus each property's.

| Place | Spaces | Also | Price (rough) |
|---|---|---|---|
| The street | 1 | | free |
| Parkade pass (Queen, Pownal or Fitzroy: already built) | 2–3 | the cheapest storage | ~$5,000 |
| Suite at the Gamma Prince Edward | 4 (underground) | home: you start there; change clothes | ~$40,000 |
| Waterfront warehouse | 8 | your own custom-shop bay | ~$120,000 |

Your phone can have a stored vehicle brought round to the curb for a fee.
No rent and no passive income: property is for storage and convenience.

As built (scripts/economy/properties.gd): passes are $5,000 (Queen, 3
spaces), $4,000 (Pownal, 2) and $5,500 (Fitzroy, 3), sold at a pay machine
by each parkade's way in, with marked stalls on the second deck. The suite
is $40,000 at the front desk on Queen Street; its four stalls are in the
parking under the hotel (scripts/world/underground_garage.gd: a way in
through the Queen Street wall, a ramp down, a stall level under the
building). The first suite becomes home; any place can be made home, and
you start in the aisle by your first stall. A stored car is off the street
but shown in its stall while you're near; getting in takes it out. The
valet ("Bring it round", the map's Garage tab) is $150, and won't come
while you're wanted. The waterfront warehouse isn't built yet.

### Pacing (to tune by playing)
First hour: $3,000–5,000 from SpudDash, a used beater and some gear. First
few evenings: trucking jobs at $500–1,500, a dealer car and a parkade pass.
Later: the suite, the warehouse, upgraded cars and your own trucks.
Something new should always be one or two sessions away.

### How it's built (scripts/economy/)
Shared pieces, under one **Economy** node (economy.gd): **OwnedCars**
(your vehicles in the town, kept between sessions where you left them),
**Counters** (a spot and a card of things to buy or jobs to take: every
store, window and drive-thru), **Jobs** (one job at a time, stop by stop,
the GPS pointed at each with the job's help mode, paid by section 6's
formula), **Addresses** (data/city/addresses.json: about 1,700 real house
numbers, each with its way in from the street) and the map's tabs
(WorldMap.add_tab: the phone). Each feature is a module listed in
Economy.MODULES and keeps to its own files. tools/economy_check.gd checks
the shared pieces. **Stores** (stores.gd) finds every store of a world
brand from locations.json and the buildings of the chain it replaces,
and puts the counter outside the front (facing the pumps, or the big
box's entrance on its lot); **Armour** (armour.gd) keeps the plates on
the player's BodyPaint in step with the save. tools/stores_check.gd checks
them.

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

A spoof of the other series' over-the-top police chases, and **as hard
as theirs**. This is for people who play those games; it isn't watered
down. Level 1 is easy to shake, level 2 takes real driving, level 3 is
a fight, and most people caught at level 4 deserve it.

| Level | Called | You got here by | What comes |
|---|---|---|---|
| 1 | **"Someone called your mother"** | Painting players who aren't in an event with you, their cars, or parked cars | One cruiser comes straight to you and follows. Lose it or stop |
| 2 | **"Charlatown Police"** | A few more hits, painting a cop, shooting at a Car Meet, or driving off while a cop has their lights on you | 3–4 cruisers, two officers in each. They chase, cut you off at junctions, and get out and come at you on foot |
| 3 | **"The FIP"** | Keeping it up at level 2, or painting the FIP on the ring roads (straight to 3) | The city calls the FIP in. 6–8 vehicles. The FIP's SUVs are as quick as a fast car. Passengers lean out and paint you, they PIT you, and they set paint strips and roadblocks ahead of you |
| 4 | **"Federal Overreach"** | About 90 s more at level 3 (as built: 260 s in sight, so a 3–4 minute level 3 chase can still end in an escape), or painting the Tactical Unit's vehicle | Everything at level 3, plus the FIP Tactical Unit: the Paint Tank and harvester roadblocks (below) |

- The level is shown at the top of the screen with its name, and a
  search circle on the map while they've lost sight of you.
- **Every wanted player gets their full chase.** There's no shared pool
  that runs dry: each level has a force it always gets (level 1: 1
  vehicle, 2: 4, 3: 8, 4: 8 and the Paint Tank). See "How there are
  always enough police" below.

### What police paint does to your car
Player paint on cars is only paint (except that Escort counts it). **The
police use "FIP-issue Evidence Paint", quick-setting**, approved
"after a 14-month procurement process", and it gums your car up. Their
hits fill the same coverage as in section 3, and coverage now does
something:

| Coverage | Your car |
|---|---|
| 0–50% | Just painted. The windscreen blurs where it's hit, until you wipe |
| 50–80% | They can spot you twice as far away. You're the orange car |
| 80–100% | Paint in the air intake: the engine coughs, and top speed and acceleration drop by a third |
| 100% | **The engine stalls. The car's done.** Get out and run |

- **A fresh car doesn't save you.** If police see you get into another
  car, they're on that one now, and you've lost the seconds it took
  (getting in and starting it takes about 2 s, and officers rush you the
  moment yours stalls). Switching cars **out of sight** is a real way to
  lose them, the same as in the other series: it's the seeing that matters.
- **A stalled car is impounded** when the chase ends. You get it back
  from the impound lot for a fee ("Open Tuesdays, 10 to 11:30"), or for
  free next session. Your own cars are never lost for good.
  *As built (single player):* the lot is a pay machine beside the police
  station (`ImpoundLot`): $95, plus a $25 "after-hours convenience fee"
  unless it really is a Tuesday between 10 and 11:30; free once a new
  session has started. A stalled car you're still sitting in when the
  chase ends is towed once you walk away from it.
- **Your paint works on them too.** A passenger in your car (a friend)
  can paint police vehicles back, by the same table: get one to 100%
  and it stalls. That's how a two-person car fights its way out. It
  raises the level, of course.
- A car wash clears coverage along with everything else (below).

### How they catch you
- **In a car:** two ways. Box you in (stuck below about 5 km/h for 3 s
  with a police vehicle touching you), or stall your car with paint and
  then catch you on foot.
  *As built:* "touching" is within half a metre of your sides or a metre
  of your ends, or a police vehicle stopped across your nose or tail
  within 3 m (the autopilot's box-in stops just short of the bumper); you
  can still back out inside the 3 s. Tuned from tester runs: 4 s at levels
  2 and 3 and 4.5 s at level 4, and a roadblock's parked cars don't count
  (nosing up to one isn't an arrest). A stalled car with you in it is
  caught when an officer on foot reaches your door. At level 1, stopping
  for the cruiser (within 14 m for 4 s) is being caught: "Lose it or stop".
- **On foot:** officers paint you out the same way events do: 3 hits,
  a head hit counts as 2. At level 3 and up they aim well, and they
  come in pairs.
- **Cartoon chaos, nobody gets hurt.** Spins, boxing in, paint, strips
  and roadblocks. Never a crash shown as an injury, never anyone hit by
  a car.
- **What it costs you:** a fine that grows with the level, plus any
  load you were delivering, which is "seized as evidence". The fine is
  never more than 10% of your cash, and nothing else is lost: not your
  cars (see the impound above), not your markers. Spending a whole night
  running from the police has to be something you can afford to do, the
  way it is in the other series. Deliveries and events pay for it.

### Smart police
The police have to be a worthy adversary: smart, not cheating. Being
chased by them should be the best part of the game.

- **They only know what they've seen.** Each officer has eyes (a sight
  cone that's blocked by buildings and cars) and ears (shots, horns,
  crashes nearby). *As built:* eyes per car (and per officer on foot),
  ears for your shots only (70 m) so far; a car they haven't seen you
  get into is only recognised as you within 22 m, so switching cars out
  of sight works. What one officer sees goes out over the radio, and
  everyone gets your last known position, your car and its colour. They
  never just know where you are.
- **They think about where you're going.** From your last known
  position, speed and heading, the dispatcher (a planner on the server,
  using the road graph) guesses the streets you'll take and sends units
  to cut you off there, not just behind you.
- **They have jobs.** The dispatcher gives each vehicle a role and
  swaps them as the chase moves: chasers (stay on you), blockers (get
  ahead, box in, set roadblocks and paint strips), flankers (run the
  parallel streets), and a spotter that hangs back to keep sight of you.
- **They come by road, and get aggressive up close.** Police heading
  to you, patrolling or searching always drive the streets, like real
  responders. Only once they're within chasing distance (about 120 m,
  or in sight) do they get aggressive: following you off the road
  through lots, lawns and fields, cutting corners and taking shorter
  paths. Lose them past about 200 m, or out of sight for a few seconds,
  and they're back on the roads.
- **They search properly.** When they lose you, they spread out across
  the search circle, check the likely streets and lots first, slow down
  and look down alleys, and come back past where they lost you.
- **On foot they fight like a team.** Pairs, using cover, one keeping
  you pinned while the other flanks. They don't run out into the open
  in a line, and they back off and wait for help if you're winning.
- **They make human mistakes.** They lose you at junctions sometimes,
  crash into each other in tight spots, and don't see a car tucked in a
  dark driveway. *As built:* a chaser 25–120 m behind misses your turn
  at a junction about one time in five (city) or ten (FIP), a little less
  at level 4, overshoots and turns back; the FIP arrives at level 3 "after
  the paperwork" (8–16 s after it's called); only the FIP does the PIT. That's what makes escaping feel earned instead of
  scripted.

### Shooting your way out
- **Officers are out at 3 hits** like anyone else. They don't fall
  down. They put a hand up the way people do at paintball or airsoft,
  say something, and walk off out of the chase. Some of what they do:
  - walk back to the cruiser and start on the paperwork,
  - get on the phone to their union rep,
  - "That's going in my report," and a long sigh,
  - sit on the curb and check their overtime on their phone,
  - an FIP officer: "Do you know who I am?" and nobody does.
  They're gone from the chase after that, and the dispatcher sends a
  new unit to replace them (see "How there are always enough police").
- **You can always tell an officer is out.** It has to read instantly,
  across a parking lot, in the middle of a fight:
  - the "I'm out!" call and a ref whistle, the same as in events,
  - a hand straight up and the marker held up over their head, barrel
    pointed at the sky,
  - a bright yellow "OUT" vest pulled on over the uniform,
  - their dot gone from your minimap,
  - they can't be hit any more (balls pass through), and your crosshair
    doesn't react to them.
- **Police vehicles stall at 100% coverage** (above). Both officers get
  out and keep after you on foot until they're out too.
- Painting police raises your level, so shooting your way out is a
  choice: it works, and it makes the night bigger.

### How there are always enough police
The police aren't a fixed fleet driving across town. Like the other
series, they **appear where they're needed, out of sight**: a new unit
is placed on a road 300–600 m from you that no player can see, already
heading your way, and a unit nobody can see that's far from the chase
is taken away. *As built:* "can't see" is blocked by a building from
both your eyes and the camera, or more than 520 m off (a car's a few
pixels there; the far town has no collision to test against), or more
than 360 m off and outside the camera's view. So four stars always means a four-star chase, wherever
you are.

- **The server runs every police vehicle and officer.** Ones near a
  player get full physics. Ones no player is near (heading in, or
  searching a far corner) move along the road graph without physics,
  which costs almost nothing.
- **Chases near each other merge.** Two wanted players within about
  400 m share their units, and the force is the bigger of the two plus
  half the smaller. That's both cheaper and how it'd really go.
- **The cost.** Ten players at level 3 is about 80 police vehicles,
  more than the 48 players' own cars. That's the heaviest thing the
  server does, so it's part of the load test before step 5: if a VPS-3
  can't carry it, the server moves up to a bigger VPS (a VPS-4, about
  US$26 a month) rather than cutting the police. The police are the
  game; they don't get rationed.

### The Island-Wide Crackdown
When **5 or more players are wanted at level 2 or higher at once**, the
FIP declares an Island-Wide Crackdown. It's a server-wide moment, like
an event:

- Everyone gets it: a radio bulletin ("the Premier has been briefed"),
  a phone alert, and a red border on the map.
- Reinforcements "from the mainland, toll waived" join every chase: all
  wanted players get one level's worth more units (a level 2 chase gets
  the level 3 force, and so on), and the Paint Tank can come out at
  level 3.
- It lasts until fewer than 3 players are wanted, then the radio
  reports it "ended after a successful review".
- Getting caught during one adds a panel: "Crackdown statistics: 1
  arrest. Overtime: $11 million."

### Everyone can see what's going on
A chase is something to watch and join in on, not something happening
quietly to one player.

- **On the map:** every wanted player at level 2 or higher is shown to
  everyone, with their level, and police units near them show as
  flashing dots. Level 1 isn't shown (it's barely a chase).
- **On the radio and phone:** the news cuts in on big chases ("Live: a
  blue hatchback is leading Charlatown Police down University Avenue"),
  and a phone ticker lists the chases going on.
- **Bystanders are safe:** police only chase wanted players. Police
  paint that hits a bystander only paints them, and doesn't make them
  wanted. A bystander who paints police becomes wanted like anyone.
- **Friends can join in:** jumping in your friend's car, or painting
  the police chasing them, puts you in the chase too.

### Level 3: the chase gets aggressive
- **Leaning out.** The passenger in every police vehicle leans out and
  paints your car, the same way a player passenger does (section 2).
  They go for the windscreen first.
- **PIT manoeuvres.** Above about 40 km/h a police vehicle taps your
  back corner and spins you. *As built:* above 55 km/h (at 40 they lined
  up as you braked for a corner and missed). No damage beyond what the cargo physics
  do to your load, but you've lost speed and they're on you.
- **Paint strips.** The spoof of spike strips: an officer ahead of you
  throws a strip of slick paint across the road. Hit it and your tyres
  lose most of their grip for about 2 s. Drive round it if you see it.
- **Roadblocks.** Two cars across a street a few junctions ahead of
  you, placed where you're heading. There's always a way round (a
  sidewalk, a lot, a lawn), not always a good one.
- **They work together:** one or two try to box you in, one leans out
  and paints, the rest run parallel streets and cut off junctions.

### Level 4: Federal Overreach
The FIP's tactical unit shows up with gear bought for a city ten times
the size. The joke is the budget, and the radio and the jail panels
lean into it.

- **The Paint Tank.** A decommissioned armoured vehicle the FIP "just
  got funding for", with a paint cannon on the roof. Slower than you on
  the straights, but it heads you off, and one cannon hit puts your car
  at 80% at once. Its shots splat a huge area of road, which stays as
  an aftermath like an event site (section 3).
- **Harvester roadblocks.** A potato harvester across the road with an
  SUV either side. Very PEI. You go round, through a yard, or back.
- **It runs out of overtime.** After 5 minutes the radio announces the
  tactical unit has "exceeded its overtime budget" and the tank goes
  home, dropping you to level 3. Surviving that long is the brag.

### Getting away
- Get out of sight, out of the search circle, and stay out of sight:
  20 s at level 1, 60 s at 2, 90 s at 3, 2 min at 4 (as built: 60 s at 3, 90 s at 4, 60 s at a 4 that grew out of a level 3 chase). The circle is
  bigger at each level, and they search it, so hiding near where they
  lost you rarely works. Each level drops one at a time.
- **The car wash is the pay-and-spray.** Get into one without any
  officer seeing you go in and your wanted level is gone, at every
  level, along with all the paint. At level 3 or 4 that means losing
  sight of them for just long enough to get in: hard, which is what
  makes it great when you pull it off. If they see you go in, it does
  nothing, and they're waiting when you come out. (As built, at level 3
  or 4 a wash also needs 20 s unseen and the chase to have run 150 s at
  level 3 or above: straight from the crime into the nearest wash is
  "too soon", it takes the paint off but not the level.)
- **Joining an event** clears level 1 only. You can't hide in an event
  once it's serious, and police stay out of live events.

### Difficulty targets
What to tune toward, for a decent driver in an ordinary car:

| Level | Escapes | Takes |
|---|---|---|
| 1 | Nearly always | Under 30 s |
| 2 | Most of the time | 1–2 min |
| 3 | About half the time | 3–4 min |
| 4 | Rarely alone; better with a friend shooting back, or a car wash nobody saw you reach | 5+ min |

- The police are about as fast as an ordinary car at level 2, and the
  FIP's SUVs are as fast as a quick car from level 3. A fast car helps,
  but it isn't a free escape.
- No rubber-banding you can feel: they don't magically keep up, they
  out-think you (cut-offs, roadblocks ahead, the search circle).

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

## 7½. Town traffic

Ordinary cars and trucks driving round town, so the streets feel like
Charlottetown at the right time of day, and so a chase has something to
weave through. Built after the police, on the same autopilot
(`CarAutopilot`), so it's mostly behaviour and tuning, not a new driver.

### What they do
- **Drive like Islanders.** Keep right, follow one-way streets, stop at
  the traffic lights that already exist (`traffic_signal.gd`) and at stop
  signs, give way at roundabouts, signal, and drive a little under the
  limit. Now and then one does the local thing: a slow pickup, someone
  stopped in the lane to chat, a tourist braking at every street sign
  in July.
- **Where they go.** Each car picks a destination (somewhere real:
  a lot, a driveway, a business) and drives there by road, then parks
  or turns off and is replaced. They never drive off-road.
- **How many.** By time of day and place: busy downtown and on the
  Arterial at rush hour, quiet at 3 AM. Cars are placed out of sight
  of every player and removed out of sight, the same way the police are
  (section 7), so the streets near you are always populated and the
  rest of town costs nothing.
- **The mix** comes from the car models that already exist: hatchbacks,
  pickups, vans, the odd truck, in ordinary colours.

### Smart, not scripted
Good traffic matters to the game as much as good police: it's what you
weave through, hide in and crash into. Each driver thinks for itself
instead of following a track.

- **They look ahead.** Each driver watches the road in front (cars,
  people, things in the lane) and keeps a safe gap that grows with
  speed, so they brake smoothly instead of all at once.
- **They handle the real road.** Change lanes to pass a stopped car or
  make a turn, merge onto the Arterial and the ring roads by finding a
  gap, wait for a gap before turning left across traffic, and never
  stop in the middle of a junction when it's backed up past it.
- **They get round problems.** A blocked lane (a crash, a parked
  truck, a roadblock, a pile of paint-covered police cars) gets driven
  round when it's safe, or the driver turns off and goes another way.
  Nobody waits forever.
- **They react the way people do.** A car coming at them makes them
  brake, swerve or mount the curb to get out of the way; a person in the
  road makes them stop and honk; a crash makes them stop, then carry on
  or turn round. Reactions take a human moment (about half a second),
  so you can read and use them.
- **They recover.** A car that's been spun, bumped onto a lawn or
  shunted sideways gets itself back onto the road and carries on.
- **They're all a bit different.** Each driver has a few settings
  (how patient, how fast, how close they follow, how quick to honk), so
  traffic doesn't move like a train, and the odd one is slow, nervous or
  in a rush.
- **They're predictable enough to play with.** The same situation gets
  much the same reaction, so a good driver learns to thread traffic,
  use a bus to block a cruiser, or slip through a gap the sirens opened.

### Reacting to you and the police
- **Sirens:** traffic pulls to the right and slows or stops for a police
  car with its siren on, and edges out of the way at junctions. It makes
  chases look right, and it opens gaps the police can use (and you can
  steal).
- **Being hit or cut off:** they brake, honk, and sometimes stop and
  wait. They don't chase you or fight.
- **Being painted:** the driver stops, gets out and stares at the paint,
  or speeds off. Painting traffic is painting a bystander's car: it
  makes you wanted (section 7).
- **Getting in:** a stopped traffic car can be taken, like the parked
  ones (the driver gets out and complains). Taking one is seen as a
  crime the same as painting one.

### Cost
- Cars near a player get full physics. Cars no player is near move
  along the road graph without physics (the autopilot's road follower),
  so a busy town is cheap.
- A cap by graphics level for how many are drawn near you, and by the
  server's budget for how many it runs, measured in the same load test
  as the police (before step 5). Traffic thins out before police do.
- Their meshes are the existing cached car meshes and LODs
  (`docs/models.md`), so traffic adds instances, not new models.

**Polish bar:** sitting at a downtown corner for a minute looks like a
real minute in Charlottetown. Nobody drives through a building, gets
stuck in a junction, or stops dead for no reason.

### As built (single player)
The road manners are `CivilDriving` (`scripts/ai/`), switched on in
`CarAutopilot` with `use_civil_driving()`; the rest is in
`scripts/traffic/` (`TrafficManager`). Where it had to differ from the
above, or fill a gap:

- **Time of day.** The game has no clock yet, so traffic reads the hour
  from a node in group `game_clock` (its `hour`, and `month`) when there
  is one, and otherwise `TrafficDensity.hour`, early afternoon by default.
  The month for the July tourists is the real one.
- **Right on red.** After a full stop, when it's clear, as the Island
  allows. A whole red is 20.5 s (`TrafficSignal`), so waiting at a light
  doesn't count as being stuck.
- **Far traffic is drawn with the parked-car meshes.** Cars past the
  physics radius (130 m) are road followers drawn through one MultiMesh
  per model of the parked versions, out to 440 m: past the furthest a car
  is placed (380 m), so cars coming toward you are already drawn when
  they come into view rather than popping in. Far ones plan their speed
  10 times a second and look round for other cars every 0.3 s.
- **Thinning.** Each police vehicle being driven takes one traffic car's
  place under the cap (80, 12 of them with physics). The quietest place
  still gets 55% of the cap, and with the clock fixed at early afternoon
  (92% of the rush-hour count) downtown has about 73 cars round you.
- **Not by graphics.** How much traffic there is, where it's placed and
  taken away, and which cars get physics don't depend on the graphics
  settings, so every player gets the same traffic. Graphics only change
  how it's drawn. People on foot are the same (24 at once).
- **Many players (the server).** Traffic is for `TrafficManager.viewers()`:
  the local player, and `others` (on a server, every player; the server
  sets `local_viewer` off). It's counted by area, in 100 m squares
  (`TrafficDensity.cell_targets`): each player asks for the same number
  as single player, spread over the streets round them, and a square near
  several players takes the largest ask, not the sum, so players near each
  other share the same cars (up to `TOWN_MAX`, 1500, for the town). Cars
  are placed and taken away only where no player could see: for players
  other than the local one (no camera here) that's anywhere with a clear
  line to them, whichever way they're facing. With `TrafficDensity.server`
  on, only each player's 6 nearest within 80 m get physics (shared), and
  `Car.silent` skips engine sounds. `ChunkStreamer.extra_foci` keeps the
  town built (for collision) round every player. `tools/traffic_server.gd`
  runs it for 48 simulated players and measures a server tick.
- **Taking a traffic car** is its own crime, `take_car` (`Wanted`, at
  least level 1, one hit), reported by `TrafficManager`; painting one is
  already `paint_car`, reported by `main.gd`. A moving traffic car can't
  be got into.
- **The mix** is cars, pickups and minivans, and near the player only (they
  have no parked versions to draw far off) the odd rollback or tractor
  unit and the Charlatown Transit buses on two routes.
- **Big chases.** At Wanted level 3 and up with a siren within 320 m
  (`TrafficHeat`), about half the drivers ahead of the player or near a
  siren turn into a driveway just ahead and pull in; the cap eases down to
  60% (45% at level 4) and nothing new is placed in the cone ahead of the
  player, so the streets thin out without emptying. It eases back after.
  Traffic drivers out of their cars run from paint landing within 16 m,
  and a driver who runs leaves the car where it stands; people walking
  (section 7¾) run from paint within 14 m, and there are half as many of
  them out.
- **Tow trucks.** A car dead in the street (stalled by paint, on its roof,
  or left by a driver who ran) gets a rollback after a while
  (`TrafficTows`): 25 s for a traffic car, 40 s for the player's own car
  once they've walked away from it, and never while they're wanted (the
  police impound a chase car themselves). The truck pulls up past it,
  lowers the deck, winches it on and drives off; the player's car goes to
  the impound lot (`ImpoundLot.impound`). Back in it before it's on the
  deck and the tow's off. Out of the player's sight and over 140 m off,
  a dead car is just gone when its time's up (the player's to the lot).
- **Sirens and room.** Traffic pulls right only as far as the curb, or the
  strip parked cars stand in where a street has them, so on a narrow
  street with parking it mostly stops in its lane. A police car with its
  siren on goes out round traffic stopped or pulled over in its lane,
  into the middle of the road or the other lane, at a speed it could stop
  from (`SirenLane`), instead of sitting behind a queue at a red light.

---

## 7¾. People on foot

A few people walking round town, so the sidewalks aren't empty, with
something on their minds, and now and then one who wants a ride. Built
in `scripts/people/` (`PedestrianManager`, `Pedestrian`, `RideFares`,
`PedestrianLines`).

- **How many.** Up to 28 round the player on High (12 on Low), scaled
  by the place and the hour the same way as the traffic
  (`TrafficDensity`): busy downtown, a handful in the suburbs. They're
  placed 45–150 m away and taken away past 190 m, only where nobody can
  see (`TrafficSight`), and drawn out to 160 m. Each is a HumanoidModel
  (one draw call) in one of 32 looks, each look's body built once and
  shared, all built during the title screen.
- **Where they go.** Each heads for a real place (a `TrafficDestinations`
  driveway, lot or door) along the sidewalks (the middle of the walk,
  `RoadNetwork.Level.WALK`). At each junction they take the way that
  points nearer to it, with some chance in it: round the corner, or across
  a street (never a highway or a road over 18 m wide). At the place they
  cross to its side if they have to and walk in, and they're gone once
  nobody can see them (out again after 20 s if someone's watching).
- **Smart, not scripted.** They wait at the curb for a gap in traffic
  (at most 14 s: drivers stop for people in the road, which they're in
  the `people_on_foot` group for while crossing), keep right of people
  coming the other way, stop to chat with someone now and then, check
  their phone, and walk at their own pace (seniors slow, commuters brisk,
  the odd jogger).
- **Thoughts.** Now and then a thought floats over someone's head (pale
  blue): what a stroller, commuter, tourist, senior, jogger or teenager
  in Charlatown thinks about. At most three show at once, only within
  32 m of the camera, and each person waits 18–40 s between thoughts.
  What they say out loud (reactions, chats, rides) is white.
- **Reacting to you.** A car coming at them makes them jump clear (they
  never get hit: cars pass through people). Paint landing near them sends
  them running down the sidewalk; painting one is `paint_bystander`
  (their body is on the characters layer, which paint hits and cars
  don't). A marker pointed at them gets their hands up; walking into them
  gets a "Sorry!". In a big chase (Wanted 3+) half as many are out.
- **Rides (`RideFares`).** While you're driving and not wanted, every
  minute or so someone ahead stops at the curb and waves, with their
  offer over their head ($12 plus 5 cents a metre, straight line). Stop
  beside them and they get in the passenger seat, say where they're
  going (a real place, 400–1600 m off) and the GPS gets the way. They
  talk on the way: about your speed, every knock, taking too long.
  Stopping within 26 m of the place, they get out, pay and walk in:
  the offer × 1.2 for a quick ride down to × 0.6 at twice the expected
  time, × 0.85 for each crash, × 0.9 for driving fast more than once.
  Getting out, or the police getting involved, loses the fare.
  It's the first job, before SpudDash (section 6), and the same shape
  that one will take: a pickup, a real place, the GPS, pay by how it went.

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
   With it, the money side (section 6½): Delayed & Lost, the stores, the
   custom shop and property.
5. **48 players.** Load testing, server hosting, matchmaking, parties.
6. **Escort, Turf Claim, Flash Race (with leaderboards), Car Meet.**
7. **The police and the FIP.** Wanted levels, the chase and arrests, the jail panels.
8. **Town traffic.** Section 7½. Built on the police autopilot.
9. **Rain.** See "Decided". Turns on the rain lines in section 3.
10. **Proximity and party voice.** See "Decided".
11. **The radio.** Grows alongside everything from step 3 on.

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
- **Crash damage and things you can knock down:** cars that dent and
  break down from crashes, and lamp posts, signs, fences and the like
  that get knocked over. Wanted when it's built: it would add to the
  chases. The police and paint rules above don't depend on it.
- **The water truck:** a city water truck you drive round spraying
  paint off buildings, as a job or a mission (cleaning up after an event,
  say).

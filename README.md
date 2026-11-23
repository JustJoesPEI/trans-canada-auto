# Trans-Canada Auto (TCA)

An open-world driving game set in real Canadian places, built in Godot 4
with GDScript. Each map is a real place: the streets, buildings, parks and
woods come from OpenStreetMap, the ground, building heights and trees from
a real lidar survey. The plan is to grow a map at a time, the way the
Trans-Canada runs province to province.

**The first map is Sand Bar: Charlatown, Prince Edward Island**, our
Charlottetown, the way GTA's cities stand in for real ones. Signs and the
title screen say Charlatown; on the Island everyone just calls it town.
Right now it's a prototype that feels good to move around in, not a full game.

Website (coming): playtca.ca

**Status: all of Charlottetown inside the bypass is playable** (Riverside Drive,
the Arterial Highway, Upton Road and Capital Drive round the outside, the
North River and the harbour on the other sides), built and streamed in
around you as you go. It runs in Godot 4.7.2 with no errors. See "What has
been tested" below.

## Starting it

1. Install **Godot 4.7** (standard build, not .NET): https://godotengine.org/download
2. Open Godot, choose **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the play button). A loading screen stays up while
   downtown is built from the map data (a few seconds, done in small steps
   so the window, or the browser page, never stops responding), then the
   title menu comes up and the rest of the city fills in round you.

The first time you open the project Godot imports it, and you may see it
write `.godot/` and some `.uid` files. That's normal; `.godot/` is ignored
by git.

## Making a click-to-play version

The project includes an export preset for Windows. In Godot: Editor >
Manage Export Templates > Download and Install (once), then Project >
Export, pick "Windows Desktop" and Export Project. You get a single
`TransCanadaAuto.exe` (about 130 MB) with everything packed inside, including
the map data. Windows will warn the first time because the game isn't
signed: "More info", then "Run anyway".

From a command line, with the templates installed:

```sh
godot --headless --path . --export-release "Windows Desktop" export/TransCanadaAuto.exe
```

## New versions and itch.io

Every change pushed to `main` is built automatically for Windows and the
web by GitHub (`.github/workflows/build.yml`); the builds are kept on each
run under the repository's **Actions** tab. Once the itch.io key is set up,
the same build goes straight to the game's itch.io page, and the itch app
updates the game on your computer by itself. Setting up the page, the key,
the text and the images: `docs/itch-page.md`.

The browser version uses Godot's web export (the Compatibility renderer,
so it looks like Low graphics). It's about 60 MB to load the first time,
then cached, and it needs the "SharedArrayBuffer support" option on
itch.io so the town can be built on background threads.

## Branding

The name is a send-up of a certain crime-sandbox series, and the branding
plays along in our own way. Each map is an edition, titled the way that
series titles its editions, with the edition's name as the big thing:
ours is stamped on a licence plate, green on white like the Island's, with
TRANS-CANADA AUTO where the province would go, **SAND BAR** in the middle,
a made-up province along the bottom (Prince Eddie Island) and TCA on the
renewal sticker. `logo.png` is the series name on its own, for anything
that isn't one map. The loading screens are tilted comic-book panels over
screen-printed sunsets: the game's own screenshots, inked and halftoned,
with captions like "Nobody locks their car here." While the town builds,
the first one (the same picture as the boot splash) fades to a random
other one, with a tip along the bottom and a spinner by what's being built.

The logos, the loading screens, the title art, the window icon and the
itch.io cover, banner and background are all drawn by
`tools/make_branding.py` into `branding/`, from the screenshots in
`branding/screens/`, the poster ads in `textures/ads/` and the free fonts
in `tools/fonts/` (Anton, Bebas Neue and Graduate). Change the script and
run it again to redraw them all. A new map's plate is `EDITION` and
`EDITION_LINE` at the top of it; new loading screens go in
`loading_screens()` there and in `LOADING_ART` in
`scripts/autoload/title_menu.gd`.

The game opens on a **title menu** over the live town (Play, Graphics,
Controls, Credits, Quit); Esc brings it back as a pause menu. It's in
`scripts/autoload/title_menu.gd`.

## If nothing happens when you press play

* **Nothing opens at all when you start Godot:** make sure you unzipped
  Godot first and are running the `.exe` from the unzipped folder, not from
  inside the zip. Windows may show a "Windows protected your PC" box; choose
  "More info", then "Run anyway".
* **The Project Manager opens but the project isn't listed:** click
  **Import** and pick `project.godot` inside the unzipped `trans-canada-auto`
  folder.
* **The editor is open but pressing F5 / play does nothing:** look at the
  **Output** panel along the bottom of the editor and copy what it says.
  Also check the taskbar: the game opens in its own window, which can end up
  behind the editor.
* **The game window opens but stays black or grey:** older or very basic
  graphics chips can't run Godot's default renderer. Start Godot from a
  command prompt with `--rendering-driver opengl3`, or in the editor go to
  Project > Project Settings > Rendering > Renderer and choose
  "gl_compatibility". The game works in that mode too.

## Controls

| Action | Keyboard and mouse | Xbox controller |
|---|---|---|
| Walk | W A S D or arrow keys | Left stick |
| Run | Hold Shift | Hold A |
| Look around | Mouse | Right stick |
| Zoom camera | Mouse wheel, or + and - | D-pad up and down |
| Reset camera behind you | C | Click right stick |
| Driver's seat or chase view (in a car) | V | Back (View) |
| Menu (pause) | Esc | Start |
| Graphics High / Low | F10 | |
| Leave a note about this spot | N | |
| Open the folder with your notes | F9 | |
| Open the map editor (running from Godot) | F8 | |
| Get in or out of the car | E or F (at the driver's door) | Y |
| Accelerate | W or Up | Right trigger |
| Brake, then reverse once stopped | S or Down | Left trigger |
| Steer | A D or Left Right | Left stick |
| Handbrake | Space | B |
| Police lights, then siren, then off (in a police car) | L | D-pad left |

All bindings live in `scripts/autoload/input_setup.gd`.

## Leaving notes (and sending photos)

To point something out in the town, for a fix or something new to build,
aim the middle of the screen at it and press **N**. Type the note ("this
house is yellow with a red door and a white porch", "a gazebo goes here")
and press Enter. The game pauses while you type.

The note is copied to the clipboard, so you can paste it straight into a
chat with Claude. It reads like this:

```
TCA note 3, Sand Bar (2026-11-22 14:05:12): this house is yellow with a red door
  Looking at: building OSM way 28326012 "Queen Parkade", 26 m away, at 46.235931, -63.129089 (game x -271.3, z -143.3)
  Standing: on Grafton Street at 46.235493, -63.126560 (game x -76.1, z -94.8), facing north-west (315 degrees)
```

That's enough to find the exact building or spot. Every note is also kept
in `notes.txt` in the game's own folder (press **F9** to open it; on
Windows it's `%APPDATA%\Godot\app_userdata\Trans-Canada Auto`), so you can
send them all at once. A numbered orange pin marks each note's spot in the
town and stays there next time you play. Delete `notes.txt` and
`notes.json` to clear them.

**Photos** work the same way: take them with your phone's location turned
on for the camera, and send them as they are (not screenshots of them).
Phones record where each photo was taken and usually which way they were
pointing, so each one can be matched to its building. A photo straight on
to the front of a building, in daylight, is the most useful.

The changes from notes go in `data/map_config.json` under "landmarks", by
the building's OSM id. A small entry (just a colour, say) keeps the
building's measured lidar height and roof.

A chain's store can have a landmark entry too: it keeps the world brand's
name and colours, with the entry's settings on top. The Superstore at
University and Belvedere was built this way from a photo taken from the
lot: a mansard roof (a deep skirt of shingles coming down over a covered
walk on posts), glass along the front, and its two glass A-frame entrances
("entrances" in its entry), the clothing store's at the left and the
grocery's at the right, each with its own sign.

The oil tanks across Riverside Drive from the Grafton Street Tim Hortons
were done the same way, from a photo from the drive-thru: white steel
tanks (style "tank") with stairs spiralling up their sides and a railing
round the top, one with a dome and the oil company's name (Ervin's)
between a red chevron and a blue one. Map data converted from now on
keeps OSM's man_made tag, so any building mapped as a storage tank
becomes one by itself.

The Take 5 on University Avenue (our Take 6) was built for Pro Oil Change,
Valvoline's oil change chain here before Take 5 bought it, and it's built
the way Pro Oil built them everywhere: a low flat-roofed box with three
drive-through bays (a glass overhead door at each end of every bay, down
both long sides), an office window, a red band round the top, and a round
tower like a 20 ft oil drum standing out of one end, which is the way in
and carries the name ("barrel" and "bay_doors" in its entry). OSM maps the
drum's curve as part of the footprint and the lidar shows it standing
1.5 m over the roof, so the drum goes wherever a footprint has a round
part like that.

The city police station on Kirkwood Drive is the Charlatown Police
Services (CPS, same as the real one): a navy board with white letters
over the front, facing Kirkwood Drive.

The tank yard has a chain-link fence round it with barbed wire on top.
Fences go round any mapped area named in "fences" in
`data/map_config.json`, with gaps where streets and driveways cross.

Riverside Drive, from the Hillsborough Bridge to the Exhibition Drive
roundabout, was done from a video of the drive. It has:
- the Irving station's canopy and price sign (a landmark with "canopy" and
  "pylon")
- the blue warehouse and the grey building opposite in plain metal siding
  (style "plain")
- the Pollution Control Plant's plain brick buildings, chain-link fence and
  open tanks with railings ("area_styles", which styles everything inside
  a named area)
- twin-arm lights down the median ("median_lights")
- the green sign gantry and roundabout warning sign before the roundabout
  ("sign_gantries")
- wooden power poles and wires along the southbound side
  ("highway_power_lines")
- a bank of armour stone under the tank-yard fence ("riprap" on the fence)

Where OSM draws the two halves of a divided highway closer together than
their full width, their shoulders are trimmed (never the lanes), leaving
a curbed median between them instead of a sliver of overlapping road.

## World brands

Real chains in town are replaced by made-up ones, the way the cars are
(Dunmore, Hanaka, Fjord) and the way GTA does it. Each world brand keeps
the real chain's colours, so you know at a glance what it is, but has its
own name: Tim Hardly's for the coffee and donut shop ("close enough"), MacDougall's for the
burgers, SoBuys for the grocery store, and so on. Every location of a chain
changes at once, matched by the brand or name OpenStreetMap gives the
building, and new locations follow as they're mapped.

They're set in `data/map_config.json`: "brands" lists each world brand with
the real chains it replaces, its kind and its colours (`sign_colour` for
the board, `sign_text` for the letters), and "brand_kinds" gives each kind
its usual look. Grocery and big-box stores get a big sign high on the side
facing their car park (it grows with the store, about 4 m tall on a 100 m
front), a stripe of the brand's colour along the top of that wall, a dark
base, and a glass entrance vestibule under the sign, plus a second sign
facing the street. Coffee shops, burger places and gas stations get a board
over the door and a glass shopfront.

**Advertising.** A brand can list window posters ("posters"), which go up in
its shopfront windows at every location, a few per shop and a different
mix at each. Billboards are `sign=billboard` points with an `ad`, standing
by the road and angled toward drivers on their way to the shop. All the
artwork is in `textures/ads/`, drawn by `tools/make_ads.py`, and
`tools/place_billboards.py "<brand>" <ad> <ad> ...` puts a brand's
billboards up near its locations (written to `data/edits.json`, so they can
be moved or deleted in the map editor, where billboards have an "Ad" field).
Tim Hardly's has five posters ("now with bacon", toasted bagel season, the
iced capp served warm, start your day with a surprise, now hiring) and a
billboard by each of its shops outside downtown (Grafton Street, North River
Road, St Peters Road, University Avenue and the one north of them): large
coffee? medium; Someone's order is ready; "I wanted a hash brown too." "No
you didn't."; roll up the rim to see what you actually ordered; 12 Tim
Hardly's between here and Summerside, not one will get it right.
Windy's split from Tim Hardly's and now sells breakfast too: its windows
say "Burgers after 11. Not a minute before.", "Breakfast is here. It's
fine." and "We're a burger chain. You can tell.", and its billboards "We broke up with Tim Hardly's. So now we do
breakfast too. Between you and me? It's sh*t." and "Windy's is now open
for breakfast. Like Tim Hardly's, but worse. No, you can't have a burger.",
"We're a burger chain. You can tell. Everything tastes like a greasy
hamburger. But hey, we do breakfast." and "Try our new Breakfast Fries.
They're fries." (two at each Windy's, one for each way in:
`place_billboards.py --each=2`).
MacDougall's is open all night for anyone too far gone for the local
Chinese places ("Too drunk for the Can't-On Cafe? Kicked out of the China
Guardin'? We'll take you. We have to."), serves breakfast until 11 (you
got here at 11:01; watch us enjoy this), and runs the Dollar Menu (nothing
on it is a dollar), the prize game (everyone wins a medium fry) and the
MacRib (was it ever gone? was it ever a rib?). Its windows: order at the
kiosk, then wait while we ignore you; download the app for 0% off; the
MacFlurry, available in this picture; breakfast until 11, not 11:01.
The **Sand Bar Tourism Board** has billboards too, in the loading screens'
comic look (a panel of the town, the caption on a yellow card, the plate,
"A message from the Sand Bar Tourism Board. Sorry."), each put up by what
it's about: "We have roundabouts. And roundabouts. And roundabouts. And
roundabouts." at four roundabouts round the edge of town; "Sorry about the
pollution plant. Smells like shit all the time. But you can blame your
girlfriend if you want." both ways into the Pollution Control Plant;
"That smoke? That's your recycling. We tried." by the district heating
plant; "Drive safe. The nurse is your cousin." both ways into the QEH;
"Speed limit 50. Or thereabouts." by UPEI; "Everyone here knows your
mother. Drive accordingly." by the Eastlink Centre; "Nobody locks their
car here. Just saying." by Bunbury Mall; and "Island time is not a speed."
by Victoria Park. They're drawn by `tools/make_branding.py` (`TOURISM`
there) and put up with `tools/place_billboards.py --tourism`
(`TOURISM_BOARDS` there says which board goes by which place).

**Gas station canopies** are drawn wherever OSM maps one (as a roof over
the pumps): about 5 m up on a row of posts, with a deep fascia in the
brand's colours and its name on both long sides, and a pump island with a
pump each side at every post, and a price sign out by the road. You can
drive under it; the posts and pumps are solid. Where OSM puts the brand on
the store but maps the canopy as a plain roof (like the Esso at St Peters
Road and Brackley Point Road), the canopy takes the brand of the gas
station store beside it. Other roofs mapped on their own (carports,
shelters) get a thin roof on corner posts.

**Car dealers** get a tall glass showroom standing out from the front, a
portal in the make's colour with its name over the showroom door, service
bay doors under a SERVICE board, a tall sign by the road, and about 18 cars
for sale lined up facing the street nearest the showroom, from the brand's
"stock" (Fjord dealers carry mostly Halftons, Hanaka dealers Civiques).
Where the lot isn't mapped, the cars go on the ground between the showroom
and the street. Dealers show only the make, never the local dealership's
name. A landmark can set the make with "brand" when OSM names the
dealership instead (the Ford and Chevrolet dealers on St Peters Road). To rename a brand,
change its name in "brands". Only chains with a building of their own are
drawn this way; ones mapped as a single point inside a mall don't have a
building to put the sign on.

| World brand | Kind | Stands in for |
|---|---|---|
| Tim Hardly's | coffee | Tim Hortons |
| Wren's Donuts | coffee | Robin's Donuts |
| Starbeans | coffee | Starbucks |
| MacDougall's | burgers | McDonald's |
| Burger Baron | burgers | Burger King |
| Windy's | burgers | Wendy's |
| A-OK Root Beer | burgers | A&W |
| Cluckers | burgers | KFC |
| Sub Station | burgers | Subway |
| Dairy Duchess | burgers | Dairy Queen |
| Portland Pizza | pizza | Boston Pizza |
| Wyoming's | pizza | Montana's |
| SoBuys | grocery | Sobeys |
| Maritime Megastore | grocery | Atlantic Superstore, Real Canadian Superstore |
| Food Island | grocery | Foodland |
| Wants | gas | Needs |
| Shamrock Farm | gas | Clover Farm |
| Ervin's | gas | Irving |
| Exo | gas | Esso |
| Petro-North | gas | Petro-Canada |
| Ultrasea | gas | Ultramar |
| Clam | gas | Shell |
| Square Q | gas | Circle K |
| BuyMart | big box | Walmart |
| Maple Tire | big box | Canadian Tire |
| The House Depot | big box | The Home Depot |
| Hearth Hardware | store | Home Hardware |
| Staplers | store | Staples |
| Gulf | store | Gap |
| Reelplex | cinema | Cineplex |
| Stoppers Drug Mart | pharmacy | Shoppers Drug Mart |
| PharmaChance | pharmacy | PharmaChoice |
| Royal Island Bank | bank | RBC |
| Fundy Bank | bank | Scotiabank |
| Dominion Trust | bank | TD |
| Imperial Commerce | bank | CIBC |
| Quality Stay | hotel | Quality Inn |
| Comfy Inn | hotel | Comfort Inn |
| Budget Lodge | hotel | Econo Lodge |
| Hamlet Inn | hotel | Hampton |
| Hanaka | car dealer | Toyota, Honda |
| Nissun | car dealer | Nissan |
| Hyunsung | car dealer | Hyundai |
| Kyo | car dealer | Kia |
| Subtaru | car dealer | Subaru |
| General Motorworks | car dealer | General Motors |
| Fjord | car dealer | Ford, Lincoln |
| Chevalet | car dealer | Chevrolet |
| Take 6 | store | Take 5 |

## Graphics setting

There are two graphics levels, **High** (the default) and **Low**. Press
**F10** in the game to switch; a note in the corner says which one you're
on, and the choice is remembered next time. Low is for older or basic
graphics chips:

| | High | Low |
|---|---|---|
| Soft shadows that sharpen near the object | yes | plain soft-edged shadows, out to 90 m instead of 160 m |
| Shading in corners and under ledges (SSAO) | yes | no |
| Light bouncing off walls and the street (SSIL) | yes | no |
| Glow round lamp glass | yes | no |
| Fine relief on brick, slabs and boards, and depth in the windows | yes | flat (same colours) |
| Trees swaying | yes | no |
| Full detail round you (curbs, lamps, signs, everything solid) | 330 m | 230 m |
| How far the simpler distant town reaches | 1 km | 750 m |

The town looks the same at a glance either way. To start on Low, run the
game with `-- --graphics=low`. When the game runs on the Compatibility
(OpenGL) renderer it starts on Low unless you've picked High with F10.
The setting lives in `scripts/autoload/graphics.gd`.

**Sound** has its own button in the menu (Esc): it steps the volume
through 100%, 75%, 50%, 25% and Off, and the choice is remembered. It
lives in `scripts/autoload/sound.gd`.

## Driving

Three cars are parked in a row on Grafton Street, just past Great George,
when you start. Walk up to a driver's door (on the left) and press E. The
car's name comes up as you get in, you sit inside, visible through the
glass, and the camera drops to a lower chase view that swings in behind
the car. Press V for the **driver's seat** view instead: you look out over
the hood from where the driver's head is, with your own arms on the wheel,
and the mouse or right stick turns your head (it eases back to the road
when you let go). The game remembers which view you like for the next car.
Slow below about 8 km/h and press E again to step out.

**How the cars look.** They're built to read like good die-cast models on
the diorama of the town, all from code in `car_builder.gd`: a lofted body
with panel gaps, tinted glass you can see into, and a full interior (dash
with gauges, radio and vents, bucket seats, door cards with armrests,
console and gear lever, headliner, sun visors and mirror). The steering
wheel turns with the front wheels, and the driver's hands stay on its rim
and feet on the pedals (reaching for them with simple two-bone IK in
`humanoid_model.gd`), so nothing passes through the wheel or the dash.
Outside there are lamp units with chrome reflectors under clear lenses,
grilles, wrap-round bumpers, plates with real characters, badges, mirrors
with glass, wipers, aerials, fuel doors and exhausts. Each model has its
own wheels: polished five-spoke mags on raised-white-letter tyres for the
Pony, ten-spoke alloys for the Civique, six-hole steel wheels on chunky
all-terrains for the Halfton, all with real spokes, lug nuts, a centre cap
and a brake disc and caliper behind (the caliper steers with the wheel but
doesn't spin). Parked cars use the same builder with less detail.
`tools/car_studio.gd` photographs every car from set angles on a plain pad,
for checking them without loading the town.

The brands are made up, the way GTA spoofs real cars:

| Car | What it is | How it drives |
|---|---|---|
| **Dunmore Pony GT** | Two-door coupe, rear-wheel drive, big V8, six speeds | Light and punchy. Floor it in a corner and the tail steps out; catch it with opposite lock. |
| **Hanaka Civique** | Four-door sedan, front-wheel drive, small four, five speeds | The sensible one. Too much throttle in a corner just pushes it wide. |
| **Fjord Halfton 150** | Pickup truck, rear-wheel drive, lazy V8, five speeds | Heavy, tall and soft. Leans hard, stops long, and the light back end can come round. |
| **Dodgy Jaunt** | Mid-size crossover, all-wheel drive, V6, six speeds | Our Dodge Journey. Steady and grippy, not quick, a bit tall in the corners. |
| **Dodgy Rammer 1500** | Crew cab pickup, four-wheel drive, Hemi V8, eight speeds | Our Ram 1500. Big and heavy but properly quick in a straight line. |

The Jaunt is built to read as a 2011-2020 Journey: slab sides under a high
belt line with a short band of glass, dark tinted glass behind the front
doors, roof rails, a short hood and raked windshield, a wide grille split
in four by a cross between the lamps, and one "racetrack" tail lamp right
across the back with a red ring of light round its edge ("grille",
"roof_rails", "privacy_glass" and tails "racetrack" in its shape).

**Police cars.** The Charlatown Police Services drive Jaunts and Rammers,
the way the real service runs Dodge Journeys and some Rams. Five of them
are parked nose-in along the station's wall on Kirkwood Drive ("fleet_cars"
in `data/map_config.json`), and you can take any of them. A livery
(`CarModels.LIVERIES`, "cps") goes over any model: white with a navy
band and a red pinstripe down the sides, POLICE on the doors and across
the back, CHARLATOWN behind it, the unit number on the plate, the rear
quarter and big on the roof, black steel wheels, a push bar, a spotlight
on the driver's A-pillar, and a red and blue light bar with two more
lights in the grille (`scripts/vehicles/police_gear.gd`). Press L in the
driver's seat for the lights, again for the siren too, and again for off.
The lights flash in quick double pulses and throw red and blue on
everything round the car. The real service's cars are white and blue; the
exact stripes are a guess until there's a photo.

**How the physics works.** Each car is a real physical body with its
weight where the engine and seats put it, sitting on four wheels:

* Each wheel has a **spring and damper**. The body dives under braking,
  squats under power and leans in corners because the springs really
  compress; it rocks over curbs and bumps, goes light over a crest and can
  leave the ground over a big enough one, and lands on its springs.
* Each **tyre** grips in proportion to the weight pressing it down, so
  weight moving between the wheels is what makes a car push wide, turn in
  or slide. A tyre only has so much grip to share between pulling and
  turning: spin the rear tyres of a rear-drive car in a corner and the tail
  comes out.
* The **engine** has a torque curve and drives through a **gearbox** with
  an automatic shift. Top speed isn't a set limit: it's where the engine's
  pull meets the air and the gearing runs out.
* Hitting things is real too: cars bounce off walls and each other, and a
  parked car with its brakes on is hard to shove.

Measured on a flat test pad with scripted inputs (`tools/car_test.gd`):

| | Pony GT | Civique | Halfton 150 |
|---|---|---|---|
| 0 to 100 km/h | 5.3 s | 9.9 s | 6.8 s |
| Top speed | 245 km/h | 170 km/h | 180 km/h |
| Braking, 100 to 0 | 42.5 m | 47.3 m | 53.1 m |
| Lean in a hard turn at 60 km/h | 1.3 degrees | 2.1 degrees | 4.4 degrees |
| Handbrake turn from 50 km/h | swings round 124 degrees | 182 degrees | 158 degrees |
| Off a 0.7 m ramp at 90 km/h | 0.8 s in the air | 0.9 s | 0.9 s |

The Dodgy Jaunt does 0 to 100 in 7.7 s (191 km/h flat out, 52.6 m to stop
from 100, 3.0 degrees of lean) and the Rammer 1500 in 6.7 s (198 km/h,
53.1 m, 3.8 degrees).

**Settings and performance parts.** Everything about how a car drives is
in `scripts/vehicles/car_models.gd`, in groups: body (weight, balance,
drag), engine (torque curve, redline), gearbox (ratios), tyres,
suspension (spring stiffness, damping, travel, anti-roll bars), brakes and
steering. `scripts/vehicles/car_parts.gd` has **performance parts** that
change those settings: sport springs, anti-roll bars, performance tyres,
intake and exhaust, an engine tune, a short final drive, big brakes and
weight reduction. There's no garage to fit them in yet; a car's `parts`
list is where they go, and `tools/car_test.gd --car=civique
--parts=engine_tune,performance_tyres` shows what they do.

The driving camera has its own group on CameraRig: a little wider than on
foot (60 degrees, widening by 6 at speed), a closer, lower position, and a
fine shake at highway speed. A much wider view feels fast for a moment but
stretches the road ahead like a wide-angle lens, so the blocks look longer
than they are; the streets themselves are true to scale (University Avenue
is 5,015 m in the game and 5,024 m on the map). The driver's seat view has
its own group too.

## Sounds

The cars have sound: the engine (starter, idle, revs, coasting, the odd
pop on the overrun), the tyres squealing when they slide, spin or lock,
road roar and wind that come up with speed, a thud over curbs and
landings, and a crunch when you hit something.

None of it is recorded. `tools/make_car_sounds.py` builds every sound
from a model of what makes the noise, so it doesn't come out sounding
like a synthesizer:

* **Engines** fire cylinder by cylinder in their real firing order, and
  each firing sends a pressure pulse into the exhaust. The pulses are
  shaped by the crank angle the exhaust valve is open, so they're long and
  thumpy at idle and short and hard at the redline. Every firing is a bit
  different (stronger, weaker, a degree early or late), the revs wander a
  little, and the gas rushing out is turbulent. Those small irregularities
  are most of what makes a real engine sound alive.
* The **V8s burble** because a cross-plane V8 fires each bank unevenly. The
  Pony GT's banks run to their own tailpipes, so you hear the lope; the
  Halfton's meet in a Y-pipe and go through a heavy muffler, so it's deep
  and smoother. The **Rammer**'s Hemi runs true duals with a lope and the
  **Jaunt**'s V6 is smooth and a little buzzy. The **Civique**'s four fires evenly and its character is
  mostly intake and valvetrain, getting raspy up top.
* The **exhaust pipes** are acoustic tubes that ring at their own pitches,
  then the muffler's chambers and the tailpipe shape the sound, with the
  ground reflection and a little air around it.
* **Tyre squeal** is a few stick-slip tones that wander and stutter; road
  roar and wind are shaped noise; knocks are a car body's ringing panels
  struck with a crunch of crumpling metal.
* The **police siren** is an electronic wail like a real one: a tone rich
  in odd harmonics sweeping 650 to 1500 Hz and back every four seconds,
  through a horn speaker's narrow band with a little distortion.

The engine is rendered as looping clips at a ladder of steady revs, on and
off the throttle (`sounds/cars/<car>/`). In the game, `CarAudio` plays the
two clips either side of the engine's revs, pitches them to match exactly
and blends between them, and blends on- and off-throttle by how hard
you're pressing. That's how racing games play real engine recordings, so a
recorded engine could drop in later without changing the code.

To change a sound, edit the settings at the top of `make_car_sounds.py`
(each car's firing order, pipe lengths, muffler, how lumpy the idle is)
and run it again. To hear the result without opening the game:

```sh
pip install numpy scipy
python3 tools/make_car_sounds.py                 # rebuilds sounds/cars/ (about 30 s)
python3 tools/preview_car_sounds.py              # a short test drive per car, as MP3s
```

`tools/sound_drive.gd` records a scripted drive through the game's own
sound code, using Godot's movie mode. See the top of the file.

## What's in the game so far

* **The whole city, from real streets.** Everything inside the bypass is
  playable: downtown, the waterfront and Victoria Park, University Avenue,
  Sherwood, Parkdale, West Royalty, East Royalty out to the Arterial
  Highway, all at their true positions and angles. You can drive the whole
  ring: up Riverside Drive from the Hillsborough Bridge junction, round the
  Arterial Highway past Malpeque Road and University Avenue to the Upton
  Road roundabout, down Upton Road to the Capital Drive roundabout, left
  onto Capital Drive and back into town by North River Road. About 11,500
  buildings and 2,000 stretches of street in all. (Great George between
  Grafton and Richmond is the pedestrian plaza by Province House, so there's
  no road there, just as in town.)
* **Roads, curbs and sidewalks** generated from the OSM centrelines, with
  the curb corners worked out at every intersection so sidewalks meet cleanly.
  Widths are set per street in `data/map_config.json` downtown and worked
  out from the road type and lane count elsewhere. Where OSM splits one
  street into several pieces the game joins them back up, so the paint and
  curbs run on unbroken; where a street gets wider or narrower it tapers
  rather than stepping out. The ground is carved down a little under every
  street and sidewalk so bumps in the lidar never poke through.
* **Highways**: the bypass, Riverside Drive and their ramps are built
  highway style, with paved shoulders, white edge lines, lane lines, a solid
  double yellow down the middle where they're two-way, and gravel verges
  instead of curbs and sidewalks. **Roundabouts** are built from their real
  shape. **Divided roads** (two one-way carriageways side by side, like
  University Avenue and Capital Drive) have a median curb on the inside
  instead of a sidewalk, and a narrow median is paved curb to curb rather
  than left as a sliver of grass. Roundabouts have a raised grass **island**
  with a curb. Where two roads overlap (a roundabout and the roads flaring
  into it, a ramp joining a highway) one surface is drawn on top and the
  other just under it, so there's never a hole between them; a ramp keeps
  its own width right up to where it joins. Sidewalks, paint, signs,
  signals and lights are kept off every roadway, not just their own. **Bridges** keep a straight deck from end to end
  with a concrete parapet down each side, whatever the ground does below.
  Each end of the deck sits on the top of its embankment (the lidar is bare
  earth with the bridge taken out, so a mapped bridge end usually lands part
  way down the slope), and the ground round the end is filled up to meet it.
  A bridge and the road under it are on different levels, so neither cuts
  the other's roadway, sidewalks or paint.
* **Centre lines** on two-way streets, lane lines on wide one-way streets,
  and **crosswalks** wherever OSM maps a marked crossing. Lane and centre
  lines stop short of each crosswalk and start again past it.
* **Buildings from their real OSM footprints.** Downtown (within about
  900 m of Great George and Richmond) they're styled like downtown
  Charlottetown: two- to four-storey Victorian brick blocks with arched
  windows, cornices and shopfronts (some with awnings), clapboard and
  cedar-shingle houses with steep gables, white trim and coloured doors, and
  sandstone public buildings. Heights and roofs are **measured from the lidar
  survey** wherever it saw the building (all but about 300 of them): the
  real height to the eaves and the ridge, whether the roof is flat, gabled or
  hipped, which way the ridge runs and how steep it is. Where the survey
  didn't see a building (built after 2020, or hidden by trees) the height
  comes from OSM's height and level tags or a good guess. Cornices are stepped, with a bracket between each window bay,
  parapets have a stone coping, and gable roofs have white fascia and barge
  boards. The walls are drawn in a shader: brick with mortar joints you can
  see the light catch, lapped clapboard, grime splashed up the bottom of the
  wall and rain streaks under the sills. Windows sit back in the wall (the
  sides of the opening show as you walk past), and each one is different
  behind the glass: a dark room, curtains, a blind part way down, or a lamp
  on. Roofs have shingle courses with streaks and a little moss; flat roofs
  are tar and gravel. Out in the rest of the city, house-sized buildings
  are clapboard and shingle houses, and big ones (the mall, schools, the
  hospital, plants and warehouses) are plain modern buildings in concrete
  and grey or beige cladding, without shopfronts.
* **Facade detail (prototype).** Within 150 m of the player (90 m on Low
  graphics), walls are built with
  real holes for the windows, doors and shop windows, with the glass set
  back 8 to 25 cm and the sides of each opening showing. Brick, sandstone,
  clapboard and cedar shingle use photographed textures (CC0, from Poly
  Haven, packed into `textures/facade/`) tinted to each building's colour.
  Windows get projecting sills (masonry) and, on Victorian brick and
  stone, real segmental-arched heads: the opening, the glass and a head of
  stone voussoirs with a keystone all follow the curve. Wooden houses get
  casings; every building stands on a fieldstone foundation; most pitched
  roofs get a brick chimney; houses facing a street usually get a front
  porch with steps, posts and railings; front doors get stone steps; colours
  are toned down to look weathered. This close-up version of a chunk's
  buildings is built on a worker thread and swapped in for the plain one as
  you approach (and back as you leave), so it costs nothing further out.
  Start the game with `-- --flat-facades`
  to see the old flat walls (and the old trees and no street clutter) for
  comparison.
* **Landmarks up close (prototype).** Churches get real pointed-arch
  window openings set deep in the wall, stepped buttresses between them,
  stone hood mouldings and a plinth; towers get louvred belfry openings and,
  under a spire, a pinnacle at each corner (St. Dunstan's, St. Paul's,
  Trinity). Province House's portico gets column bases and capitals, a
  cornice, raking cornices up the pediment and broad steps. The
  Confederation Centre is ribbed Wallace sandstone with groups of tall slot
  windows, a granite base and a heavy fascia, with the theatre's fly tower,
  Memorial Hall and the gallery clerestory rising above the main block and
  a glazed lobby on Queen Street (landmark keys `ribbed` and `massing` in
  `data/map_config.json`).
* **Fire hydrants (prototype)** at the curb every 95 m or so on ordinary
  streets, solid, drawn within 150 m (`scripts/world/street_clutter.gd`).
* **Trees (prototype).** Broadleaf crowns are built like real ones: main
  branches climbing out of the trunk and forking, with clumps of leaves
  (three crossed cards each, from a leaf atlas drawn by
  `tools/make_leaf_atlas.py`) at their ends and along their outer halves,
  so the outline is leaves, the middle is open and sky shows through.
  Spruces are whorls of drooping branch cards (texture drawn by
  `tools/make_needle_branch.py`). Trunks and branches use a photographed
  bark texture.
* **The look**: daylight with a warm, fairly low sun, soft shadows, a deep
  blue sky that fades to haze at the horizon, and a light haze over
  distance. Colours go through AgX tonemapping (so bright skies and white
  trim don't blow out), with ambient occlusion in corners and light bounced
  off walls. The aim is grounded and readable rather than photographic.
* **Landmarks**, matched to their OSM footprints by id in
  `data/map_config.json`: St. Dunstan's Basilica with its twin spires at the
  foot of Great George Street, Province House with its columned portico
  facing Grafton Street, its low hipped slate roof and chimneys,
  Confederation Centre in pale sandstone, St. Paul's and Trinity United
  churches with their towers, and City Hall's clock tower. Their colours, heights
  and towers are best estimates, not measurements, and worth checking
  against the real buildings. Those checked against Joe's photos say so
  in their `_comment`.
* **The war memorial and flags at Province House.** Three bronze soldiers
  advancing on a granite pedestal, in front of the portico, with the
  Canadian flag on one side and the Island's on the other, rippling in
  the wind. They're placed by hand in `data/map_config.json` under
  "monuments" (`scripts/world/monuments.gd`). The flag pictures are drawn
  by `tools/make_flags.py`.
* **Red-and-white crosswalks downtown.** Marked crosswalks within
  "red_crosswalks_m" (450 m) of the origin have red blocks between the
  white stripes, edged by a thin white line, like the real ones on Great
  George and Grafton. Further out they're plain white zebras.
* **Overhead crosswalk signs.** Where a marked crosswalk crosses a main
  road (trunk, primary or secondary) away from traffic lights and outside
  downtown, a red "CROSS X WALK" board hangs over the middle of the street
  on a span wire between two galvanized posts, and each post has a white
  walking-figure sign, like the ones on Grafton by Holland College
  (`scripts/world/street_props.gd`; the sign faces are drawn by
  `tools/make_crosswalk_signs.py`).
* **Real elevation** from Natural Resources Canada's lidar survey of PEI
  (2020): the ground, streets, sidewalks, buildings and street furniture all
  follow the true slopes, from the shore up to about 50 m in the north end
  of the city; about 11 m above sea level at Queen and Grafton, 6 m at
  Prince and Sydney and 2 m at Water Street. Buildings stand
  at their uphill ground level and show a foundation on the downhill side.
  The car feels the grade (it rolls downhill and works uphill), and the
  harbour sits at sea level where the land drops below it.
* **The ground between the streets** from OSM: lawns, yards, parks and
  playing fields, parking lots and driveways, stone-paved squares, brick
  footpaths and gravel trails, and Victoria Row's brick street, painted onto
  the terrain so they follow the slope. Commercial and industrial land is
  asphalt; ground nobody has mapped is rough grass. **Parking lots** are
  asphalt with oil stains and white stall lines: along every parking aisle
  mapped in OSM, and in rows laid out along the lot where no aisle is
  mapped.
* **Streets that look used**: weathered asphalt with darker repair patches,
  hairline cracks, polished wheel paths, oil drips down each lane and grit
  in the gutters; worn paint; concrete sidewalks laid in slabs with a
  separate curb stone, the odd gum spot, and curbs grimy from road spray.
* **Street-name signs** at each intersection, **stop signs** where OSM maps
  them, **traffic lights** (cycling, for looks only so far) at the junctions
  OSM marks as signalled, **trees** where OSM maps them (a forked trunk
  under a crown of leaf clusters that sways a little in the wind), black
  cast-iron **heritage lamp posts** with six-sided lanterns along downtown's
  sidewalks, and ordinary street lights on wooden poles everywhere else.
  Outside downtown, **utility poles** run down one side of town streets
  with the wires strung between them (downtown's are buried), and the
  street lights on that side carry the wires too.
* **Cars parked along the curbs**: a few on residential streets and more
  downtown, on one side of a narrow street and both sides of a wide one,
  none on the main roads through town. They're seeded by position, so the
  same cars are parked in the same spots every time, and they're solid.
  **Every tree the lidar survey saw** (about 63,000) stands where it really
  is, at its real height and spread: leafy trees, and spruce and fir where
  the canopy comes to a point. A tree leaning out over a street has its
  trunk moved back to the edge of the sidewalk.
* **The player**: a low-poly person with normal proportions (red fall jacket,
  jeans), built as one smooth skinned mesh on a small skeleton, so each
  person is a single draw call (pedestrians will use the same model with
  random looks: build, height, hair, clothes). **Clothes** come in four
  slots, each a kind and its colours (`scripts/characters/outfit.gd` lists
  them): hat (none, toque, ball cap), top (T-shirt, long-sleeve shirt,
  hoodie, flannel shirt, fall jacket, satin bomber, jean jacket with copper
  buttons and flap pockets, varsity jacket with leather sleeves, quilted
  puffer), bottoms (jeans, trousers, joggers, shorts) and shoes (sneakers,
  boots, dress shoes). Fabrics have their own look in the shader (flannel
  plaid, denim twill, puffer quilting, knit ribbing, satin and leather
  shine). Tops and caps carry **prints**: sixteen made-up Island brands and
  sayings, each designed like real merch with its own lettering, one or two
  inks and a well-washed look (Red Clay Spud Co., the Canada Gull patch, the
  Spud Kings crest, Tim Hardly's ("Close enough"), Mussel Beach Gym, Lobster Supper, "Who's
  your father?", "Free to come. Pay to leave.", The ~~Gentle~~ Rowdy
  Island, a From Away inspection stamp, the University Ave. Pothole Society,
  Mainlanders Go Home, Red Mud Racing and more). They go big on a tee or
  hoodie, as a logo on a jacket's chest, across the back, on a sleeve patch
  or a cap's front, and pale inks print dark on pale clothes.
  `tools/make_clothing_prints.py` draws them, with the free display fonts in
  `tools/fonts/`, onto
  `textures/clothing/prints.png`. They
  are built into the person's one mesh over the bare body, so nothing pokes
  through, they move with the body, and a person is still one draw call;
  `set_outfit()` changes them on the spot. **The character creator** (Character, in the
  title and pause menu) dresses the player: skin, height, build, hair style
  and colour, and every slot's kind, colours and prints (chest, back, sleeve
  patch, cap logo), with a turning preview you can drag round and set
  walking. Randomize, Reset, Cancel or Done; Done puts the look on the
  player straight away and keeps it for next time in `user://character.json`
  (`scripts/characters/player_look.gd`). Shoulders
  slope and round over into the arms, the torso tapers from chest to waist,
  the legs have a seat, knees and calves, the hands have a thumb, and hair
  stands off the head. The walk is worked out from speed rather than a
  canned clip: stride and pace match the ground speed, knees bend through
  each step, the hips drop and shift a little over the planted foot while
  the spine keeps the shoulders and head level, the shoulders turn against
  the hips with the arms, the feet land close to a line under the body, and
  a run leans forward with bent arms (and leans into turns; a walk doesn't).
  Each foot landing takes the weight: the knee gives and the hips dip a
  little. Starting tips the body forward and stopping rocks it back, on a
  bouncy spring, so a stop overshoots a touch and settles, and on a stop
  the last step carries through so the feet land together.
  Standing still, they breathe and shift their weight. A light touch on the
  stick strolls, full tilt walks, and Run runs. They turn toward where you
  push and move the way they face, so a run carves a wider turn, and a sharp
  reversal at a run slows down first. They step up curbs and stop against
  buildings, poles and trees without running on the spot.
  Speed and heading glide on damped springs, so starts, stops and turns ease
  in and out (walking speed in about a fifth of a second, a stop in a
  little under a quarter: quick, like an online sandbox game, not a simulator), big turns pivot a little slower than small corrections, and a
  reversal at a run plants and slows before coming round. Physics
  interpolation is on, so movement stays smooth on 120 and 144 Hz screens.
* **Camera**: a third-person camera that frames you in the lower part of
  the screen with the street ahead in view. Zooming slides it along a curve,
  from low and behind your back (close in) up to a nearly overhead view
  (zoomed out), and the mouse tilts it on top of that; pull the mouse down to
  look up at the spires. It follows on smooth springs, looks a little ahead
  of where you're going, pulls back and widens a touch when you run, and
  eases back in behind you after a moment without camera input. If a
  building would come between you and the camera, it moves in quickly and
  eases back out after; buildings and tree crowns that still block the view
  fade out of the way. All the tuning numbers (distance, angles, follow
  times, recentring) are exported variables on the Player and CameraRig
  nodes, grouped in the Inspector.
* **The edge of the play area** is an invisible wall 60 m outside the
  bypass ring, and out in the North River and the harbour along the shore,
  with road-closed barriers wherever a street crosses it (the
  Trans-Canada to Cornwall and Stratford, Malpeque Road, St. Peters Road
  and so on). Past it the city carries on as scenery.
* **HUD**: the name of the street you're on, a controls reminder, and the
  OpenStreetMap credit.

## Editing the map

A map editor that works from above, for fixing the town yourself.

**The easy way: press F8 in the game.** Run the game from Godot (F5),
press **F8**, and the editor opens in your web browser already connected
to the game: nothing to pick or allow, it saves straight into the project,
**Live** is on, and a blue "You" marker shows where you are in the game
(**Find me** or the Home key centres the map on it). Every change shows in
the game a second or two later, round you, without restarting. Click back
into the game window to carry on playing. (The game serves the editor
itself, only to this computer: `scripts/world/map_editor_server.gd`.)

**Without the game running:** open `tools/map_editor.html` (in the `tools`
folder; Godot's file panel doesn't show it) in **Chrome or Edge**, press
**Open project folder** and pick this folder (the one with `project.godot`
in it). The whole city loads in a few seconds.

* **Streets:** click one to select it. Drag its points to move them (a
  point where streets meet moves for all of them), drop a point on another
  street's point to join them, and double-click the line to add a point.
  Change the name, type, lanes, one-way and speed limit, or delete it.
  **Road** draws a new street that joins whatever it starts or ends on.
* **Road edges:** each street has Width, Sidewalk and Shoulder boxes (in
  metres) and **+** / **-** keys that widen or narrow it 0.25 m at a time.
  Tick **Edges** to see the curbs and sidewalks as wide as the game builds
  them. A parking-lot street can be marked "parking aisle" to get painted
  stalls along it.
* **Buildings and areas:** drag a building to move it, drag a corner to
  reshape it, and set its wall height, roof height and shape, wall and roof
  colour and material. **Building** and **Area** draw new ones (an area is
  a parking lot, park, lawn, woods and so on).
* **Props:** benches, picnic tables, litter bins, post boxes, hydrants,
  heritage lamps and street lights, bollards, planters, boulders, jersey
  barriers, traffic cones, a drive-thru menu board and order speaker, a
  clearance bar, and trees, stop signs, traffic lights and crosswalks. Pick
  one and click to place it; turn it with **[** and **]**.
* **Deleting:** select anything placed or mapped (a prop, a tree, a stop
  sign, a crosswalk, a building, a street) and press **Delete**. The
  hydrants, lamps, street lights and parked cars the game puts along every
  street by itself are erased with **Erase** instead: click one (or a lidar
  tree) to take it out, and click its red cross to put it back. The editor
  shows them from `data/city/generated_props.json`; after big street
  changes, refresh that list with
  `godot --path . --script res://tools/list_generated_props.gd` (not
  `--headless`; a window opens for a minute or two and closes itself).
  The game itself no longer puts a hydrant in another street or across a
  driveway.
* **Fences, walls and hedges:** **Line** draws chain-link (with or without
  barbed wire), wood privacy, picket and split-rail fences, hedges, stone,
  brick and concrete walls, guardrails and banks of armour stone. Fences
  and walls leave a gap where they cross a street.
* **Signs:** in the Props list. Road signs (speed limit, stop, yield, no
  parking, one way, do not enter, school zone, pedestrian crossing,
  parking, street name, a custom sign) and business signs (pylon,
  monument, wall sign, billboard) with your own text, colours and size.
  Put `|` in the text for a new line.
* **More props:** bus shelters, bike racks, newspaper boxes, community
  mailboxes and mailboxes, utility poles, dumpsters, propane cages, ice
  machines, transformer boxes, dock bumpers, ATMs, gas pumps, EV chargers,
  cart corrals, parking-lot lights, play structures, swing sets,
  flagpoles, fire pits, sheds, trampolines and lawn chairs.
* **Where you start:** **Start** places the player's start spot and the
  cars waiting there (click, and drag the way to face). Your cars replace
  the three on Grafton Street.
* **Test here:** click and drag anywhere, tick "Start in a car" if you
  like, and the next time you run the game you start right there. It's
  kept in `data/test_start.json`, which git ignores; Clear in the panel (or
  deleting the file) starts the game normally again.
* **Notes:** circle a spot and write what needs fixing. Notes are saved
  with the edits (the game ignores them) along with the streets and
  buildings inside the circle, so Claude can find the exact spot.
  **Copy for Claude** puts the note on the clipboard to paste into a chat.
* **Aerial** shows satellite photos under the map to line things up
  against, the **Changes** tab lists every fix (click one to go there, or
  undo just that one), and Ctrl+Z / Ctrl+Y undo and redo.

**Seeing your changes in the game, live.** Run the game from Godot (F5)
and leave it running beside the editor. Every time you save, the game
notices within a second, reads the edits again and rebuilds just the
squares of town your changes touch, round you, without restarting or
moving you ("Map updated" shows when it's done; about a second on a normal
PC). Tick **Live** next to Save and it saves by itself a moment after each
change, so you can move a fence in the editor and watch it move in the
game. **Test here** works the same way: click and drag in the editor and
the running game takes you straight there (driving, if "Start in a car" is
ticked). This only works when the game runs from Godot; an exported copy
has the map packed inside it and shows edits only after it's exported
again.

**Save** (Ctrl+S) writes `data/edits.json`. The game lays it over the
OpenStreetMap data the next time it starts, so commit that file to keep the
fixes. `data/city/` itself is never changed, so a fresh OSM download keeps
them. In other browsers Save downloads `edits.json` instead; put it in the
`data` folder. The ground colour under a new or reshaped area (grass,
parking) comes from the ground masks, so it changes only after
`tools/make_ground_mask.py` is run again.

## Maps

Trans-Canada Auto is meant to grow a map at a time. A map is one
`map_config.json` and the data it points to (see `data/README.md`); the
"map" entry at the top names it.

| Map | Place | What's in it |
|---|---|---|
| **Sand Bar** | Charlatown (Charlottetown), PEI | The whole city inside the bypass and Riverside Drive |

Another place (Halifax, say) would be built the same way: cut its
OpenStreetMap data and lidar with the tools in `tools/`, give it its own
config, and point the World node's `config_path` at it.

## How the town is built as you move

The city is far too big to build all at once, so it's split into 200 m
squares (chunks) and built round you as you go:

* Within about 330 m of the camera (230 m on Low) chunks are built in **full
  detail**: curbs, paint, lamps, signs, trees, and everything solid to walk
  and drive into.
* Out to about 1 km (750 m on Low) they're built in **low detail**: the same
  streets and buildings (windows and all) without the small things, and
  nothing solid.
* Past that, a coarse version of the whole city's ground runs on to the
  horizon under the haze.

Chunks are built on background threads, nearest first, a few at a time, so
there's no long wait or stutter, and a chunk is dropped again once you've
moved well away from it. Each chunk's buildings are merged into one mesh
(two draw calls however many buildings), but each building keeps a number
in that mesh, so the camera still fades just the one building that hides
you. A coarse floor under the whole map means nothing ever falls through
while a chunk is still on its way. The code is in
`scripts/world/chunk_streamer.gd` (what to build when) and
`scripts/world/chunk_builder.gd` (building one chunk).

## Project layout

| Folder | What's there |
|---|---|
| `data/` | The map data (`city/`: streets, plus buildings and the rest in chunks), the elevation, the ground masks, and how to read it all (`map_config.json`). See `data/README.md`. |
| `tools/` | The map editor (`map_editor.html`, see "Editing the map"); Python scripts to cut the city out of the PEI OpenStreetMap file, convert it, fetch the elevation, paint the ground masks and preview the map as an SVG; and Godot scripts for checking without playing (`capture.gd` takes screenshots and measurements, `profile_chunks.gd` times chunk building, `char_preview/char_preview.gd` renders the person standing, seated and through a walk or run cycle, `char_preview/char_motion.gd` renders frames of them starting, walking, running and stopping, `char_preview/char_outfits.gd` renders a line-up in every kind of clothing, `char_preview/creator_shot.gd` screenshots the character creator); `make_clothing_prints.py` draws the graphics printed on clothes, `make_ads.py` the posters and billboards, and `place_billboards.py` puts a brand's billboards up by the road. |
| `scenes/` | `main.tscn` (lighting, sky, and the pieces below), `player/`, `camera/`. |
| `scripts/autoload/` | `InputSetup` (all controls), `GameState` (money and the save file), `Graphics` (the High/Low setting) and `Sound` (the volume). |
| `scripts/world/` | Building the town: `world_builder.gd` runs it (data, play-area ring, the first chunks); `chunk_streamer.gd` builds and drops chunks round the player and `chunk_builder.gd` builds one; `street_data.gd` loads the data, `geo_projection.gd` turns latitude and longitude into metres, `road_network.gd` is the street graph and curb maths, `terrain.gd` is the real ground (heights, chunk meshes, collision, harbour), `road_mesher.gd`, `building_generator.gd` and `street_props.gd` make the geometry (`placed_props.gd` builds the props placed in the map editor), and `building_fade.gd` fades one building out of a merged chunk. |
| `scripts/player/`, `scripts/characters/`, `scripts/camera/`, `scripts/ui/` | The player, the reusable person model (`body_builder.gd` makes the mesh), the camera rig, the HUD. |
| `scripts/vehicles/` | The cars: `car_models.gd` (names, shapes and every driving setting), `car_parts.gd` (performance parts), `car.gd` (the physics: body, springs, tyres, engine, gearbox; it also turns the steering wheel), `car_builder.gd` (builds each car's body, interior, wheels, brakes and steering wheel) and `car_audio.gd` (the car's sounds). |
| `sounds/cars/` | The car sounds, built by `tools/make_car_sounds.py`: one folder per car (engine clips on and off the throttle at each rung of revs, key on, key off, pops) and `shared/` (tyres, road, wind, knocks, bumps). |
| `shaders/` | Building walls (windows, brick, siding drawn in the shader), roofs, asphalt, sidewalks, road paint, paving, the terrain ground, tree leaves and people's clothes. `include/detail.gdshaderinc` has the noise and bump helpers they share. |

Coordinates: 1 unit = 1 metre, +X is east, -Z is north, +Y is metres above
sea level, and the origin is the Great George / Richmond junction. Physics layers are named in
`scripts/world/layers.gd`.

## Checking the map without Godot

```sh
python3 tools/preview_map.py preview.svg                                  # downtown
python3 tools/preview_map.py city.svg --centre=-1500,-2000 --half 3300   # the whole city
```

That draws the roads, sidewalks, buildings and play-area ring using the
same corner maths as the game. It's a quick way to check a width change or
a data refresh.

## Checking it in Godot without playing

Three scripts in `tools/` run the game by themselves and print what they
find (see the top of each file for how to run them):

* `capture.gd` starts the game, times the startup, saves screenshots from
  set spots and prints frame time, draw calls, triangles and memory.
* `drive_ring.gd` travels the bypass loop at a set speed and checks the
  streets are built and solid under the car the whole way.
* `profile_chunks.gd` times how long chunks take to build.
* `look_lab.gd` renders the same viewpoints in several candidate lighting
  looks, for comparing art direction.
* `car_studio.gd` photographs each car, with a driver at the wheel, from
  set angles on a plain pad (front, rear, side, a wheel, through the
  window, the driver's seat, above) and prints its triangle counts.
* `car_test.gd` measures each car on a test pad: acceleration, top speed,
  braking, cornering, a handbrake turn and a jump.
* `sound_drive.gd` records a scripted drive (key on, blips, a launch
  through the gears, a handbrake turn, a knock, key off) to hear the car
  sounds exactly as the game plays them.
* `audit_junctions.gd` checks every junction's geometry (too close to a
  neighbour, overlapping, or spiky) and lists the worst.
* `draw_roads.gd` draws the streets of an area exactly as the game builds
  them, from straight above, as an SVG: asphalt, sidewalks, medians, verges
  and paint, with the centrelines and junctions marked. The quickest way to
  see a gap, a curb that doesn't meet or paint in the wrong place.

## What has been tested

* The project imports and runs in Godot 4.7.2 with no errors or warnings
  from the game's scripts, on both the normal (Vulkan) renderer and the
  Compatibility (OpenGL) one. The camera fading a single building out of a
  merged chunk was checked on both.
* The map conversion was run on Geofabrik's PEI extract of 2026-11-21:
  2,032 street segments, 1,471 junctions and 11,457 buildings in 857
  chunks.
* `drive_ring.gd` drove the whole loop (11.1 km: Riverside Drive, the
  Arterial Highway, Upton Road, Capital Drive, North River Road) at 100 and
  160 km/h on High and at 120 km/h on Low, and again at 120 km/h after the
  lidar trees and buildings went in. The street was built and solid
  under the car at every check (one every 10 m), and the whole route is
  inside the play area. After the road clean-up (joined streets, tapers,
  carved ground) it was run again at 120 km/h: solid at all 1,089 checks.
* Measured in this cloud container, which has no graphics card (so the
  picture is drawn in software, about one frame a second, and frame times
  say nothing about a real PC):

  | | Before (four blocks) | After (whole city) |
  |---|---|---|
  | Playable after starting | 1.9 s | 3 to 4 s (downtown built; the rest fills in after) |
  | Building one chunk (one core) | | about 0.2 s full detail, 0.1 s distant |
  | Draw calls downtown | 560 to 710 | 670 |
  | Triangles drawn downtown | 2.1 million | 1.5 million |
  | Draw calls elsewhere | | 700 to 920 |
  | Memory (whole program) | 1.7 GB | 1.9 to 2.2 GB |
  | Slowest frame while streaming at 120 km/h (no drawing) | | about 60 ms |

  Most of the memory is the software renderer itself; on a real graphics
  card it will be much less. The game's own memory went from about 100 MB
  to 180 MB.
* With the facade, clutter and tree prototype: `drive_ring.gd` drove the
  whole loop at 100 km/h with the close-up facades swapping in and out
  along the way; the street was solid under the car at all 1,088 checks and
  the slowest frame was 31 ms (36 ms after merging the car physics, parked
  cars and power lines from main). At the spawn point at 1600x900 (software
  rendering, so only the ratios count): main before the merge drew 4.7
  million triangles in 798 draw calls, 2.1 s a frame, playable after 67 s;
  merged, with parked cars drawn within 150 m and wires within 260 m, 8.9
  million in 834, 3.4 s a frame, playable after 79 s. Without the draw
  limits the merged build drew 11.9 million.
* Nobody has played it with a keyboard or controller yet, so how walking,
  driving and the camera feel on the new roads is still untested.
* The car's numbers in the Driving section were measured by driving the real
  car on a test pad with scripted inputs, and it was recorded driving round
  the block downtown with a small driver script pressing the controls.

## Known issues and limits

* Where a ramp joins a highway at a shallow angle, the two roadways simply
  overlap (no painted gore), and where many carriageways meet at one OSM
  node (University Avenue, Malpeque Road and Capital Drive) the junction
  is one big patch of asphalt.
* Driveways, parking lots and service lanes are painted on the ground
  rather than built as streets, so they have no curbs or paint.
* You can wade or drive into the shallows of the harbour and rivers until
  you reach the invisible wall.
* Building colours and materials are well-chosen guesses, not the real
  ones: the lidar gives shape and height but not colour, and there's no
  open source of building photos to copy from. Malls, schools and the
  hospital are plain modern boxes at their real size.
* Roofs are simple: one gable or hip over the whole footprint (or flat),
  so L-shaped houses and dormers aren't modelled.
* Big churches get a simple nave roof; transepts and apses aren't modelled.
* Landmark details (towers, portico, colours) are set by hand in
  `data/map_config.json` and are close to the real buildings, not exact.
* Road and sidewalk widths are estimates. OSM doesn't record them for most
  streets.
* Street parking lanes and Queen Street's diagonal parking aren't painted
  yet.
* Gable roofs only go on houses whose footprint is close to a rectangle.
  Everything else gets a flat roof.
* Traffic lights cycle but nothing obeys them yet, and there's no other
  traffic.
* Three cars to drive; parked traffic along the curbs comes with Milestone 3.
* Bumping a wall costs speed, but cars don't dent.
* The car sounds are the same from the driver's seat as from outside (no
  muffled cabin sound yet), and there's no traffic or town ambience.
* Esc only frees the mouse. The pause menu comes with Milestone 4.

## Next milestone

**Milestone 3: Living environment.** Pedestrians walking the real
sidewalks (the person model already supports random looks), parked cars
along the curbs, and more street furniture.

## Credits

Map data © OpenStreetMap contributors, under the Open Database License
(https://www.openstreetmap.org/copyright). Elevation: Natural Resources
Canada, HRDEM; contains information licensed under the Open Government
Licence – Canada. See `data/README.md`.

Wall textures (brick, sandstone, clapboard, cedar shingle, foundation
stone) are from Poly Haven (https://polyhaven.com), CC0; the list is in
`textures/facade/LICENSE.txt`, with the bark texture. The leaf and
spruce-branch textures are drawn by `tools/make_leaf_atlas.py` and
`tools/make_needle_branch.py`. The car sounds are synthesized by
`tools/make_car_sounds.py`.

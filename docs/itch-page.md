# The itch.io page

Everything needed to set up Trans-Canada Auto on itch.io: the settings, the
images, and the text to paste in. The images are in `branding/` (redraw them
with `python3 tools/make_branding.py`) and `branding/screens/`.

## 1. Make the page (once)

1. Sign in at https://itch.io and choose **Upload new project** (from the
   arrow by your name, then "Upload new project").
2. Fill it in like this:

| Field | What to put |
|---|---|
| Title | Trans-Canada Auto |
| Project URL | trans-canada-auto |
| Short description or tagline | Drive a whole real city: Charlatown (Charlottetown, PEI), built from open map data and lidar. |
| Classification | Games |
| Kind of project | HTML (you'll still have downloads too) |
| Release status | Prototype |
| Pricing | No payments (or "$0 or donate" if you'd like tips) |
| Uploads | Leave empty for now: the automatic build fills them in (see 3) |
| Embed options | 1280 x 720, **Mobile friendly** off, **Automatically start on page load** off, **Fullscreen button** on, **Enable scrollbars** off, **SharedArrayBuffer support** on (the game needs it to build the town smoothly) |
| Description | Paste the text from "Description" below |
| Genre | Simulation |
| Tags | open-world, driving, sandbox, 3d, canada, real-world, low-poly, exploration, godot, singleplayer |
| AI generation disclosure | Answer honestly. The code and art were written with an AI coding assistant; the map comes from OpenStreetMap and NRCan. |
| Custom noun | game |
| Cover image | `branding/itch/cover.png` |
| Screenshots | The pictures in `branding/screens/` (downtown, riverside, roundabout, university, queen-street, macdougalls, gas-station, megastore, victoria-park, overview) |
| Visibility | **Draft** while you test (only you can see it), then **Public** |

3. Save. Then, under **Edit theme** on the page itself:
   * Banner: `branding/itch/banner.png`
   * Background: `branding/itch/background.png`, not repeated
   * Background colour `#12361f`, text `#f3ead8`, links `#d06a48`,
     buttons `#b4472c` with `#ffffff` text

## 2. Let GitHub send new versions (once)

1. On itch.io: your name > **Settings** > **API keys** > **Generate new API
   key**. Copy it. Don't paste it into a chat or anywhere public.
2. On GitHub, in the trans-canada-auto repository: **Settings** > **Secrets
   and variables** > **Actions**.
   * **Secrets** tab > New repository secret: name `BUTLER_API_KEY`,
     value the key.
   * **Variables** tab > New repository variable: name `ITCH_GAME`, value
     `your-itch-username/trans-canada-auto`.

From then on, every change pushed to `main` is built for Windows and the
web and sent to itch.io within about 15 minutes, as a new version (0.1.N).
Each build's files also stay on its run under the repository's **Actions**
tab for a while, in case you want one directly.

## 3. The uploads

After the first automatic build, open the page's **Edit game** > Uploads:

* `html5`: tick **This file will be played in the browser**.
* `windows`: tick **Windows** as its platform.

## 4. Playing new versions

* In a browser: reload the page.
* On Windows: install the free itch app (https://itch.io/app), find Trans-Canada
  Auto in your library and install it there. The app updates the game by
  itself whenever a new version comes in. No more zips.

## Description

Paste this into the page's description:

---

**Trans-Canada Auto** is an open-world driving game set in real Canadian
places, one map at a time. The first map is **Sand Bar**: the whole of
Charlatown, our Charlottetown, Prince Edward Island, inside the bypass.

Every street is where it really is, from OpenStreetMap. The ground, the
height and roof of every building and some 63,000 trees come from Natural
Resources Canada's lidar survey of the Island, so the hills, the rooflines
and the leafy streets are the real ones. Downtown has its Victorian brick
blocks and shopfronts, the suburbs their houses and yards, and the
waterfront, Victoria Park and University Avenue are all there.

**What you can do**

* Walk anywhere in the city, or take one of three cars: the Dunmore Pony
  GT, the Hanaka Civique or the Fjord Halfton 150. Each drives the way it
  should.
* Drive the whole bypass loop: up Riverside Drive, round the Arterial
  Highway and its roundabouts, and back in by Capital Drive.
* Stop for a coffee at a Tim Hardly's (it won't be what you ordered), a burger at MacDougall's, or
  groceries at SoBuys. Every chain in town has its own made-up stand-in.
* Leave yourself notes about anything you spot (press N).

It's an early prototype: no traffic, missions or sound yet. It's being
built in the open, a piece at a time, on Prince Edward Island.

**Controls:** WASD to walk or drive, mouse to look, E to get in or out of a
car, Space for the handbrake, Esc for the menu. Controllers work too.

**Credits:** Map data © OpenStreetMap contributors, under the Open Database
License (https://www.openstreetmap.org/copyright). Elevation, building
heights and trees: Natural Resources Canada, HRDEM; contains information
licensed under the Open Government Licence – Canada. Made with the Godot
Engine. Businesses in the game are made up.

---

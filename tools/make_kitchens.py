#!/usr/bin/env python3
"""Write data/city/kitchens.json: SpudDash's kitchens that aren't chains.

    python3 tools/make_kitchens.py

The world brands' food places (Tim Hardly's, Burger Baron...) are all out
on University Avenue and the bypass, so SpudDash (scripts/economy/
spuddash.gd) also picks up from the town's own restaurants, cafes and pubs:
every building in the city chunks with an OSM amenity of restaurant,
fast_food, cafe, pub or ice_cream that isn't a world brand. Each gets a
made-up name (design section 8: real businesses never reach the game by
name), chosen by what kind of food the place serves, which is guessed from
its OSM cuisine or name; the real name isn't kept.

Each entry: {"name", "food" (pizza, asian, seafood, pub, cafe, ice_cream,
indian, mexican, diner), "x", "z"} (game metres, as locations.json). Run it
again after refreshing the OSM data or the brands.
"""

import glob
import json
import os

from make_locations import projection, ring_of, centre_area

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

AMENITIES = {"restaurant", "fast_food", "cafe", "pub", "ice_cream", "bar"}
# What kind of food, from words in the cuisine or the name (first match).
FOOD_WORDS = [
    ("pizza", ["pizza"]),
    ("asian", ["noodle", "wok", "sushi", "pho", "thai", "chinese", "japanese", "korean", "k-bbq", "ramen", "vietnam", "asian", "dumpling"]),
    ("indian", ["indian", "punjab", "curry", "tandoor", "masala"]),
    ("mexican", ["taco", "mexican", "burrito", "cantina"]),
    ("seafood", ["lobster", "fish", "oyster", "seafood", "wharf", "mussel", "chowder"]),
    ("pub", ["pub", "ale", "tavern", "brew", "beer", "triangle", "irish"]),
]
# Made-up names by kind of food, handed out in order; then DINER's.
NAMES = {
    "pizza": ["Slice of Life", "Crust Fund"],
    "asian": ["Wok This Way", "The Noodle Committee", "Seoul Searching", "Rolled Back Sushi", "Pho Real"],
    "indian": ["Curry Favour", "Naan of Your Business"],
    "mexican": ["Taco Bout It", "Burrito Bureau"],
    "seafood": ["Shellfish Reasons", "The Lobster Trap Door", "Chowder Council", "Mussel Memory"],
    "pub": ["The Tabled Motion", "The Bylaw Tavern", "Two Years Less a Pint", "The Recess"],
    "cafe": ["Grounds for Appeal", "The Daily Grind Committee", "Brew Process"],
    "ice_cream": ["Cone of Silence", "Scoop of Work"],
    "diner": ["Second Reading Bistro", "The Order Paper", "Consultation Kitchen", "Ribbon Cutters Grill",
              "The Spud Stop", "Island Plate", "Committee Room Diner", "The Shuffle Inn",
              "Pothole Season Grill", "The Come From Away", "Toll Booth Burgers", "The Red Dirt Kitchen",
              "Mainland Envy", "The Backlog", "Parking Ticket Diner", "Permit Pending Cafe"],
}


def food_of(props):
    if props.get("amenity") == "cafe":
        return "cafe"
    if props.get("amenity") == "ice_cream":
        return "ice_cream"
    words = (props.get("cuisine", "") + " " + props.get("name", "")).lower()
    for food, keys in FOOD_WORDS:
        if any(k in words for k in keys):
            return food
    if props.get("amenity") in ("pub", "bar"):
        return "pub"
    return "diner"


def main():
    cfg = json.load(open(os.path.join(ROOT, "data", "map_config.json"), encoding="utf-8"))
    to_ground = projection(cfg)
    branded = set()
    for name, b in cfg.get("brands", {}).items():
        if not name.startswith("_"):
            branded.update(b.get("replaces", []))
    city = os.path.join(ROOT, cfg["city"].replace("res://", ""))
    found = {}  # osm id -> (food, x, z): a building split over chunks counts once
    for path in sorted(glob.glob(os.path.join(city, "chunks", "*.geojson"))):
        for ft in json.load(open(path, encoding="utf-8")).get("features", []):
            p = ft.get("properties", {})
            if p.get("amenity") not in AMENITIES:
                continue
            if p.get("brand") in branded or p.get("name") in branded:
                continue
            ring = ring_of(ft.get("geometry", {}))
            if not ring:
                continue
            (x, z), _ = centre_area([to_ground(q[0], q[1]) for q in ring])
            found.setdefault(p.get("osm_id", "%.0f,%.0f" % (x, z)), (food_of(p), x, z))
    used = {k: 0 for k in NAMES}
    out = []
    # Downtown first (nearest Great George and Richmond), so the names
    # people see most are the first ones on each list.
    for food, x, z in sorted(found.values(), key=lambda e: e[1] * e[1] + e[2] * e[2]):
        names = NAMES.get(food, [])
        if used.get(food, 0) < len(names):
            name = names[used[food]]
            used[food] += 1
        elif used["diner"] < len(NAMES["diner"]):
            name = NAMES["diner"][used["diner"]]
            used["diner"] += 1
        else:
            continue
        out.append({"name": name, "food": food, "x": round(x, 1), "z": round(z, 1)})
    doc = {
        "_comment": "SpudDash's kitchens that aren't chains, made by tools/make_kitchens.py from the OSM chunks: made-up names at the town's own restaurants, cafes and pubs. Don't edit by hand: run the tool again.",
        "kitchens": out,
    }
    with open(os.path.join(city, "kitchens.json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("kitchens.json: %d kitchens" % len(out))


if __name__ == "__main__":
    main()

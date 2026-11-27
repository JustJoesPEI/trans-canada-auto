# Research notes on the town

What's known about each part of Charlottetown, gathered on 2026-11-27 from
CBC's reporting and photos, listings and search snippets, one file per
area: every building's facts with dates, what it looks like, the stand-in
names proposed, props outside, each neighbourhood's look, and the current
events (with sources) that the jokes can lean on. Each entry says how sure
it is: "photo" (seen in a CBC photo), "text" (an article or listing says
so) or "guess".

The landmark entries in `data/map_config.json` were made from these (their
`_comment` says which), and the neighbourhood looks in "neighbourhoods".
The photos themselves are CBC's and aren't kept here; the sources list the
articles (`tools/news_photos.py` fetches them again).

Proposed names not yet approved by Joe, and anything marked "guess",
should be checked against his photos.

## Second pass: street level (the `street_*.json` files)

What the town looks like on foot, gathered the same day from CBC's photos
and reporting: the props, fences, signs and patios of downtown, the
waterfront and Victoria Park, the east side and Stratford, the commercial
strips, and what Charlottetown's yards have in each neighbourhood. Each
item has its position (worked out with `tools/near.py`), how sure it is,
and its source. They were placed as `edit:sl2_` features in
`data/edits.json`; what stands in yards, playgrounds, pitches, patios and
cemeteries is generated instead (`scripts/world/town_dressing.gd`, from
`yards` and each neighbourhood's `yards` in `map_config.json`). Their
`name_checks` say which proposed stand-in names turned out to be real
businesses, and what replaced them.

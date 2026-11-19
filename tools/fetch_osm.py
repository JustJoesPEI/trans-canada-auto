#!/usr/bin/env python3
"""Download a raw OpenStreetMap extract for a bounding box.

Uses the main OSM API "map" call (good for areas up to 0.25 square degrees,
far more than downtown Charlottetown needs). Python 3 standard library only.

    python3 tools/fetch_osm.py 46.2318,-63.1302,46.2378,-63.1212 raw/downtown.osm

If the API is unreachable, export the same box by hand from
https://www.openstreetmap.org/export (Manually select a different area ->
Export) and save it under raw/. Then run tools/osm_to_geojson.py on it.
"""

import sys
import urllib.request

API = "https://api.openstreetmap.org/api/0.6/map?bbox={w},{s},{e},{n}"


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    s, w, n, e = (float(v) for v in sys.argv[1].split(","))
    url = API.format(s=s, w=w, n=n, e=e)
    req = urllib.request.Request(url, headers={"User-Agent": "charlottetown-prototype-osm-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp, open(sys.argv[2], "wb") as out:
        out.write(resp.read())
    print("saved", sys.argv[2])


if __name__ == "__main__":
    main()

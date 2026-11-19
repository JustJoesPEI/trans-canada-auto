class_name Layers
extends RefCounted
## Physics layer bits, named the same as in Project Settings > Layer Names.
##
## GROUND is only ever hit by downward rays (characters and cars find their
## height from it), so curbs never snag anything. SOLID is what bodies bump into.

const GROUND := 1 ## roads, sidewalks, lots
const SOLID := 2 ## buildings, poles, trees, parked cars
const VEHICLES := 4
const CHARACTERS := 8
const BOUNDARY := 16 ## invisible edge of the playable area

class_name JailLines
extends RefCounted
## What Two Years Less a Day says (design.md section 7, "Getting caught",
## and section 8: dry, quick, aimed at the courts, the police and the
## province, never at anyone they're aimed at).
##
## panels() picks the captions for one arrest; JailPanels draws them over
## the art in branding/jail/ (tools/make_jail_panels.py).

## The case falls apart (about one arrest in eight). The first five are the
## design's; the rest in the same voice.
const DISMISSALS := [
	"The evidence was misplaced. Case dismissed.",
	"Evidence locker flooded. Again.",
	"The officer's notebook was used to prop a door. Case dismissed.",
	"Court backlog. Your hearing is set for 2031. Free to go.",
	"Released on a promise to appear. Nobody appears.",
	"The paint was ruled \"not evidence, just a colour.\" Case dismissed.",
	"The arresting officer is away at a conference on arresting. Case dismissed.",
	"Filed in the wrong jurisdiction. The city says it's the FIP's. The FIP says it's the city's. Free to go.",
	"The Crown's key witness was the review of the review. It isn't finished. Case dismissed.",
	"The judge has recused herself. She knows your mother.",
]

## Under the fine, as you walk out: one of these.
const KICKERS := [
	"Payable at City Hall. Open Tuesdays, 10 to 11:30.",
	"Receipt to follow in six to eight weeks.",
	"The province calls it a revenue stream.",
	"A processing fee was waived. The fee for waiving it was not.",
	"Your file goes to a committee. The committee meets in the spring.",
	"The FIP thanks you for your contribution to its next review.",
	"Cheque, cash, or interac. The Crown doesn't do e-transfers yet.",
]

## The radio news after a dismissal, read with a straight face.
const RADIO_DISMISSED := [
	"On the radio: \"Police say the dismissal shows the system is working as intended.\"",
	"On the radio: \"A spokesperson said the force respects the court's decision, and the flood.\"",
	"On the radio: \"The province has announced a review. Of what, it didn't say.\"",
	"On the radio: \"The FIP declined to comment, then commented at length.\"",
]

## The art for each panel (branding/jail/).
const ART := {
	"judge": "res://branding/jail/judge.jpg",
	"served": "res://branding/jail/served.jpg",
	"released": "res://branding/jail/released.jpg",
	"taxpayers": "res://branding/jail/taxpayers.jpg",
	"dismissed": "res://branding/jail/dismissed.jpg",
}


## The panels for an arrest (Wanted.caught's result: level, dismissed,
## fine, cash_before, crackdown), each {"art": key of ART, "caption", "sub"
## (a smaller line, or "")}. The judge always comes first.
static func panels(result: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var fine := int(result.get("fine", 0))
	var lvl := int(result.get("level", 1))
	if bool(result.get("dismissed", false)):
		out.append(_p("judge", "Two years less a d—", ""))
		out.append(_p("dismissed", _pick(DISMISSALS, rng), ""))
		out.append(_p("released", "No fine.", "The Crown \"will review its procedures.\""))
		return out
	out.append(_p("judge", "Two years less a day.", ""))
	out.append(_p("served", "Time served: less a day.", ""))
	if lvl >= 4:
		out.append(_p("released", "Free to go.", _pick(KICKERS, rng)))
		out.append(_p("taxpayers", "Cost to taxpayers: $4.2 million. Fine: %s." % dollars(fine), ""))
	else:
		out.append(_p("released", "Free to go. Fine: %s." % dollars(fine), _broke(result, rng)))
	if bool(result.get("crackdown", false)):
		out.append(_p("taxpayers", "Crackdown statistics: 1 arrest. Overtime: $11 million.", ""))
	return out


## The radio's line on a dismissal.
static func radio(rng: RandomNumberGenerator) -> String:
	return _pick(RADIO_DISMISSED, rng)


## "$1,234".
static func dollars(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if n < 0 else "$") + s + out


static func _broke(result: Dictionary, rng: RandomNumberGenerator) -> String:
	if int(result.get("fine", 0)) == 0:
		return "You're broke. The Crown is used to it."
	return _pick(KICKERS, rng)


static func _p(art: String, caption: String, sub: String) -> Dictionary:
	return {"art": art, "caption": caption, "sub": sub}


static func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	return str(list[rng.randi() % list.size()])

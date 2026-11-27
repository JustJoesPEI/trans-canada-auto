class_name BuildInfo
extends RefCounted
## Which build this is, shown in the menu's corner and in Credits.
##
## "dev" in the repository. The build on GitHub (.github/workflows/build.yml)
## stamps the real number here before it exports: 0.1 and the build's run
## number, the same version itch.io shows, so a player can say which build
## they're on.

const VERSION := "dev"


## The version as players see it: "v0.1.115", or "dev build" when it's run
## from the editor or a copy of the repository.
static func label() -> String:
	return "dev build" if VERSION == "dev" else "v" + VERSION

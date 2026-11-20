class_name TestUserDir
## LT-93: user:// is one directory per project name, so every git worktree of this repo shares
## it. Test data written there goes under a subdirectory keyed by the checkout's absolute path:
## concurrent runs in different worktrees never touch each other's files (one run's cleanup
## used to delete another run's fixtures: "map.json not found"). The game's own user:// use is
## unchanged.

const BASE := "user://test_runs"


## user://test_runs/<first 12 hex chars of md5(absolute project path)>, e.g.
## user://test_runs/3f2a9c01b7de. Stable for one checkout, distinct between worktrees.
static func root() -> String:
	return BASE.path_join(ProjectSettings.globalize_path("res://").md5_text().left(12))


## A path for test data named `name` inside this checkout's root.
static func path(name: String) -> String:
	return root().path_join(name)

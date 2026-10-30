class_name ConfigLoadResult
extends RefCounted
## Outcome of GameConfig.load_from_dir: either a fully valid config or the list of errors.

## Null unless `ok`.
var config: GameConfig
## One line per problem: "<file>: <field path>: <message>".
var errors: Array[String] = []
var ok: bool:
	get:
		return errors.is_empty()

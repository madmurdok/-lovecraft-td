class_name ConfigLoadResult
extends RefCounted
## Outcome of GameConfig.from_dicts (and ConfigLoader.load_dir): either a fully valid config
## or the list of errors.

## Null unless `ok`.
var config: GameConfig
## One line per problem: "<file>: <field path>: <message>".
var errors: Array[String] = []
var ok: bool:
	get:
		return errors.is_empty()

class_name BossTrait
extends EnemyTrait
## LT-97 (D2): a flag trait, no parameters (`"boss": {}`); bosses are never mimicked
## (HallucinationSystem.BOSS_TRAIT). No hook: read by its id.

const ID := "boss"


func id() -> String:
	return ID

class_name NpcXpGrantTest
extends GdUnitTestSuite
## Unit tests for NPCSystem XP granting and level-up resolution (Experience System).
## Covers AC-1 (grant amount), AC-4 (level-up + single signal), AC-5 (multi-threshold),
## AC-6 (cap), AC-8 (serialize/re-derive). Grant semantics are tested directly via grant_xp.

# ---- Helpers ------------------------------------------------------------------

## The `NPCSystem` global is the autoload *instance* (a Node) — `.new()` lives on the script,
## not the instance — so we instantiate a fresh, isolated system from the preloaded script.
const _NPC_SYSTEM_SCRIPT := preload("res://src/gameplay/npc_system.gd")

## Builds a live NPCSystem (its _enter_tree wires to the project autoloads, which exist
## under the test runner). Returns the system; caller adds NPCs via _add_npc.
func _make_npc_system() -> NPCSystem:
	var npc_sys: NPCSystem = _NPC_SYSTEM_SCRIPT.new()
	add_child(npc_sys)
	return npc_sys

func _add_npc(npc_sys: NPCSystem, id: StringName) -> NPCSystem.NPCInstance:
	var npc := NPCSystem.NPCInstance.new()
	npc.npc_id = id
	npc.position = Vector2i.ZERO
	npc.home_base = Vector2i.ZERO
	npc.state = NPCSystem.TaskState.IDLE
	npc_sys.all_npcs[id] = npc
	return npc

# ---- AC-1: grant amount -------------------------------------------------------

func test_grant_xp_increments_total_and_emits_gained() -> void:
	# Arrange
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")
	var gained: Array = []
	npc_sys.npc_xp_gained.connect(func(id: StringName, total: int, into: int, span: int) -> void:
		gained.append([id, total, into, span]))

	# Act
	npc_sys.grant_xp(&"npc_0", ExperienceFormulas.XP_PER_WORK_CYCLE)

	# Assert
	assert_int(npc.xp).is_equal(ExperienceFormulas.XP_PER_WORK_CYCLE)
	assert_int(gained.size()).is_equal(1)
	assert_int(gained[0][1]).is_equal(ExperienceFormulas.XP_PER_WORK_CYCLE)

func test_grant_xp_zero_or_negative_is_noop() -> void:
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")
	npc_sys.grant_xp(&"npc_0", 0)
	npc_sys.grant_xp(&"npc_0", -50)
	assert_int(npc.xp).is_equal(0)

func test_grant_xp_unknown_npc_is_noop() -> void:
	var npc_sys := _make_npc_system()
	npc_sys.grant_xp(&"npc_missing", 100)
	assert_bool(true).is_true()  # no crash

# ---- AC-1: production cycle → assigned worker --------------------------------

func test_production_cycle_grants_xp_to_assigned_worker() -> void:
	# Arrange — worker assigned to the producing building.
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")
	npc.assigned_building_id = &"lumber_1"

	# Act — Building System reports a completed cycle for that building.
	npc_sys._on_production_output_ready("lumber_1", {})

	# Assert
	assert_int(npc.xp).is_equal(ExperienceFormulas.XP_PER_WORK_CYCLE)

func test_production_cycle_without_assigned_worker_grants_nothing() -> void:
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")  # not assigned to the producing building

	npc_sys._on_production_output_ready("lumber_1", {})

	assert_int(npc.xp).is_equal(0)

# ---- AC-4: level-up detection and single signal ------------------------------

func test_grant_crossing_threshold_levels_up_once() -> void:
	# Arrange — 95 XP, one short of the level-2 threshold (100).
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")
	npc.xp = 95
	npc.level = 1
	var levels: Array = []
	npc_sys.npc_leveled_up.connect(func(_id: StringName, lvl: int) -> void: levels.append(lvl))

	# Act — a 10-XP deposit pushes total to 105, crossing into level 2.
	npc_sys.grant_xp(&"npc_0", 10)

	# Assert
	assert_int(npc.level).is_equal(2)
	assert_int(levels.size()).is_equal(1)
	assert_int(levels[0]).is_equal(2)

func test_grant_without_crossing_does_not_level_up() -> void:
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")
	var levels: Array = []
	npc_sys.npc_leveled_up.connect(func(_id: StringName, lvl: int) -> void: levels.append(lvl))

	npc_sys.grant_xp(&"npc_0", 10)  # 10 < 100, still level 1

	assert_int(npc.level).is_equal(1)
	assert_int(levels.size()).is_equal(0)

# ---- AC-5: multiple thresholds crossed in one grant --------------------------

func test_single_large_grant_lands_on_final_level_with_one_signal() -> void:
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")
	var levels: Array = []
	npc_sys.npc_leveled_up.connect(func(_id: StringName, lvl: int) -> void: levels.append(lvl))

	# 400 XP: past cumulative_xp(3)=380 but below cumulative_xp(4)=900 → level 3.
	npc_sys.grant_xp(&"npc_0", 400)

	assert_int(npc.level).is_equal(3)
	assert_int(levels.size()).is_equal(1)
	assert_int(levels[0]).is_equal(3)

# ---- AC-6: cap at MAX_LEVEL ---------------------------------------------------

func test_xp_keeps_rising_past_max_without_further_levelup() -> void:
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")
	var levels: Array = []
	npc_sys.npc_leveled_up.connect(func(_id: StringName, lvl: int) -> void: levels.append(lvl))

	npc_sys.grant_xp(&"npc_0", 999999)  # well past the level-10 threshold
	assert_int(npc.level).is_equal(ExperienceFormulas.MAX_LEVEL)
	var signals_after_max: int = levels.size()
	var xp_at_max: int = npc.xp

	npc_sys.grant_xp(&"npc_0", 1000)  # further work past the cap

	assert_int(npc.xp).is_equal(xp_at_max + 1000)         # XP still accrues
	assert_int(npc.level).is_equal(ExperienceFormulas.MAX_LEVEL)
	assert_int(levels.size()).is_equal(signals_after_max)  # no new level-up signal

# ---- AC-8: serialize / re-derive level on load -------------------------------

func test_xp_survives_serialize_and_level_is_rederived() -> void:
	# Arrange
	var npc_sys := _make_npc_system()
	var npc := _add_npc(npc_sys, &"npc_0")
	npc.xp = 500
	npc.level = 3

	# Act — round-trip through serialize/deserialize into a fresh system.
	var data: Dictionary = npc_sys.serialize()
	var npc_sys2 := _make_npc_system()
	npc_sys2.deserialize(data)

	# Assert
	var restored: NPCSystem.NPCInstance = npc_sys2.all_npcs[&"npc_0"]
	assert_int(restored.xp).is_equal(500)
	assert_int(restored.level).is_equal(ExperienceFormulas.level_for_total_xp(500))
	assert_int(restored.level).is_equal(3)

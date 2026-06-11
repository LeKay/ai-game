## GdUnit4 unit test suite for NPC System Story 001:
## NPC Identity and Recruitment (TR-npc-001, TR-npc-004).
##
## Tests AC-1 through AC-4 plus edge cases.
## NPCSystem is instantiated directly — no Autoload or TickSystem required.

extends GdUnitTestSuite

const NPCSystemScript := preload("res://src/gameplay/npc_system.gd")

var _sys: NPCSystemScript

func before_test() -> void:
	_sys = NPCSystemScript.new()
	auto_free(_sys)


# ---- AC-1: NPC recruitment creates IDLE NPC at house tile -------------------

func test_recruit_npc_returns_non_empty_id() -> void:
	var id := _sys.recruit_npc(Vector2i(10, 10))
	assert_str(str(id)).is_not_empty()


func test_recruit_npc_creates_npc_in_idle_state() -> void:
	var id := _sys.recruit_npc(Vector2i(10, 10))
	assert_int(_sys.get_npc_state(id)).is_equal(NPCSystemScript.TaskState.IDLE)


func test_recruit_npc_sets_position_to_home_base() -> void:
	var id := _sys.recruit_npc(Vector2i(10, 10))
	var pos := _sys.get_npc_position(id)
	assert_int(pos.x).is_equal(10)
	assert_int(pos.y).is_equal(10)


func test_recruit_npc_adds_to_house_counter() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	assert_int(_sys.get_house_npc_count(Vector2i(10, 10))).is_equal(1)


func test_recruit_npc_adds_to_all_npcs_registry() -> void:
	_sys.recruit_npc(Vector2i(3, 3))
	assert_int(_sys.get_npc_count()).is_equal(1)


func test_recruit_npc_emits_npc_recruited_signal() -> void:
	var fired := [false]
	_sys.npc_recruited.connect(func(_id: StringName, _pos: Vector2i) -> void:
		fired[0] = true
	)
	_sys.recruit_npc(Vector2i(5, 7))
	assert_bool(fired[0]).is_true()


func test_recruit_npc_signal_carries_correct_home_base() -> void:
	var received_pos := [Vector2i(-1, -1)]
	_sys.npc_recruited.connect(func(_id: StringName, pos: Vector2i) -> void:
		received_pos[0] = pos
	)
	_sys.recruit_npc(Vector2i(5, 7))
	assert_int(received_pos[0].x).is_equal(5)
	assert_int(received_pos[0].y).is_equal(7)


func test_simultaneous_recruitments_at_different_houses_get_unique_ids() -> void:
	var id1 := _sys.recruit_npc(Vector2i(0, 0))
	var id2 := _sys.recruit_npc(Vector2i(5, 5))
	assert_str(str(id1)).is_not_equal(str(id2))


# ---- AC-2: Second slot unlocks after NPC_SPAWN_DELAY_TICKS ticks ------------

func test_second_slot_blocked_immediately_after_first_recruitment() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	var id2 := _sys.recruit_npc(Vector2i(10, 10))
	assert_str(str(id2)).is_equal("")


func test_second_slot_blocked_one_tick_before_delay() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	_sys._on_ticks_advanced(NPCSystemScript.NPC_SPAWN_DELAY_TICKS - 1)
	var id2 := _sys.recruit_npc(Vector2i(10, 10))
	assert_str(str(id2)).is_equal("")


func test_second_slot_unlocks_exactly_at_delay() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	_sys._on_ticks_advanced(NPCSystemScript.NPC_SPAWN_DELAY_TICKS)
	var id2 := _sys.recruit_npc(Vector2i(10, 10))
	assert_str(str(id2)).is_not_empty()


func test_second_slot_unlocks_after_excess_ticks() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	_sys._on_ticks_advanced(NPCSystemScript.NPC_SPAWN_DELAY_TICKS + 500)
	var id2 := _sys.recruit_npc(Vector2i(10, 10))
	assert_str(str(id2)).is_not_empty()


func test_npc_spawn_delay_ticks_constant_is_1000() -> void:
	assert_int(NPCSystemScript.NPC_SPAWN_DELAY_TICKS).is_equal(1000)


func test_second_slot_ids_are_unique() -> void:
	var id1 := _sys.recruit_npc(Vector2i(10, 10))
	_sys._on_ticks_advanced(NPCSystemScript.NPC_SPAWN_DELAY_TICKS)
	var id2 := _sys.recruit_npc(Vector2i(10, 10))
	assert_str(str(id1)).is_not_equal(str(id2))


# ---- AC-3: Max 2 NPCs per house enforced ------------------------------------

func test_third_recruitment_returns_empty_id() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	_sys._on_ticks_advanced(NPCSystemScript.NPC_SPAWN_DELAY_TICKS)
	_sys.recruit_npc(Vector2i(10, 10))
	var id3 := _sys.recruit_npc(Vector2i(10, 10))
	assert_str(str(id3)).is_equal("")


func test_npc_count_unchanged_when_at_capacity() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	_sys._on_ticks_advanced(NPCSystemScript.NPC_SPAWN_DELAY_TICKS)
	_sys.recruit_npc(Vector2i(10, 10))
	var count_before: int = _sys.get_npc_count()
	_sys.recruit_npc(Vector2i(10, 10))
	assert_int(_sys.get_npc_count()).is_equal(count_before)


func test_house_counter_unchanged_when_at_capacity() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	_sys._on_ticks_advanced(NPCSystemScript.NPC_SPAWN_DELAY_TICKS)
	_sys.recruit_npc(Vector2i(10, 10))
	_sys.recruit_npc(Vector2i(10, 10))
	assert_int(_sys.get_house_npc_count(Vector2i(10, 10))).is_equal(2)


func test_different_houses_have_independent_capacity() -> void:
	_sys.recruit_npc(Vector2i(10, 10))
	_sys._on_ticks_advanced(NPCSystemScript.NPC_SPAWN_DELAY_TICKS)
	_sys.recruit_npc(Vector2i(10, 10))
	# Same house at capacity — blocked
	var blocked := _sys.recruit_npc(Vector2i(10, 10))
	assert_str(str(blocked)).is_equal("")
	# Different house has an open first slot
	var id_other := _sys.recruit_npc(Vector2i(20, 20))
	assert_str(str(id_other)).is_not_empty()


func test_npc_capacity_per_house_constant_is_2() -> void:
	assert_int(NPCSystemScript.NPC_CAPACITY_PER_HOUSE).is_equal(2)


# ---- AC-4: NPCInstance fields correctly initialized ------------------------

func test_npc_instance_state_is_idle() -> void:
	var id := _sys.recruit_npc(Vector2i(5, 5))
	assert_int(_sys.get_npc_state(id)).is_equal(NPCSystemScript.TaskState.IDLE)


func test_npc_instance_position_equals_home_base() -> void:
	var id := _sys.recruit_npc(Vector2i(5, 5))
	var pos := _sys.get_npc_position(id)
	assert_int(pos.x).is_equal(5)
	assert_int(pos.y).is_equal(5)


func test_npc_instance_travel_progress_is_zero() -> void:
	var id := _sys.recruit_npc(Vector2i(5, 5))
	assert_int(_sys.all_npcs[id].travel_progress).is_equal(0)


func test_npc_instance_travel_ticks_total_is_zero() -> void:
	var id := _sys.recruit_npc(Vector2i(5, 5))
	assert_int(_sys.all_npcs[id].travel_ticks_total).is_equal(0)


func test_npc_instance_work_cycle_complete_is_false() -> void:
	var id := _sys.recruit_npc(Vector2i(5, 5))
	assert_bool(_sys.all_npcs[id].work_cycle_complete).is_false()


func test_npc_instance_assigned_building_id_is_empty() -> void:
	var id := _sys.recruit_npc(Vector2i(5, 5))
	assert_str(str(_sys.all_npcs[id].assigned_building_id)).is_equal("")


func test_npc_instance_assigned_storage_id_is_empty() -> void:
	var id := _sys.recruit_npc(Vector2i(5, 5))
	assert_str(str(_sys.all_npcs[id].assigned_storage_id)).is_equal("")


func test_npc_instance_home_base_matches_recruitment_tile() -> void:
	var id := _sys.recruit_npc(Vector2i(5, 5))
	var npc: NPCSystemScript.NPCInstance = _sys.get_npc_instance(id)
	assert_int(npc.home_base.x).is_equal(5)
	assert_int(npc.home_base.y).is_equal(5)

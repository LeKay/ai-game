## Tests that PerkRegistry.generate_choices draws bound goods from the
## level-restricted pool defined by LEVEL_PERK_GROUPS.
## Spec: docs/superpowers/specs/2026-06-28-perk-good-groups-design.md
##
## Uses the live ResourceRegistry autoload (data/resources.json) — `clothing`
## must be tagged perk_group: 1 (Task 2).

extends GdUnitTestSuite

const PerkRegistry := preload("res://src/systems/perks/perk_registry.gd")


## Minimal duck-typed stand-in for NPCSystem.NPCInstance — PerkRegistry only
## reads .profession, .perks, .level on the npc argument.
class _NPCStub:
	var level: int = 1
	var profession: int = -1
	var perks: Array = []


func _stub(level: int, profession: int, perks: Array) -> _NPCStub:
	var n := _NPCStub.new()
	n.level = level
	n.profession = profession
	n.perks = perks
	return n


# ---- AC-4: Level 2 calling cards all bind clothing ---------------------------

func test_level_2_calling_cards_all_bind_clothing() -> void:
	# Frischer NPC: keine Profession, keine Perks, level=2 → Calling-Pfad.
	var npc := _stub(2, -1, [])
	# Mehrfach laufen, weil _calling_cards Zufall enthält (building shuffle).
	for _i in 50:
		var cards: Array = PerkRegistry.generate_choices(npc, 3)
		assert_array(cards).is_not_empty()
		for card: Dictionary in cards:
			assert_that(card[&"good"]).is_equal(&"clothing")


# ---- AC-6: Duplicates allowed when pool has 1 member -------------------------

func test_level_2_can_produce_three_cards_with_same_good() -> void:
	var npc := _stub(2, -1, [])
	var produced_three_cards := false
	for _i in 50:
		var cards: Array = PerkRegistry.generate_choices(npc, 3)
		if cards.size() == 3:
			produced_three_cards = true
			break
	assert_bool(produced_three_cards).is_true()


# ---- AC-5: Level 3+ uses the full perk-eligible pool ------------------------

func test_level_3_uses_full_pool() -> void:
	# NPC mit Profession + bereits 1 Perk → kein Calling-Pfad mehr;
	# generate_choices nimmt LEVEL_PERK_GROUPS.get(3, 0) == 0 → voller Pool.
	var first_perk := {&"perk_id": &"berufung", &"good": &"clothing", &"building_type": 0}
	var npc := _stub(3, BuildingRegistry.BuildingType.LUMBER_CAMP, [first_perk])

	var seen_non_clothing := false
	for _i in 100:
		var cards: Array = PerkRegistry.generate_choices(npc, 3)
		for card: Dictionary in cards:
			var good: StringName = card[&"good"]
			if good != &"" and good != &"clothing":
				seen_non_clothing = true
				break
		if seen_non_clothing:
			break
	# Mit dem vollen Pool (Plank, Cloth, Clothing, Axe, Spindle, Pottery, Salt) und
	# 100 Iterationen × bis zu 3 good-bound Karten ist es extrem unwahrscheinlich,
	# dass nur clothing gezogen wird — würde auf eine fehlerhafte Pool-Auswahl deuten.
	assert_bool(seen_non_clothing).is_true()

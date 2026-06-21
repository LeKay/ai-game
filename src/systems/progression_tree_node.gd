class_name ProgressionTreeNode extends RefCounted
## One node in the Progression Tree graph. Plain data, owned by ProgressionSystem and
## loaded from data/progression_tree.json. See design/quick-specs/progression-tree-2026-06-19.md.

var id: StringName
var display_name: String
## Short glyph (emoji) shown inside the circular node. Data-driven via the JSON "icon"
## field; falls back to a generic marker when empty.
var icon: String = ""
var branch: StringName
## Authoring hint only — the visual ring is recomputed from the same-branch prerequisite
## chain in ProgressionSystem so edges never skip a ring. See _compute_visual_rings().
var ring: int
var prerequisites: Array[StringName] = []
## Invisible prerequisites: node ids that must ALSO be unlocked before this node becomes
## available, but which are deliberately NOT drawn as edges and do NOT influence the radial
## layout. Used to gate a node behind the ability to actually obtain the resources its unlock
## costs (e.g. the house needs Stone, so Shelter hides a dependency on Stonecutting) without
## cluttering the strand graph with cross-branch lines. See ProgressionSystem.is_available().
var hidden_prerequisites: Array[StringName] = []
## Minimum number of unlocked buildings required before this node becomes available (0 = no
## building gate). Used by the Leadership branch so each NPC level-cap node opens only after the
## colony has unlocked enough buildings. See ProgressionSystem.is_available().
var requires_buildings: int = 0
## Each entry: { "type": String, "id": String } — see unlock type values in the spec.
var unlocks: Array[Dictionary] = []
## null = free click; reserved for the future research currency.
var cost: Variant = null

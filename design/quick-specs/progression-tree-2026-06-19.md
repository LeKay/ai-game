# Quick Design Spec: Progression Tree (Tech Tree)

**Type**: New Small System (⚠️ escalation candidate — see *Scope & Process Note*)
**Scope**: A node-graph progression system that gates the entire game's content
(manual gathering, hand-crafting, buildings, and recipes) behind clickable
unlock nodes radiating from a central start node.
**Date**: 2026-06-19
**Estimated Implementation**: > 1 week (full system — this spec documents the agreed
design; implementation should be planned as a proper system, not a 4-hour change)
**Status**: Design agreed 2026-06-19. Step 1 (graph + UI) and Step 2 (gating + Save/Load)
both implemented in code 2026-06-19 — awaiting Godot runtime verification by the user.
**Revised 2026-06-20**: clear-tile paired with harvest; Road/Path moved into the **Paving**
node (after Shelter); **Spindle** moved after Weaving; new **Prospecting** node (Search +
manual Clay mining, after Tooled Quarrying); new **Workbench** node (Crafting Bench upgrade,
after Storage); Shelter made a structural prerequisite for all building nodes (except
Gathering Hut); delivery-limits view filtered to unlocked resources; node tooltips added.
Full GDD promotion + systems-index entry still pending.

---

## Scope & Process Note

This started as a quick-design request but the agreed design **gates every system**
(decision 2 below), needs a **new graph UI**, and must **serialize into save/load**.
That is a new Progression-layer system, which the quick-design skill flags for
escalation to `/design-system`. By user direction (2026-06-19) we are keeping a
**lightweight spec for now** to capture the agreed design; the full GDD (with
Player Fantasy, Formulas, Edge Cases, full Dependencies) should follow before
implementation. When promoted, add it to `design/gdd/systems-index.md` as a
Progression-layer system near the Goal/Perk systems.

---

## Overview

The Progression Tree is the player's master unlock system and the literal backbone
of the game's "manual → automated" pillar. The game begins **from scratch**: the
player can do nothing until they spend unlocks. From a central **Hearth** node,
category branches (Food, Materials, Crafting, Textiles) radiate outward. Clicking a
node unlocks a capability and reveals the next node(s) in that branch — and
sometimes, via **cross-links**, a node in a *different* branch. The graph is
dynamic: edges are drawn as nodes become reachable, so the tree visibly grows as
the player progresses.

Every piece of content unlocks in a consistent **two-step pattern**: first the
**manual** form (gather a resource by hand, hand-craft an item), then the
**automated** form (a building that produces it). This is not a convenience — it
*is* the game's core identity, expressed as a navigable tree.

---

## Decisions (locked 2026-06-19)

| # | Decision | Choice | Notes / future hook |
|---|----------|--------|---------------------|
| 1 | **Unlock cost** | **Free click** for now | Architect the unlock call so a future **research currency** can be required per node. Currency to be introduced by a later system. |
| 2 | **What is gated** | **Everything** — manual gathering, hand-crafting, buildings, and recipes all start locked | The Hearth grants only the bare minimum to begin (see Core Rules). |
| 3 | **Tree shape** | **Radiating category branches** that are *mostly* independent, **with cross-links** | A node may require prerequisites from another branch (e.g. Wood + Stone in Materials → Axe + Pickaxe appear in Crafting). It is a layered DAG drawn as radiating branches. |
| 4 | **Item bootstrap** | **Manual-first, then building** | Unlocking an item (e.g. Axe) first enables its **manual** craft/gather; a **later** node unlocks the **building** that automates it. |

---

## Core Rules

1. **From scratch.** At game start the player has only **The Hearth** (center node)
   and a free **Collection Point** (drop-off depot). No gathering, crafting, road-laying,
   or other building is possible until unlocked. (Road moved off the Hearth into the
   **Paving** node, unlocked after Shelter — see the Food table.)

2. **Unlocking.** Clicking an *available* node unlocks it permanently. A node is
   *available* when **all** of its prerequisite nodes are unlocked (logical AND).
   Unlocks never revert. For now the click is **free**; the data model carries a
   `cost` field (null = free) reserved for the future research currency.

3. **Two-step content rule (manual → automated).** Each resource/item appears as up
   to two nodes:
   - A **manual** node — enables the player to *gather* a resource by hand or
     *hand-craft* an item (using the existing `CraftingRegistry` recipes).
   - An **automation** node — unlocks the **building** (and its building recipe)
     that produces the same output without the player.
   The automation node always has the manual node (and any required tool) as a
   prerequisite.

4. **Cross-links.** Prerequisites may cross branches. Canonical examples:
   - `Wood` + `Stone` (Materials) → unlock `Axe` and `Pickaxe` (Crafting).
   - `Wood` + `Fiber` → unlock `Spindle`.
   - `Axe` → unlock `Lumber Camp` and `Sawmill`; `Pickaxe` → `Stone Mason`;
     `Spindle` → `Weaver` and `Tailor`.
   The UI draws the cross-link edge when the target node becomes available.

5. **Dynamic reveal.** A node is hidden/dimmed until it becomes available, at which
   point its edge(s) animate in from the prerequisite node(s). This is the "tree
   grows as you play" feel.

6. **Worker dependency.** Automation buildings need an NPC. The **Shelter** node
   (Residential House) must therefore be unlocked before any production building
   can actually operate. It is placed early in the Food branch.

---

## Proposed Node Graph

`Ring` = layout distance from center (unlock depth). `⟵` marks a cross-branch prerequisite.

### ⚙️ Settlement Core (granted by the Hearth — available turn one)
Collection Point (depot) only.

> **Manual-clear pairing:** each manual-gather node now *also* unlocks the matching
> **Clear-tile** action for that terrain (e.g. Woodcutting → Chop **and** Clear Tree),
> so clearing a field unlocks together with harvesting it.

> **Shelter is a hard prerequisite for buildings.** Every node that unlocks a building
> requires **Shelter** (directly or transitively), **except Gathering Hut** and the
> Hearth's Collection Point. This makes the worker dependency a structural unlock gate,
> not only a runtime check.

### 🌾 Food
| Ring | Node | Unlocks | Prerequisite |
|---|---|---|---|
| 1 | Foraging | manual gather + clear **Berry** | Hearth |
| 2 | Gathering Hut | automates Berry (Gathering Hut + berry recipe) | Foraging |
| 3 | Shelter | **Residential House** (spawns NPCs) | Gathering Hut |
| 4 | Paving | **Road** building + **lay Path** action | Shelter |
| 4 | Agriculture | **Farm** + Wheat (gather/clear/plant) | Shelter |
| 5 | Milling | **Mill** → Flour | Agriculture |
| 6 | Baking | **Bakery** → Bread | Milling |
| 4 | Hunting | **Hunting Lodge** → Meat + Hide | Shelter |

### 🪵 Materials
| Ring | Node | Unlocks | Prerequisite |
|---|---|---|---|
| 1 | Woodcutting | manual gather + clear **Wood** | Hearth |
| 1 | Fiber Harvesting | manual gather + clear **Fiber** | Hearth |
| 2 | Stonecutting | manual gather + clear **Stone** | Woodcutting |
| 2 | Storage | **Storage Building** | Woodcutting + Shelter ⟵ |
| 3 | Workbench | **Crafting Bench** upgrade (on Storage) | Storage |
| 3 | Forestry | **Lumber Camp** (auto Wood) | Woodcutting + Shelter ⟵ |
| 3 | Masonry | **Stone Mason** (auto Stone) | Stonecutting + Shelter ⟵ |
| 4 | Tooled Quarrying | Stone Mason "with tool" recipe | Masonry + Pickaxe ⟵ |
| 5 | Prospecting | **Search** action + manual mine **Clay** | Tooled Quarrying |
| 5 | Sawmilling | **Sawmill** → Plank | Forestry + Axe |

### 🔨 Crafting / Handwerk
| Ring | Node | Unlocks | Prerequisite |
|---|---|---|---|
| 3 | Toolmaking: Axe | manual-craft **Axe** | Wood + Stone ⟵ |
| 3 | Toolmaking: Pickaxe | manual-craft **Pickaxe** | Wood + Stone ⟵ |
| 4 | Tool Workshop | automates Axe / Pickaxe / Spindle | Axe + Pickaxe + Shelter ⟵ |
| 5 | Spinning Tools: Spindle | manual-craft **Spindle** | Weaving ⟵ |

### 🧵 Textiles
| Ring | Node | Unlocks | Prerequisite |
|---|---|---|---|
| 3 | Spinning | manual-craft **Cloth** (4 Fiber) | Fiber Harvesting |
| 4 | Weaving | **Weaver** (Fiber + Spindle → Cloth) | Spinning + Shelter ⟵ |
| 5 | Garment-making | manual-craft **Clothing** | Spinning |
| 6 | Tailoring | **Tailor** → Clothing | Weaving + Garment-making |

> **Spindle moved after Weaving (2026-06-20).** The Spindle node is now a child of
> **Weaving** (no longer its prerequisite). Weaving requires only Spinning (+ Shelter).

**Critical-path spine (the "linear" reading):**
Foraging → Woodcutting → Stonecutting → Axe / Pickaxe → Lumber Camp / Stone Mason →
Tool Workshop → Spindle → Weaver → Farm → Mill → Bakery → Tailor → Hunting.

---

## Node Data Model (for future implementation)

Stored data-driven (e.g. `data/progression_tree.json`), per the data-driven content rule.

```json
{
  "node_id": "forestry",
  "display_name": "Forestry",
  "branch": "materials",        // core | food | materials | crafting | textiles
  "ring": 4,                     // radial layout depth from center
  "prerequisites": ["axe"],      // node_ids, ALL required (AND); cross-branch allowed
  "unlocks": [
    { "type": "building", "id": "lumber_camp" }
  ],
  "cost": null                   // null = free click; reserved for research currency
}
```

**`unlocks[].type` values:**
- `gather` — enables a manual action (`id` = `PlayerCharacter.ManualActionType` enum name,
  e.g. `CHOP_TREE`, `CLEAR_TREE`, `MINE_CLAY`, `CONSTRUCT_PATH`)
- `manual_recipe` — enables a hand-craft recipe (`id` = CraftingRegistry recipe id)
- `building` — enables placing a building type (`id` = BuildingType)
- `building_recipe` — enables a specific recipe inside a building (e.g. Gathering Hut fiber)
- `upgrade` — enables a building upgrade (`id` = upgrade id, e.g. `crafting_bench`)
- `search` — enables the world-tile **Search** action (`id` is informational, e.g. `SEARCH`)

---

## Visual Implementation

**Chosen approach (2026-06-19): Option B — custom `Node2D`/`Control`, not `GraphEdit`.**

Godot's built-in `GraphEdit` (present in 4.6) was rejected: it is an *editor-tooling*
control (free-form node creation, left/right **port-based** horizontal connections,
draggable nodes, engine-editor styling) and would have to be heavily fought and
re-themed for a fixed, player-facing **radial** tech tree.

We build the tree as a custom layer instead, which fits this project because the
layout is **authored** (each node already knows its `branch` + `ring`), and because
the codebase already renders custom overlays this exact way — `PathDotOverlay`,
`TransportOverlay`, and `BuildingIndicatorLayer` in `src/scenes/map_root/`.

### Meaning of "dynamic"

**Authored layout + animated reveal** — NOT force-directed auto-layout. Node
positions are deterministic from a small formula (`branch → angle`, `ring → radius`
from the center). "Dynamic" means edges and nodes **animate in** as their
prerequisites are met (the "tree grows as you play" feel), via tweens — the graph
does not self-arrange by physics.

### Building blocks

| Concern | Godot primitive | Notes |
|---|---|---|
| Tree world / pan & zoom | a `Node2D` root viewed by a `Camera2D` | ~30 lines for drag-pan + scroll-zoom; clamp zoom to `[zoom_min, zoom_max]` |
| Node visuals | a small node scene (`TextureButton` + label + lock/available/unlocked state) | one PackedScene reused per node, fed from the node data model |
| Node positioning | radial layout helper | `pos = center + Vector2.from_angle(branch_angle) * (ring * ring_radius)`; spread sibling nodes within a branch by index |
| Edges | one `Line2D` per connection (preferred) **or** a single `_draw()` overlay with `draw_polyline` | `Line2D` gives easy per-edge gradients, width, antialiasing, and animation |
| Curved edges | sample a `Curve2D` into the `Line2D` points | gentle bezier from prerequisite → node; cross-links curve across branches |
| Reveal animation | `Tween` on the new edge's draw-progress/alpha + node fade-in | triggered when a node transitions locked → available |
| Redraw trigger | `queue_redraw()` (if using `_draw` overlay) on unlock-state change | event-driven, not per-frame |

### Notes

- All node/edge state is driven by the **node data model** (see above) and the set of
  unlocked node ids — the visual layer is a pure renderer of that state.
- No third-party addon and no `GraphEdit` dependency. `Line2D`, `Camera2D`, `Curve2D`,
  `TextureButton`, and `_draw()` are all stable, in-training-data APIs (low version risk).
- A separate UX spec (`design/ux/progression-tree.md`) should define exact node
  art, colors per state (locked / available / unlocked), edge styling, and the
  reveal animation feel before `/team-ui` implementation.

## Code Integration / Gating Architecture

How the unlock state actually hides locked content in the existing UI. Investigated
in code 2026-06-19.

### Single source of truth: a `ProgressionSystem` Autoload

All unlock state lives in one new Autoload, `ProgressionSystem`
(`src/systems/progression_system.gd`), loaded data-driven from
`data/progression_tree.json` (the node graph above). The UI never owns this state
(per `ui-code` rule "UI must never own game state — display only"); it only queries it.

On load, `ProgressionSystem` builds **reverse-lookup maps** from each node's
`unlocks[]` array, so callers ask about *content* and never hardcode node ids:

```gdscript
ProgressionSystem.is_building_unlocked(building_type: int) -> bool
ProgressionSystem.is_recipe_unlocked(recipe_id: StringName) -> bool        # manual recipes
ProgressionSystem.is_building_recipe_unlocked(building_type, recipe_id) -> bool
ProgressionSystem.is_gather_unlocked(action_type: int) -> bool             # ManualActionType
ProgressionSystem.is_upgrade_unlocked(upgrade_id: StringName) -> bool      # building upgrades
ProgressionSystem.is_search_unlocked() -> bool                            # world-tile Search
ProgressionSystem.is_resource_unlocked(resource_id: StringName) -> bool    # any producing node unlocked
ProgressionSystem.get_node_unlock_description(node_id) -> String           # node tooltip text
ProgressionSystem.unlock(node_id: StringName) -> bool                      # emits node_unlocked
signal node_unlocked(node_id)                                             # UI re-populates on this
```

**Why a capability API and not raw node-id checks in the UI:** the content→node
mapping stays in data + `ProgressionSystem`. When the research currency arrives,
*none of the call sites below change* — only the `unlock()` precondition does.

### The gate points (where locked content reaches the player)

Both `BuildingGrid` and `CraftingGrid` are confirmed **dumb renderers** — they draw
whatever `populate()` is handed, so they need **no change**. Gating goes at the few
assembly points upstream:

| # | Surface | Location | Gate |
|---|---------|----------|------|
| 1 | Build menu | `inventory_screen.gd::_building_list()` | `continue` past types where `is_building_unlocked(btype)` is false |
| 2 | Manual craft menu | `inventory_screen.gd::_crafting_list()` | skip recipes where `is_recipe_unlocked(recipe_id)` is false |
| 3 | Manual gather/forage | `player_character.gd::ManualActionType` surfaced via `tile_interaction_panel.gd` (Harvest button, reads `get_cost_preview()`) | don't offer the action when `is_gather_unlocked(action_type)` is false |
| 4 | Building recipe selectors | `building_detail_panel.gd` (Tool Workshop 3 recipes, Weaver/Tailor fallbacks, Gathering Hut berry/fiber) | filter recipe options; Gathering Hut fiber **also** needs a production-side gate in `BuildingRegistry` |
| 5 | Inventory item grid | `inventory_screen.gd::_to_item_list()` | **no action** — a locked resource can never be obtained, so it never appears |
| 6 | Building upgrades | `BuildingRegistry.get_available_upgrades()` | filter out upgrades where `is_upgrade_unlocked(id)` is false (Crafting Bench gated by the **Workbench** node) |
| 7 | World-tile Search | `tile_interaction_panel.gd::_populate_search_section()` | hide the Search section when `is_search_unlocked()` is false (gated by **Prospecting**) |
| 8 | Clear-tile action | `tile_interaction_panel.gd::_populate_clear_section()` + `player_character` command layer | hide/reject `CLEAR_*` when its `is_gather_unlocked()` is false (pairs with the matching harvest node) |
| 9 | Lay-Path action | `player_character.gd::_try_start_construct_path()` | reject `CONSTRUCT_PATH` when `is_gather_unlocked()` is false (gated by **Paving**) |
| 10 | Storage delivery-limits view | `building_detail_panel.gd::_refresh_storage_config()` | skip resource rows where `is_resource_unlocked(res_id)` is false |
| 11 | Tree node tooltips | `progression_tree_screen.gd::_build_graph()` | each node's `tooltip_text` = `get_node_unlock_description(node_id)` (lists what it unlocks) |

### Two-layer gating (defense in depth)

- **UI layer — hide:** a one-line guard at each assembly point omits locked entries
  before `populate()`. Matches the user's "hide before unlocked" intent and is the
  minimal change.
- **Command layer — reject:** `BuildingRegistry.place_building`, `CraftingRegistry.try_craft`,
  and the manual-action start each reject locked content (new `LOCKED` result code).
  This prevents bypass via hotkeys, queued actions, or edited saves, and keeps the
  system — not the UI — authoritative.

### Hide vs. locked-state (UX choice)

- **Menus (#1, #2, #4):** hide (just `continue`).
- **World-tile gather actions (#3):** the tile is physically on the map, so a
  `🔒 Locked` hint may read better than silently offering nothing. Resolve in the UX spec.

### Refresh

The grids fully rebuild on `populate()`, so on `node_unlocked` the inventory screen /
tile panel re-call their assembly function. Trivial, event-driven.

### Save/Load

`ProgressionSystem` serializes one field — the set of unlocked node ids.

### Prerequisite refactor (done 2026-06-19, ahead of the system)

To gate the build menu cleanly, the hardcoded 13-entry building array in
`inventory_screen.gd::_building_list()` was replaced by a canonical
`BuildingRegistry.BUILDABLE_TYPES` list + public `BuildingRegistry.get_type_display_name()`.
`BuildingRegistry` is now the single source of truth for *which* types are buildable
and their display names, so the future gate is a single `continue` over that list.

## Tuning Knobs

| Knob | Default | Range | Category | Rationale |
|------|---------|-------|----------|-----------|
| `node_cost_enabled` | `false` | bool | gate | Master switch for the future research currency. False = free clicks. |
| `reveal_mode` | `prereqs_met` | {`prereqs_met`, `all_visible`, `adjacent`} | feel | When a node becomes visible. `prereqs_met` = dynamic reveal; `all_visible` = whole tree shown greyed; `adjacent` = show one ring ahead. |
| `branch_count` | 4 | 3–6 | curve | Number of radiating category branches. Adding content may add branches. |
| `ring_radius` | 160 px | 100–300 | layout | Distance between rings in the radial layout (center → ring 1 = 1× this). |
| `zoom_min` / `zoom_max` | 0.5 / 2.0 | 0.25–4.0 | feel | Camera zoom clamp for the tree view. |
| `reveal_anim_duration` | 0.4 s | 0.0–1.5 | feel | Tween time for a newly-available node + its edge(s) to animate in. 0 = instant. |

All values live in data, not hardcoded.

---

## Acceptance Criteria

> `[x]` = implemented in code 2026-06-19; runtime verification in Godot by the user is
> still pending (no local headless run per project policy).

- [x] **From scratch:** On a fresh game the player can only use the Collection Point
      and Road; all gather/craft/build actions are unavailable until their node is unlocked.
- [x] **Free unlock:** Clicking an available node unlocks it with no resource cost and
      it stays unlocked permanently.
- [x] **Prerequisite gating:** A node is only clickable when all its prerequisite nodes
      are unlocked; an attempt on a locked node is rejected with clear feedback.
- [x] **Cross-link fires:** After unlocking both Woodcutting and Stonecutting, the Axe
      and Pickaxe nodes become available and their cross-branch edges are drawn.
- [x] **Manual → automated:** Unlocking e.g. "Axe" enables only hand-crafting; the
      Lumber Camp cannot be built until "Forestry" is unlocked, which itself requires Axe.
- [x] **Worker gate:** No automation building can operate until "Shelter" (Residential
      House) has been unlocked and a House placed to provide an NPC.
- [x] **Dynamic reveal:** Newly available nodes and their edges appear/animate when their
      prerequisites are met (per `reveal_mode`).
- [x] **Future-proofed cost:** The unlock path reads a per-node `cost` (null today) so a
      research currency can be required later without restructuring.
- [x] **Save/Load:** The set of unlocked nodes serializes and restores exactly.
- [x] **No regression:** Manual `CraftingRegistry` recipes and `BuildingRegistry`
      production behave unchanged *once their gating node is unlocked* (gated integration
      tests open the tree via `ProgressionSystem.unlock_all()` in `before_test`).

---

## Example Playthrough (the agreed definition, narrated)

**Beat 0 — From nothing.** The map opens with one lit node at the center: **The
Hearth**. A free Collection Point sits nearby and Roads can be laid, but the
character can't yet gather or craft. Three dim nodes pulse at the Hearth's edge:
**Foraging**, **Woodcutting**, **Fiber Harvesting**.

**Beat 1 — First hands-on survival.** The player clicks **Foraging**; a line snaps
out to a lit Berry node and they can now pick **Berries** by hand. They also unlock
**Woodcutting** and **Fiber Harvesting** — now they can chop **Wood** (bare-handed,
slow) and pull **Fiber** from grass. Unlocking Woodcutting reveals two more nodes:
**Stonecutting** and **Storage**.

**Beat 2 — The first cross-link.** They unlock **Stonecutting** (manual **Stone**).
The instant both Wood and Stone are unlocked, two previously-hidden nodes light up
in the **Crafting** branch and draw edges across to it: **Axe** and **Pickaxe**.
The tree is saying: "you have the materials — now you can make tools." They unlock
**Axe** and hand-craft one (3 Wood + 2 Stone); chopping wood gets viable. They grab
**Pickaxe** too.

**Beat 3 — Manual becomes automated (the core beat).** With an Axe in hand,
**Forestry** becomes available → they place a **Lumber Camp**. But it needs a
worker, so they first push the Food branch to **Shelter** → a **Residential House**
that spawns an NPC. Assign the NPC, and for the first time **Wood flows in without
the player lifting a finger.** **Masonry** → **Stone Mason** follows the same path
for Stone. Unlocking Axe + Pickaxe also opens **Tool Workshop**, which now
*mass-produces* the tools they were crafting by hand.

**Beat 4 — Branching out.** Flush with materials and a small workforce, the player
chooses where to invest:
- **Textiles:** Fiber → **Spinning** (hand-craft Cloth) → **Spindle** (cross-link
  from Wood + Fiber) → **Weaving** (Weaver automates Cloth) → **Garment-making** →
  **Tailoring** (Tailor → Clothing, a high-value trade good).
- **Food security:** **Agriculture** (Farm → Wheat) → **Milling** (Mill → Flour) →
  **Baking** (Bakery → Bread, dense food) — and the side node **Hunting**
  (Hunting Lodge → Meat + Hide).
- **Materials depth:** **Sawmilling** (Sawmill → Plank) for construction-grade output.

**Outcome.** By the end of the session the once-empty Hearth is the hub of a glowing
web. The player has lived the game's whole identity in miniature: *did it by hand,
then taught a building to do it.* Every edge on the tree is a memory of that
transition — and the reserved `cost` field means a later research economy can turn
these free clicks into earned milestones without changing the shape of the tree.

---

## Open Questions (resolve in the full GDD)

1. **Hunting Lodge placement** — it requires adjacent wild/forest; confirm its
   prerequisite (currently Shelter) and whether it needs its own "wild" unlock.
2. **House / Storage ring placement** — confirm Shelter (House) at Food ring 3 and
   Storage at Materials ring 2 feel right in playtest.
3. **Research currency** — source (work XP? gold? a dedicated resource?), earn rate,
   and per-node costs. Deferred to the system that introduces it.
4. **Multiple unlocks per node** — whether some nodes should bundle several unlocks
   (e.g. Tool Workshop → all three tool recipes at once) vs. one-per-node.
5. **Re-lock on load from older save** — confirm unlocked-set is authoritative and
   handle queued actions that become locked (mirror Recipe DB milestone edge case).

---

## Systems Index

Not yet in `design/gdd/systems-index.md`. When promoted to a full GDD, add as a
**Progression-layer** system (alongside Goal #16 and Perk #15), depending on:
Building System, Recipe Database / CraftingRegistry, Inventory/Storage (for the
future currency), and Save/Load.

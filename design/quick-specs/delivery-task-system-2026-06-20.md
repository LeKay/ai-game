# Quick Design Spec: Delivery Task System

**Type**: New Small System (⚠️ escalation candidate — see *Scope Note*)
**Scope**: A task/quest dialog that grants the player **progression points** (the currency
that funds Progression Tree unlocks) in exchange for delivering goods. Each unlocked node
grants one delivery task; completing it pays a reward — currently +1 progression point,
which funds the next unlock. The reward model is **generic** so future tasks can pay other
reward types.
**Date**: 2026-06-20
**Estimated Implementation**: ~10–14 h (new `TaskSystem` autoload + unlock-economy change in
`ProgressionSystem` + new UI dialog + save/load + per-node task data authoring across ~25
nodes + tests)
**Status**: Design drafted 2026-06-20. Decisions locked via Q&A below.

---

## Scope Note

This activates the **"research currency"** the Progression Tree spec
(`progression-tree-2026-06-19.md`, decision 1) explicitly reserved: every node already
carries a `cost` field (`null` today) and there is a `node_cost_enabled` knob. This spec
turns free-click unlocking into **point-gated** unlocking and adds the task loop that mints
those points.

Because it adds a currency, modifies the existing `unlock()` path, adds a UI dialog, and
serializes into save/load, it is an **escalation candidate** — kept lightweight here
(matching the precedent set for the tree spec), flagged for GDD promotion. When promoted,
add it to `design/gdd/systems-index.md` as a Progression-layer system.

---

## Decisions (locked 2026-06-20)

| # | Decision | Choice | Notes |
|---|----------|--------|-------|
| 1 | Unlock cost | **1 progression point per node** | Reads the node's existing `cost` field (default 1). |
| 2 | On Complete | **Items consumed** (delivered) | Removed from inventory across containers. |
| 3 | Task coverage | **Every non-root node authors a task** | Reward: currently +1 point. |
| 4 | Reward model | **Generic** | Tasks pay a typed reward (`progression_point` today; other types later). |
| 5 | Concurrency | **Dialog holds N active tasks** | Not assumed one-ahead — future non-point rewards let tasks pile up. |
| 6 | Authoring location | **Separate file** `data/progression_tasks.json`, keyed by `node_id` | Tree graph and task data stay decoupled. |
| 7 | Reward icon | **Generic icon** for the progression point | Reuse a generic gem/star/marker asset. |

---

## Overview

The Delivery Task System is the **economic engine** of the Progression Tree. The player
starts with **1 progression point** and the Hearth unlocked. Spending the point unlocks one
available node; unlocking grants that node's **delivery task** (e.g. "Deliver 5 Berries").
Fulfilling it — by simply *having* the goods in inventory — enables a **Complete** button
that consumes the goods and pays the task's reward (today **+1 point**), funding the next
unlock. The loop is self-pacing: the tree can only grow as fast as the player can satisfy
deliveries, and each task demands goods the just-unlocked node lets them produce.

Rewards are **generic**: a task pays a typed reward, so later tasks can grant resources,
items, or other currencies instead of progression points. The dialog therefore renders an
arbitrary number of concurrent tasks, each with its own reward tile.

---

## Core Rules

1. **Points balance.** `ProgressionSystem` owns an integer `progression_points`, starting at
   **`starting_points`** (default 1, set in `reset_to_initial`). Shown in the task dialog and
   on the tree top bar.

2. **Unlock costs a point.** `ProgressionSystem.unlock(node_id)` now also requires
   `progression_points >= node.cost` (default `1`). On success it deducts the cost and emits
   `node_unlocked` (unchanged) plus `points_changed`. If prerequisites are met but points are
   insufficient, unlock is **rejected** and the tree shows a transient "Need 1 progression
   point" hint.

3. **Unlock grants a task.** On `node_unlocked`, `TaskSystem` grants that node's authored
   task (active state). The **root Hearth** (pre-unlocked at game start) grants **no** task.
   `unlock_all()` (dev/test) bypasses point cost and grants no tasks, so existing gated
   integration tests stay green.

4. **Fulfillment = possession.** A task lists 1+ required `{resource, amount}`. A required-item
   **tile is "active"** when `InventorySystem.get_global_quantity(resource) >= amount`,
   otherwise "disabled". When **all** tiles are active, the task's **Complete** button enables.

5. **Complete = deliver + reward.** Clicking Complete re-validates every amount, **consumes**
   them from inventory (across containers via `try_consume`), marks the task completed, and
   grants the task's typed reward (see Reward Model). A completed task cannot be re-completed.

6. **No soft-lock (authoring rule).** A node's task may **only** demand resources obtainable
   from that node's own **prerequisite closure** (the node itself + all transitive
   prerequisites). This guarantees every point-funded unlock is fulfillable with what is
   unlocked. Validated at load (see Edge Cases).

7. **Concurrency.** Multiple tasks may be active at once (a point-rewarding task normally
   keeps the player one-ahead, but non-point rewards let tasks accumulate). The dialog renders
   all active tasks and never assumes exactly one.

---

## Reward Model (generic)

A task's reward is a typed object so the system is open to future reward kinds:

```json
"reward": { "type": "progression_point", "amount": 1 }
```

`TaskSystem.complete_task` dispatches on `reward.type`:

| `reward.type` | Effect | Status |
|---|---|---|
| `progression_point` | `ProgressionSystem.add_points(amount)` | implemented now |
| `resource` (future) | deposit `amount` of `reward.resource` into inventory | reserved |
| `item` / other (future) | dispatched by type | reserved |

The reward **tile** in the UI renders from the reward type: `progression_point` shows the
generic point icon + "+amount"; future `resource` rewards show that resource's icon.

---

## Data Model

Tasks are authored in a **separate file**, `data/progression_tasks.json`, keyed by `node_id`
(the Progression Tree graph in `data/progression_tree.json` stays untouched except that each
node's reserved `cost` field is now read as an int):

```json
{
  "version": 1,
  "tasks": {
    "woodcutting": {
      "title": "Deliver Firewood",
      "requires": [ { "resource": "wood", "amount": 5 } ],
      "reward": { "type": "progression_point", "amount": 1 }
    },
    "shelter": {
      "title": "Stock the Larder",
      "requires": [ { "resource": "berry", "amount": 8 } ],
      "reward": { "type": "progression_point", "amount": 1 }
    }
  }
}
```

- A `node_id` absent from `tasks` grants no task (only the root should be absent).
- `requires[]`: `{ resource: StringName, amount: int }` — resources must lie in the node's
  prerequisite closure (Rule 6).
- `cost` (per node, in `progression_tree.json`): previously reserved `null`; now an int,
  defaulting to `1` when null/absent.

---

## Addendum (2026-06-24): Building Requirements

Requirements are now **typed** so a task can demand built structures, not just delivered goods.
A task's `requires[]` may mix both kinds:

```json
"requires": [
  { "type": "resource", "resource": "wood",  "amount": 8 },
  { "type": "building", "building": "STORAGE_BUILDING", "amount": 1 }
]
```

| `type` | Fulfilled when | On Complete | UI tile |
|---|---|---|---|
| `resource` | `get_global_quantity(resource) ≥ amount` (possession) | goods **consumed** | resource glyph + `have/need` |
| `building` | cumulative builds of that type `≥ amount` | **not** consumed (building stays) | building icon (🏛 fallback) + `built/need` |

- `building` is a **BuildingType enum key** (case-insensitive), e.g. `"SAWMILL"`, `"LUMBER_CAMP"`.
- **Cumulative / latching:** `TaskSystem` counts `BuildingRegistry.building_construction_complete`
  per type into `_built_counts`; the count never decrements, so a building requirement stays met
  even if the structure is later demolished. Persisted in save files.
- **Backward compatible:** a typeless entry with a `resource` field is read as `type: "resource"`,
  so all existing delivery tasks keep working unchanged.
- **No soft-lock (Rule 6) still applies:** a building requirement must name a building obtainable
  from the node's prerequisite closure (the node that grants the task usually unlocks it).
- Completion stays **manual** (the Complete button) for consistency and to support mixed tasks
  where resource parts must be consumed.

## Architecture

| Concern | Owner | Notes |
|---|---|---|
| Points balance + spend | **`ProgressionSystem`** (existing autoload) | new `progression_points: int`, `can_afford(node_id)`, `add_points(n)`; `unlock()` checks/deducts; signal `points_changed(total)` |
| Task list + lifecycle | **`TaskSystem`** (new autoload, `src/systems/task_system.gd`) | loads `data/progression_tasks.json`; listens to `ProgressionSystem.node_unlocked` → grant; `get_active_tasks()`, `is_fulfilled(node_id)`, `complete_task(node_id) -> bool`; signals `task_granted`, `task_updated`, `task_completed` |
| Item possession / delivery | `InventorySystem` (existing) | `get_global_quantity` (check), `try_consume` per container (delivery); `TaskSystem` listens to `storage_changed` → emits `task_updated` so tiles refresh live |
| Dialog rendering | **`TaskDialog`** (new `CanvasLayer`, `src/ui/tasks/`) | pure renderer of `TaskSystem`; opened by a new 📋 HUD button beside 🌳; lists task cards |

`TaskSystem` depends on `ProgressionSystem` + `InventorySystem` — register it **after** both
in Project Settings → Autoload. UI never owns state (per `.claude/rules/ui-code.md`).

---

## UI — Task Dialog

- Overlay sibling of `ProgressionTreeScreen` (same toggle pattern, `process_mode = ALWAYS`,
  Esc closes). New HUD button 📋 "Tasks" beside the 🌳 Progression button.
- Header shows the current **progression points** balance (generic point icon + count).
- One **card per active task**, listed vertically; the list scrolls and supports an arbitrary
  number of tasks:
  - **Title** (task `title`).
  - **Required-item tiles** (Kacheln): resource icon + `have / need` count; greyed/disabled
    until `have ≥ need`, highlighted when met.
  - **Reward tile**: rendered from the reward type (generic point icon + "+1" today).
  - **Complete** button: disabled until every required tile is active.
- Live refresh on `storage_changed`, `task_granted`, `task_completed`, `points_changed`.
- Completed tasks drop off the list (a tuning knob can keep them shown faded).

---

## Tuning Knobs

| Knob | Default | Range | Category | Rationale |
|------|---------|-------|----------|-----------|
| `starting_points` | 1 | 0–5 | gate | Points at game start (bootstraps the first unlock). |
| node `cost` | 1 | 1–5 | curve | Points to unlock a node (per-node, in `progression_tree.json`). |
| task `reward.amount` | 1 | 1–3 | curve | Reward magnitude per completed task (per-node, in `progression_tasks.json`). |
| task `requires[].amount` | — | 1–N | curve | Goods demanded per task (per-node, in `progression_tasks.json`). |
| `keep_completed_visible` | false | bool | feel | Keep finished tasks shown faded vs. removed. |

All values are data-driven; none hardcoded.

---

## Edge Cases

1. **0 points, node available** → unlock rejected with hint; not a soft-lock (an active task
   exists to earn the point).
2. **Inventory drops below requirement after tiles activated** (e.g. food eaten) →
   `storage_changed` re-disables the tile and the Complete button before the click; Complete
   re-validates and aborts if short.
3. **Delivery split across containers** → consumption iterates containers via `try_consume`
   until `amount` is met.
4. **Unfulfillable task authored** (resource outside the node's closure) → load-time
   validation in `TaskSystem` logs `push_error` naming the offending node/resource (Rule 6),
   so authoring mistakes fail loudly rather than soft-locking a player.
5. **Old save without points/tasks** → on load set points from the save (default
   `starting_points` if absent); any unlocked non-root node lacking a task record is treated
   as **completed** (grandfathered) so it never blocks.
6. **`unlock_all()` cheat / tests** → bypasses cost, grants no tasks, leaves points untouched.

---

## Save / Load

- `ProgressionSystem.serialize/deserialize` extended to include `progression_points`.
- `TaskSystem` serializes per-node task status (`active` / `completed`); active tasks rebuild
  on load (no re-reward).

---

## Acceptance Criteria

- [ ] **Start state:** fresh game = 1 point, Hearth unlocked, task dialog empty.
- [ ] **Spend to unlock:** unlocking an available node deducts 1 point; at 0 points the same
      click is rejected with feedback.
- [ ] **Task on unlock:** unlocking a node adds its authored task to the dialog; the root
      grants none.
- [ ] **Tile activation:** a required-item tile flips disabled→active exactly when
      `get_global_quantity ≥ amount`, live on inventory change.
- [ ] **Complete gating:** Complete is enabled only when all required tiles are active.
- [ ] **Deliver + reward:** Complete consumes the exact amounts from inventory and grants the
      typed reward (+points today); the task cannot be re-completed.
- [ ] **Loop closes:** completing a point-rewarding task funds the next unlock.
- [ ] **Multiple tasks:** the dialog correctly renders and completes several concurrent active
      tasks independently.
- [ ] **Generic reward:** the reward tile renders from `reward.type`; a non-`progression_point`
      type would render its own icon without code changes to the dialog.
- [ ] **No soft-lock:** every authored task is fulfillable from its node's prerequisite closure
      (load-time validation passes).
- [ ] **Save/Load:** points balance and active/completed task set restore exactly.
- [ ] **No regression:** `unlock_all()` and existing gated integration tests still pass (cost
      bypassed).

---

## Systems Index

Not yet in `design/gdd/systems-index.md`. On GDD promotion, add as a **Progression-layer**
system beside the Progression Tree, depending on: Progression Tree (points/unlock),
Inventory/Storage (possession + delivery), Save/Load, HUD.

---

## Resolved Design Questions (2026-06-20)

1. **Multiple concurrent tasks** — **Yes.** The dialog holds N active tasks; future non-point
   reward types make this the general case. (Decision 5.)
2. **Progression-point icon** — **Generic icon** (reuse a gem/star/marker). (Decision 7.)
3. **Authoring location** — **Separate file** `data/progression_tasks.json`. (Decision 6.)

## Open Questions (resolve in full GDD)

1. **Reward balancing** — whether some nodes should pay >1 point or cost >1 point to pace
   later branches; deferred to playtest.
2. **Future reward types** — concrete list (resource/item/other currency) and their UI tiles,
   when the first non-point reward task is authored.

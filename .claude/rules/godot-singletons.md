---
paths:
  - "src/**"
---

# Godot Singleton & Autoload Rules

## The One Rule

**NEVER use `Engine.get_singleton("Name")` to access a GDScript Autoload.**

`Engine.get_singleton()` is for C++ engine singletons and plugin-registered singletons only.
For GDScript Autoloads (registered in Project Settings → Autoload), use the **global name directly**.

```gdscript
# CORRECT — direct Autoload access (works in every GDScript file)
if PathSystem.has_path(pos):
    return 0.5

var cost := BuildingRegistry.get_movement_cost(building_id)
```

```gdscript
# WRONG — Engine.get_singleton() returns null for GDScript Autoloads
var path_sys = Engine.get_singleton("PathSystem")   # null!
if path_sys != null and path_sys.has_path(pos):     # never runs
    return 0.5
```

## Why it matters

`Engine.get_singleton("PathSystem")` silently returns `null` for GDScript Autoloads.
Code with null checks (`if path_sys != null`) fails silently — no crash, wrong behaviour.
This has caused multiple bugs in this project (road tile costs, building cost lookups).

## Registering Autoloads

Add the script to **Project Settings → Autoload** with a name (e.g. `PathSystem`).
That name is then available as a global in every GDScript file in the project.

## Accessing Autoloads from non-Autoload scripts

Non-Autoload scripts (e.g. `WorldGrid`, which is instantiated as a scene node) can still
access Autoloads by their global name — the global scope is project-wide, not per-node.

```gdscript
class_name WorldGrid extends Node
# No special setup needed — PathSystem, BuildingRegistry etc. are always in scope.

func get_tile_movement_cost(pos: Vector2i) -> float:
    if PathSystem.has_path(pos):   # fine — direct autoload access
        return 0.5
```

## Registered Autoloads in this project

| Name              | Script                                    |
|-------------------|-------------------------------------------|
| TickSystem        | src/systems/tick_system.gd                |
| BuildingRegistry  | src/systems/building_registry.gd          |
| InventorySystem   | src/systems/inventory_system.gd           |
| NPCSystem         | src/gameplay/npc_system.gd                |
| LogisticsSystem   | src/systems/logistics/logistics_system.gd |
| PathSystem        | src/systems/path_system.gd                |
| HungerSystem      | src/systems/hunger_system.gd              |
| CraftingRegistry  | src/gameplay/crafting_registry.gd         |
| WildSystem        | src/systems/wild_system.gd                |
| ProgressionSystem | src/systems/progression_system.gd         |
| TaskSystem        | src/systems/task_system.gd                |

Extend this table whenever a new Autoload is added.

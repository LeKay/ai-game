# Resource System

> **Status**: In Design
> **Author**: User + Claude (Sonnet 4.5)
> **Last Updated**: 2026-05-05
> **Implements Pillar**: Pillar 1 (Manual → Automated), Pillar 2 (Information Transparency), Pillar 3 (Optimization Over Expansion)

## Overview

The Resource System defines the canonical set of collectable and tradeable resources in the game world — wood, stone, fiber, berries, tools, and all production chain intermediates — as a centralized data registry. It specifies each resource's attributes (name, category, stack limits, charge where applicable, icon references) and serves as the single source of truth for what can be stored in inventory, consumed in recipes, harvested from tiles, or traded. All gameplay systems that handle items (Inventory/Storage, Production, Manual Labor, Hunger, Trading) reference this registry rather than hardcoding resource types, enabling data-driven expansion (adding new resources doesn't require code changes).

For the player, the Resource System is invisible infrastructure — they experience it as "I can collect wood and stone" or "tools wear out over time", not as a database. Its design directly serves **Pillar 1 (Manual → Automated)** by making resources tangible — their names, icons, and values reflect what they are and what they cost to produce, anchoring the player's manual labor in something real. It also serves **Pillar 2 (Information Transparency)** by ensuring every resource has consistent naming and attributes across all UI displays, tooltips, and production chains, and **Pillar 3 (Optimization Over Expansion)** by limiting the resource type count (forcing creative chain design rather than sprawling variety). The system distinguishes **Consumables** (consumables like food and clothing, consumed daily by NPCs and the player) from **Production Goods** (production goods like raw materials and intermediates, used as recipe inputs), enabling different consumption mechanics for each category.

## Player Fantasy

In the beginning, every piece of wood has a name. Not literally, but you *know* it — you remember chopping the tree, carrying the logs, watching the tick counter count down. When you place those 10 logs and 3 stones to build your first house, you feel the cost in your hands. Resources are scarce, personal, heavy. You pick up a stone and think: "I need one more for the tool."

But slowly, almost without noticing, the texture of resources changes. Wood stops being "the thing I chop" and becomes "the thing the lumberyard produces." Planks stop being precious and become a number on a dashboard. Your storage fills with goods you never touched. You open the inventory and see 47 planks, 12 bread, 3 fine clothing — and you feel wealthy not because the numbers are big, but because you remember when each one of those goods required your direct labor.

The Resource System exists to make that shift *legible*. Every resource carries implicit memory — of what it cost to produce, what chain created it, where it came from. Early, resources are tangible (you carry them). Late, resources are systemic (they flow through chains). The emotional payoff is the distance between those two states: "I used to carry every log. Now logs carry themselves."

## Detailed Design

### Core Rules

**1. Resource Definition Schema**

Every resource in the registry has the following attributes:

**Required Attributes:**
- **`id`** (string, unique) — Machine-readable identifier (e.g., `"wood"`, `"plank"`, `"tool"`). Lowercase alphanumeric + underscore only. Never changes once assigned.
- **`display_name`** (string) — Human-readable name shown in UI (e.g., "Wood", "Planks"). Can be localized.
- **`category`** (enum: `"consumable"` | `"production_good"`) — Primary classification:
  - `"consumable"`: Food, clothing, luxury goods — consumed daily by NPCs/player
  - `"production_good"`: Raw materials, tools, intermediates — used as recipe inputs
- **`stack_limit`** (integer >= 1) — Maximum quantity per inventory slot. Every resource must explicitly set this value.
- **`icon_path`** (string) — Relative path to icon sprite (e.g., `"assets/ui/icons/resources/wood.png"`).

**Optional Attributes:**
- **`subcategory`** (string) — Finer classification for UI sorting (e.g., `"raw_material"`, `"intermediate"`, `"food"`, `"tool"`). Display-only; systems use `category` and `tags` for logic.
- **`weight`** (float, kg) — Weight per unit for logistics calculations. Null = weightless (0 kg).
- **`base_value`** (integer, gold) — Default trading price. Null = not tradeable.
- **`max_charge`** (float, default 100.0) — Maximum charge per item unit. All items carry this value. A slot's total available charge equals `quantity × max_charge` when fully stocked. Productions can consume fractional charge amounts; the slot is emptied only when `current_charge <= 0`.
- **`description`** (string, max 120 chars) — Tooltip flavor text.
- **`tags`** (array of strings) — Gameplay flags (e.g., `["burnable"]`, `["tier_2_input"]`). Free-text.

**2. Stack and Charge Rules**

- **All resources** (`stack_limit >= 1`): Multiple units occupy one slot until the stack limit is reached. Each slot tracks a `current_charge: float` representing the **total remaining charge for all units** in that slot. When fully stocked, `current_charge == quantity × max_charge`. Recipes can consume fractional charge amounts; the slot is cleared only when `current_charge <= 0`.
- **Charge is additive for stacked items:** Three units of wood (max_charge 100 each) provide 300 total charge. A production consuming 0.25 charge leaves 299.75 remaining — all three items remain in the slot.
- **Enforcement:** `stack_limit` must be >= 1 for all resources. There is no special stack-limit-1 rule for any category.

**3. Data Format**

- **File:** `res://data/resources.json`
- **Structure:** JSON object with version number and resources array
- **Example:**
```json
{
  "version": 1,
  "last_updated": "2026-05-05",
  "resources": [
    {
      "id": "wood",
      "display_name": "Wood",
      "category": "production_good",
      "subcategory": "raw_material",
      "stack_limit": 99,
      "weight": 2.5,
      "base_value": 2,
      "max_charge": 100.0,
      "icon_path": "assets/ui/icons/resources/wood.png",
      "description": "Freshly chopped logs.",
      "tags": ["burnable", "construction_material"]
    },
    {
      "id": "tool",
      "display_name": "Tool",
      "category": "production_good",
      "subcategory": "tool",
      "stack_limit": 10,
      "weight": 2.0,
      "base_value": 30,
      "max_charge": 100.0,
      "icon_path": "assets/ui/icons/tools/tool.png",
      "description": "A sturdy general-purpose tool for chopping, mining, and crafting.",
      "tags": ["tool"]
    }
  ]
}
```

**4. Extensibility**

- New resources can be added without code changes (systems iterate registry at runtime)
- Schema versioning: Increment `version` number when adding required fields. Systems apply migration rules for older saves.
- Deprecation: Add `"deprecated": true` flag to hide resource from UI while keeping it loadable from old saves

**5. Validation Rules**

Design-time validation (pre-commit script):
- All `id` values unique
- All `icon_path` files exist
- `stack_limit` >= 1 for all resources
- `max_charge` > 0.0 when provided (defaults to 100.0 if omitted)
- `category` is valid enum value
- All resources registered in `design/registry/entities.yaml` items section

Runtime validation:
- Registry version compatible
- Icon sprites loaded (fallback to placeholder if missing)

### States and Transitions

The Resource System is stateless — it's a data registry, not a simulation. Resources have no states or transitions at the system level. Individual resource instances (held in inventory slots) may have state (`current_charge` per slot), but that state is managed by the Inventory System, not the Resource System.

### Interactions with Other Systems

| System | Interaction | Data Flow | Interface |
|--------|-------------|-----------|-----------|
| **Inventory/Storage** | Stores resource instances | Resource System → Inventory: schema lookup via `get_resource(id)` | Inventory validates operations against registry, stores `{resource_id, quantity, current_charge}` per slot |
| **Production** | Recipes reference resources by `id` | Resource System → Production: filter `category: production_good` | Recipes deduct inputs or consume fractional charge (per-recipe `charge_cost`), add outputs |
| **Manual Labor** | Harvesting yields resources | Resource System → Manual Labor: resource definitions for tiles | Manual actions add resource instances to player inventory |
| **Hunger** | Daily consumption | Resource System → Hunger: filter `category: consumable` | Hunger deducts charge (= quantity × max_charge) from storage at day transition |
| **Trading** | Merchants stock tradeable resources | Resource System → Trading: filter `base_value != null` | Buy/sell prices = `base_value × merchant_markup` |
| **HUD/UI** | Display resource info | Resource System → UI: `display_name`, `icon_path`, `description` | UI polls registry for display, shows charge bars for items with partial consumption |

## Formulas

The Resource System is a data registry and does not perform calculations. However, dependent systems use resource attributes in their formulas. The formulas below document how resource attributes feed into other systems' calculations.

**1. Stack Overflow Calculation** (used by Inventory System)

When adding resources to inventory, determine if a new stack is needed:

`stacks_needed = ceil(quantity_to_add / stack_limit)`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| quantity_to_add | q | int | 1-999 | Amount of resource being added to inventory |
| stack_limit | s | int | 1-999 | Maximum units per stack (from resource definition) |
| stacks_needed | n | int | 1-999 | Number of inventory slots required |

**Output Range:** [1, 999] — bounded by max quantity (999) with minimum stack_limit (1). Under typical VS play (stack_limit ≥ 50, quantity ≤ 300), range is [1, 6].

**Example:**
```
Adding 250 wood (stack_limit: 99):
stacks_needed = ceil(250 / 99) = ceil(2.53) = 3 slots
```

**2. Item Charge Remaining** (used by HUD/Tooltip UI)

Display an item's remaining charge as a percentage of the slot's maximum capacity:

`charge_percent = (current_charge / (quantity × max_charge)) × 100`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| current_charge | c_cur | float | 0.0–(quantity × max_charge) | Total remaining charge for all units in the slot |
| quantity | q | int | 1–stack_limit | Number of units in the slot |
| max_charge | c_max | float | > 0.0 | Maximum charge per unit (from resource definition, default 100.0) |
| charge_percent | p | float | 0.0–100.0 | Percentage for UI display |

**Output Range:** [0.0, 100.0] %

**Example:**
```
Tool slot: quantity = 2, max_charge = 100.0, current_charge = 150.0
charge_percent = (150.0 / (2 × 100.0)) × 100 = 75.0%
UI displays: "Tool ×2 [██████░░] 75%"

Wood slot: quantity = 3, max_charge = 100.0, current_charge = 299.75
charge_percent = (299.75 / 300.0) × 100 ≈ 99.9%
UI displays: "Wood ×3 [████████] ~100%"
```

**3. Weight Per Stack** (used by Logistics System, future)

Calculate total weight of a stack of resources:

`stack_weight = quantity × weight_per_unit`

**Variables:**
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| quantity | q | int | 1–stack_limit | Number of units in this stack |
| weight_per_unit | w | float | 0.0–unbounded | Weight from resource definition (kg) |
| stack_weight | W | float | 0.0–49,950 | Total weight of stack (kg) |

**Output Range:** [0.0, 49,950] kg — practical maximum: `stack_limit(999) × max_weight(50.0)`. Under typical VS play (stack_limit ≤ 99, weight ≤ 2.5 kg), range is 0–247.5 kg per stack.

**Example:**
```
99 wood (weight: 2.5 kg per unit):
stack_weight = 99 × 2.5 = 247.5 kg
```

**Note:** Weight calculation is future-proofing for encumbrance/transport capacity systems not in Vertical Slice.

## Edge Cases

**Invalid/Missing Data:**
- **If resource missing required field** (`id`, `display_name`, `category`, `stack_limit`, `icon_path`): Design-time validation blocks commit. Runtime: skip resource, log error, use placeholder.
- **If resource has invalid `id` format** (uppercase, spaces, special chars): Design-time validation rejects. Runtime: sanitize (`"My Tool"` → `"my_tool"`), attempt registry match.
- **If duplicate resource IDs**: Design-time validation blocks. Runtime: last-defined wins, log critical warning.
- **If invalid `category` value** (not `consumable` or `production_good`): Default to `"production_good"`, log error.
- **If missing icon file**: Design-time validation warns. Runtime: load placeholder icon (`assets/ui/icons/placeholder.png`).

**Boundary Values:**
- **If `stack_limit = 1`**: Valid non-stackable item. Each unit occupies one inventory slot. The slot still tracks `current_charge` for fractional consumption.
- **If `max_charge` omitted or null**: Defaults to 100.0. Log info-level notice.
- **If `weight = 0` or `null`**: Treat as weightless (0 kg). Does not contribute to logistics calculations.
- **If `base_value < 0`**: Invalid — design-time validation blocks. Runtime: treat as `null` (not tradeable), log critical error.

**Charge Edge Cases:**
- **If recipe's `charge_cost` exceeds available `current_charge` in storage**: Production UI shows recipe as disabled with tooltip "Insufficient charge ([current]/[required])". Cannot start production.
- **If `current_charge` reaches exactly 0**: Slot is cleared immediately (resource_id = null, quantity = 0). A notification may be shown: "[Item Name] fully consumed."
- **If `current_charge` goes negative** (data corruption): Clamp to 0, clear slot, log critical error.

**Cross-System Reference Failures:**
- **If recipe references unknown resource** (not in registry): Design-time validation checks all recipe IDs. Runtime: mark recipe as INVALID, show "Missing ingredient: [id]" in tooltip.
- **If harvest tile yields unknown resource**: Harvest succeeds but yields nothing. Tooltip shows "Nothing to harvest". Log warning.
- **If merchant stocks unknown resource**: Skip that inventory entry. Merchant shows remaining valid items. If all invalid, shows "Out of Stock".

**Save/Load Edge Cases:**
- **If save contains deprecated resource** (`"deprecated": true` in registry): Load instance normally, show grayed-out icon + "(Deprecated)" suffix. Cannot be used in new recipes but can be dropped/traded. Hidden from new loot/harvest.
- **If save contains completely removed resource** (no registry entry): Create temporary runtime-only entry with placeholder icon, display as "Unknown Item". Player can drop but not use. Log critical warning.
- **If registry version downgrade** (save v2, game v1): Block load, display error "Save created with newer game version". Return to main menu.
- **If registry version upgrade** (save v1, game v2 with new required field): Apply migration rules (e.g., default `weight: 0.0`). Log migration, upgrade save on next save.

**Stack Edge Cases:**
- **If adding to full stack** (stack at `stack_limit`, adding more): Create new stack in next available slot. If no slots, display "Inventory Full", addition fails.
- **If merging stacks with overflow** (Slot A: 60, Slot B: 50, limit: 99, merge B→A): Slot A capped at 99, Slot B has remainder (11). UI shows "Merged 39 units, 11 remaining".
- **If `stack_limit = 0`** (invalid): Design-time validation blocks. Runtime: force `stack_limit = 1`, log critical error.

**UI Display Edge Cases:**
- **If `display_name` > 30 characters**: Design-time validation warns. Runtime: truncate with ellipsis in compact views, show full name in tooltip.
- **If `description` > 120 characters**: Design-time validation warns. Runtime: display full text in tooltip.
- **If `description` missing or null**: Tooltip shows name and stats only. No error (description is optional).

## Dependencies

**Upstream (depends on):**
- None — Resource System is a Foundation layer system with zero dependencies

**Downstream (depended on by):**
- **Inventory/Storage System** — Stores resource instances, validates operations against registry
- **Production System** — Recipes reference resources by ID, consume inputs, produce outputs
- **Manual Labor System** — Harvest actions yield resources defined in registry
- **Hunger System** — Daily consumption filters `category: consumable` resources
- **Trading System** — Merchants stock resources with `base_value != null`
- **HUD/UI Systems** — Display resource `display_name`, `icon_path`, charge bars
- **Building System** — Build costs reference resource IDs and quantities
- **Logistics System** — NPC transport uses `weight` attribute for capacity calculations (future)
- **Recipe Database System** — Recipe definitions reference resource IDs as inputs/outputs
- **NPC System** — NPC tier consumption requires `category: consumable` resources
- **Population Tier System** — Tier progression requires specific `tags` (e.g., `["tier_2_input"]`)

**Interface Stability:**
- Resource `id` values are PERMANENT — never rename or delete (use deprecation flag instead)
- All other attributes (display_name, stack_limit, etc.) can change without breaking saves
- Schema version increments trigger migration rules for backward compatibility

## Tuning Knobs

The Resource System is primarily a data definition layer, so tuning knobs are per-resource attributes, not global system settings.

**Per-Resource Tuning Knobs:**
| Knob | Type | Safe Range | Effect | Notes |
|------|------|------------|--------|-------|
| `stack_limit` | int | 1-999 | Controls inventory density | Lower = more slots needed. Higher = easier hoarding. Default: 99 for most resources. |
| `weight` | float | 0.0-50.0 kg | Affects logistics transport capacity | Heavier resources slow NPC carriers (future system). 0 = weightless. |
| `base_value` | int | 1-1000 gold | Merchant buy/sell price baseline | Higher = more valuable trading commodity. 0 = worthless (can't sell). |
| `max_charge` | float | 1.0-10000.0 | Charge per item unit | Higher = item lasts longer under partial consumption. Default 100.0. Low values (e.g. 1.0) make items behave like traditional consumables (one use = gone). |

**Global System Settings:**
- **Validation Level** (`"strict"` | `"warn"` | `"permissive"`): Design-time validation severity. Default: `"strict"` (blocks invalid data).
- **Placeholder Icon Path**: Fallback when `icon_path` missing. Default: `"assets/ui/icons/placeholder.png"`.
- **Registry File Path**: Location of `resources.json`. Default: `"res://data/resources.json"`.

**What breaks if tuned incorrectly:**
- `stack_limit = 999`: UI displays become unwieldy ("999/999 Wood" overflows tooltip). Inventory management trivial (one slot holds everything).
- `weight > 100 kg`: Single unit exceeds base NPC carrying capacity (100 kg). NPC carriers cannot move this resource.
- `max_charge < 1.0`: Items vanish after a single fractional consumption; adjust recipe `charge_cost` accordingly.

## Visual/Audio Requirements

The Resource System is pure data infrastructure and has no direct visual or audio components. Visual requirements for resource display are documented in the UI Requirements section below.

## UI Requirements

The Resource System itself has no UI — it's a data provider. However, it defines requirements for UI systems that display resource information.

**Icon Display (HUD System, Inventory UI, Tooltip UI):**
- All resource icons must be 32×32 pixels (or scalable vector format)
- Icon file path format: `assets/ui/icons/[category]/[id].png` (e.g., `assets/ui/icons/resources/wood.png`, `assets/ui/icons/tools/tool.png`)
- Placeholder icon (`assets/ui/icons/placeholder.png`) shown when `icon_path` is missing or invalid
- Icons should visually distinguish categories: warm colors for consumables, cool colors for production goods, metallic tones for tools

**Resource Name Display:**
- Use `display_name` attribute (not `id`) in all player-facing UI
- If `display_name` > 30 characters, truncate with ellipsis in compact views (e.g., inventory grid)
- Show full `display_name` in tooltips on hover

**Tooltip Requirements:**
- **Minimum tooltip content** (all resources):
  - Icon + `display_name`
  - Category label: "Consumable" or "Production Good"
  - Stack info: "Stack Limit: [stack_limit]"
- **Additional tooltip content** (if attributes present):
  - `description` text (max 120 chars, flavor text)
  - `weight`: "Weight: [weight] kg per unit"
  - `base_value`: "Value: [base_value] gold" (only if tradeable)
  - `max_charge` (when partially consumed): "Charge: [current_charge] / [quantity × max_charge] ([percent]%)"

**Charge Bar (Items with partial consumption):**
- Display a visual charge indicator for items whose `current_charge < quantity × max_charge` in inventory slots
- Color-coded: Green (100–66%), Yellow (65–33%), Red (32–1%), Flashing Red (< 10%)
- Tooltip shows exact numbers: "Charge: 225.0 / 300.0 (75%)"
- Slot cleared immediately when `current_charge <= 0` (no display needed)

**Deprecated Resource Display:**
- Icon shown with 50% opacity (grayed-out)
- Display name appended with " (Deprecated)" suffix
- Tooltip includes warning: "This item is deprecated and cannot be used in new recipes."

**Unknown Resource Display (Save/Load Edge Case):**
- Show placeholder icon with question mark
- Display name: "Unknown Item"
- Tooltip: "This item's data is missing from the current game version. You can drop it but not use it."

**Category Color Coding (Recommended, Not Required):**
- Consumables: Yellow/orange icon borders or background tint
- Production Goods: Blue/gray icon borders or background tint
- Tools (subset of production goods): Metallic silver/bronze icon borders

**Sorting and Filtering:**
- Inventory UI should allow filtering by `category` and `subcategory`
- Default sort order: Category (consumables first), then Subcategory (food → clothing → luxury), then alphabetical by `display_name`
- Alternate sort orders: By `base_value` (most valuable first), by `weight` (lightest first)

**Stack Count Display:**
- Show quantity badge on inventory icon: "99" in bottom-right corner
- If quantity = 1 and resource is stackable, show no badge (implied single unit)
- If quantity >= 1000, abbreviate: "1.2k", "15k", etc.

## Acceptance Criteria

- **GIVEN** the resource registry is loaded, **WHEN** querying `get_definition("wood")`, **THEN** return wood's full schema (display_name: "Wood", category: "production_good", stack_limit: 99, max_charge: 100.0, etc.)
- **GIVEN** a stackable resource (wood, stack_limit: 99), **WHEN** adding 150 units to empty inventory, **THEN** create 2 stacks (99 + 51) in separate slots
- **GIVEN** a chargeable resource (tool, max_charge: 100.0), **WHEN** tool slot reaches current_charge = 0.0, **THEN** tool slot is cleared and removed from inventory
- **GIVEN** a resource with invalid category ("misc"), **WHEN** loading registry at runtime, **THEN** default to `"production_good"`, log error, continue loading
- **GIVEN** a recipe references resource ID "unknown_item" not in registry, **WHEN** validating recipe at runtime, **THEN** mark recipe as INVALID, display "Missing ingredient: unknown_item" in UI
- **GIVEN** a deprecated resource ("old_tool") in player's save, **WHEN** loading save, **THEN** load item with grayed-out icon + "(Deprecated)" suffix, hide from loot/merchant inventories
- **GIVEN** a save with registry v1, game with registry v2 (added optional field `weight`), **WHEN** loading save, **THEN** apply migration rule (default `weight: 0.0`), log migration, upgrade save on next save
- **GIVEN** all required fields present and valid, **WHEN** pre-commit validation runs, **THEN** validation passes with no errors or warnings
- **GIVEN** resources with `base_value != null`, **WHEN** Trading System queries tradeable resources, **THEN** return only resources with non-null base_value

## Open Questions

None at this time. Resource System schema is well-defined for Vertical Slice. Future considerations (not blocking):
- Rarity tiers (common/rare/epic) for loot systems (post-MVP)
- Resource quality variants (low/high quality wood) for advanced crafting (Full Vision)
- Seasonal/event resources (limited-time items) for live-ops (post-1.0)

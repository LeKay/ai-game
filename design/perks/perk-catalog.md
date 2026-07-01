# Perk System — Brainstorm & Catalog

> **Status**: Brainstorming (2026-06-17)
> **Author**: User + Claude (Opus 4.8)
> **Extends**: [Experience System](../gdd/experience-system.md)
> **Purpose**: Living catalog of perk ideas. Perks proposed one at a time; accepted ones land
> in the "Accepted Perks" table below. Nothing here is implemented yet.

## Agreed Model (from design discussion)

- **Level-up reward**: on each level-up the player is offered **3 perk cards** to choose from
  (pick exactly one). The cards are large, side-by-side on screen.
- **Where**: level-ups are resolved in the **Day Overview UI**. The "next day" button is locked
  until *all* pending level-ups (across all NPCs) have been resolved.
- **Bound good (Ware)**: every perk card is tied to a **randomly chosen good**. The perk's effect
  is only active while the NPC is **supplied that good**, assigned in the NPC detail UI exactly
  like food (consumed per day).
- **Eligible goods**: only goods **assigned to a perk group** (`perk_group: <int>` in
  `data/resources.json`) can be drawn as a perk's bound good. The group selected for a given
  level-up is defined by `LEVEL_PERK_GROUPS` in `src/systems/perks/perk_registry.gd`.
- **Effect domain**: perks change **balancing** — e.g. less nutrition needed per day, more XP in a
  profession, higher max efficiency, faster travel, etc. Perks are permanent once chosen (the good
  supply gates whether the bonus is *currently* active).
- **Building-bound perks** (new category): some perks also pick a **random production building
  type** when the card is generated, in addition to the random good. The card then reads e.g.
  "Ergiebig · Lumber Camp · Stoff", and the effect applies to **all buildings of that type** while
  the NPC is supplied. Each building-bound perk may **restrict its building-type pool** to types
  where it makes sense (e.g. input-reduction perks only roll processing buildings that have inputs).
- **Profession gate** (tech-tree): building-bound *effect* perks (#6 Ergiebig, #8 Sparsam,
  #10 Geräumig) are **locked until the NPC has a profession**. A profession is set by the
  **Berufung** card (#11), which permanently fixes the NPC to one production building type and grants
  +50 % work XP there. After specialization, that NPC's building-bound perks are offered **only for
  the profession's building type**. So the order is: unspecialized NPC → may be offered Berufung →
  once specialized → building-bound perks for that profession unlock. One profession per NPC,
  permanent.

## Resolved Rules

- **Profession** = building type (via building-bound perks).
- **Building binding** = building **type** (not a specific instance).
- **Stacking amount**: an NPC accumulates **unlimited** perks (1 per level-up). Natural balance is
  the upkeep — each perk consumes its own bound good per day.
- **Effect stacking**: identical effects **fully stack** (e.g. XP ×1.25 ×1.25 = ×1.5625), including
  the efficiency-cap perks. The only hard ceiling is the engine clamp `EFFICIENCY_MAX = 2.0` in F1
  (NPC efficiency can never exceed 200 %). Within a single 3-card draw, no two **identical** cards
  (same effect + same good) are offered.
- **Bound-good consumption**: a perk's good is consumed **once per day at the day transition**,
  exactly like food. Supplied that day → perk active for the whole next day; missing → perk dormant
  that day (good not consumed). No mid-day toggling — the active set is fixed per day.

## Open Questions (revisit as we go)

- (none currently)

## Implementation Status

Phased build (no GDD; catalog is the design source).

- **Phase 1 — Foundation ✅ (parse-verified):** `perk_group` field in `resources.json` (group-tagged
  goods are perk-eligible) + `ResourceRegistry.get_perk_eligible_ids_for_group(group)`;
  `PerkRegistry` (`src/systems/perks/perk_registry.gd`)
  with the 10 perk defs + `generate_choices(npc)` (profession-gated) + `building_type_name`;
  `NPCInstance` gains `profession`/`perks`/`pending_perk_choices`/`active_perks` + serialization;
  `grant_xp` queues one perk choice per level gained; `apply_perk_choice()`/`skip_perk_choice()` +
  pending-choice accessors.
- **Phase 2 — Level-up cards ✅ (parse-verified):** standalone `PerkChoicePanel`
  (`src/ui/perk_choice_panel.gd`, own CanvasLayer in `game.tscn`); Day Overview "next day" button
  gates on pending choices and opens the panel; 3 large cards, pick → `apply_perk_choice`, advance,
  resolve all before advancing.
- **Phase 3 — NPC detail UI ✅ (parse-verified):** "Perks & Versorgung" section in
  `npc_detail_panel.gd` — profession + each perk's bound good with live stock (green/red).
- **Phase 4 — Effect hooks (in progress):**
  - 4a ✅ daily perk-good consumption + per-day `active_perks` + XP effects (#2 Lernbegierig,
	#7 Lehrmeister, #11 Berufung) applied at the day-transition XP flush; generic query layer
	(`npc_perk_bonus`, `building_perk_bonus`, `building_has_active_perk`).
  - 4b ✅ #5 Packesel (carrier capacity, LogisticsSystem), #6 Ergiebig (output bonus) +
	#10 Geräumig (output buffer cap) + #8 Sparsam (every-4th-cycle input skip) in BuildingRegistry.
  - 4c ✅ #1 Genügsam (+nutrition in HungerSystem) + #9 Zäh (unfed floor clamp) + #3 Meisterhand
	(NPC eff cap via `extra_cap_bonus` folded into the nutrition curve in HungerSystem, 2026-06-18).
	Ordering relies on the autoload order (NPCSystem before HungerSystem) so `active_perks` is set
	first when the food modifier is computed.

**All 10 effect hooks wired** (#4 Werkstattoptimierung removed 2026-06-18 — see note below the
table). **Phase 5 (2026-07-01):** #12 Carrier calling added (`berufung_traeger` in PerkRegistry);
uses `PROFESSION_CARRIER = -2` sentinel; Carrier offered in first-level-up draw alongside building
professions; cart icon in PerkChoicePanel. Pending: full in-engine playtest verification.

## Accepted Perks

| # | Name | Effect | Magnitude | Hooks | Notes |
|---|------|--------|-----------|-------|-------|
| 1 | Genügsam (Frugal) | While supplied with the bound good, the NPC needs **2 less nutrition per day** to reach full efficiency. | Flat **−2** to the daily nutrition requirement (e.g. 5 → 3 for 100%). | Treat consumed nutrition as `+2` when feeding the efficiency curve (`efficiency_from_nutrition`), only while the bound good is supplied. | Trade: spend 1 unit/day of the bound good to cut food logistics. Value scales inversely with the bound good's cost. |
| 2 | Lernbegierig (Eager Learner) | While supplied with the bound good, the NPC gains **+25 % XP** (work cycles *and* deliveries). | **×1.25** XP multiplier. | At day-transition, multiply the NPC's accrued `pending_xp` by 1.25 (rounded) before applying, only while the bound good is supplied. | Global (not profession-scoped). A profession-bound higher-magnitude variant is parked for later, pending a "profession" definition. |
| 3 | Meisterhand (Master Hand) | While supplied with the bound good, **the NPC's own max efficiency cap** rises by **+20 %** (same channel as a level-up). | **+0.20** to `nutrition_bonus_cap`. | Pass +0.20 as `extra_cap_bonus` into the nutrition curve (`calculate_food_modifier`) while supplied. Like a level-up, this is a *cap*: the NPC must be fed more nutrition to actually reach the higher max. Speeds the building too (building cap is now 2.0 — see Removed #4). | Was "break 100 %" with #4; since the building cap was lifted globally, a single perk now suffices. |
| 5 | Packesel (Pack Mule) | While supplied with the bound good, the NPC's **carrier capacity is +1** (2 → 3 items per trip). | **+1** to `CARRIER_CAPACITY` for this NPC. | Per-NPC carrier-capacity override in LogisticsSystem, active while supplied. Inert for a non-carrier (production-only) NPC. | Logistics *throughput* lever, complements the travel-*speed* gain from efficiency perks. |
| 6 | Ergiebig (Bountiful) | While supplied with the bound good, the **randomly chosen production building** yields **+1 output per completed cycle**. | **+1** output per cycle. | On `production_output_ready` for the bound building, add +1 of its output to the buffer while the perked NPC is supplied. First **building-bound** perk: random good + random production **building type**; +1 applies to **all buildings of that type** while supplied. | Yield lever (amount, not speed). Building binding = **type** (decided). Strong with many buildings of the type — bound-good supply on one NPC is the gate. |
| 7 | Lehrmeister (Mentor) | While supplied with the bound good, the **other resident of the same house** gains **+25 % XP**. | **×1.25** XP for the housemate. | At day-transition, multiply the housemate's `pending_xp` by 1.25 while the mentor is supplied. Inert if the house has only one resident. | Social/spatial lever — introduces a housing-pairing decision. Distinct from #2 (self-XP). |
| 8 | Sparsam (Thrifty) | Building-bound. While the NPC is supplied, the bound building type runs **every 4th cycle with no input consumption** (≈ −25 % input demand). | Every **4th** cycle is input-free. | Per-building cycle counter; the 4th completed cycle skips input consumption. Bound-type pool restricted to **processing buildings that have inputs** (Sawmill, Tailor, Weaver, Tool Workshop). | Input/economy lever — eases upstream chains. Deterministic (counter, not chance). |
| 9 | Zäh (Hardy) | While supplied with the bound good, the NPC's **underfed efficiency floor rises from 25 % to 50 %**. | `NUTRITION_UNFED_EFFICIENCY` **0.25 → 0.5** for this NPC. | Raise this NPC's unfed floor in the nutrition curve while supplied. | Resilience lever — cushions food shortfalls. Distinct from #1: Genügsam lowers *need*, Zäh raises the *floor*. |
| 10 | Geräumig (Spacious) | Building-bound. While the NPC is supplied, the bound building type has **+50 % output buffer capacity** (e.g. 20 → 30). | `output_capacity` **×1.5** for that type. | Raise the building type's output buffer while supplied — it keeps producing longer before `OUTPUT_FULL` stalls it. | Stall-resilience lever — decouples production from pickup. Only matters when logistics is the bottleneck. |
| 11 | Berufung (Calling / Profession) | **Permanently** sets the NPC's profession to a production building type. While supplied with the bound good, **+25 % work-cycle XP** and **+10 % production speed** at that building type. | **×1.25** work XP (day-transition); **+10 %** to building efficiency multiplier (live, per tick). | Adds a permanent `profession` (building type); gates building-bound effect perks (#6/#8/#10); applies XP multiplier at day-transition; applies speed bonus via `EFFECT_CALLING_BUILDING_EFF` secondary effect → `_advance_production_cycle` multiplies computed efficiency by ×1.1 while supplied. | **Prerequisite** for building-bound perks. Good-bound, one per NPC, permanent. Stacks with #2/#7. Speed bonus stacks additively with further Callings on other NPCs. |
| 12 | Carrier (Calling / Carrier) | **Permanently** sets the NPC's profession to Carrier (sentinel `PROFESSION_CARRIER = -2`). While supplied with the bound good, **+25 % delivery XP** and **+1 carrier capacity** per trip. | **×1.25** delivery XP multiplier at day-transition; **+1** to carrier capacity (stacks with Pack Mule #5). | Stores `PROFESSION_CARRIER` in `npc.profession`; day-transition XP flush applies ×1.25; `EFFECT_CARRIER_CAPACITY` secondary effect picked up by `_carrier_capacity()` in LogisticsSystem. Building-bound effect perks (#6/#8/#10) remain locked. Icon: cart. Offered alongside building professions in the first-level-up Calling draw. | Not building-bound. Good-bound, one per NPC, permanent. Stacks with #2/#5/#7. |

> **#4 Werkstattoptimierung (Workshop Tuning) — REMOVED 2026-06-18.** It raised the
> building efficiency cap from 1.0 to 1.2. The building cap was lifted globally on
> 2026-06-18 (`BUILDING_EFFICIENCY_MAX = 2.0`), so any >100 % worker already speeds the
> building — the perk became redundant and was deleted. The catalog now has **10 perks**;
> remaining numbers are kept stable (no renumber) so existing references stay valid.

## Rejected / Parked

_(none yet)_

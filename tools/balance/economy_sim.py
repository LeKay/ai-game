#!/usr/bin/env python3
"""
From Scratch — Economy / Game-Loop Balancing Simulation
=======================================================

Standalone model of the *currently implemented* game systems (not the GDD intent).
All numbers were read directly from the GDScript source on 2026-06-11:

    src/systems/player_character.gd        manual actions, energy
    src/gameplay/crafting_registry.gd      tool recipe (the UI path)
    src/gameplay/building_registry.gd      build costs, production cycles
    src/systems/efficiency/efficiency_formulas.gd  F1-F6
    src/gameplay/hunger_system.gd          daily food consumption
    src/gameplay/npc_system.gd             carriers / workers / travel
    src/systems/logistics/logistics_system.gd  carrier FSM + travel ticks
    src/systems/tick_system.gd             TICKS_PER_DAY = 1440
    data/resources.json                    tool max_charge = 100

Purpose
-------
1. Make the realized production chain explicit and find its bottlenecks.
2. Quantify the "manual -> automated" pacing the game design is built around.
3. Show, with numbers, which balance changes produce a better game loop.

Run:  python tools/balance/economy_sim.py
      python tools/balance/economy_sim.py --proposed   (only the tuned config)

This file is an ANALYSIS tool. It does not touch game code. Treat the GDScript
source as the source of truth; if a formula here drifts from the code, fix here.
"""

from __future__ import annotations
import argparse
import sys

# Windows consoles default to cp1252; force UTF-8 so box-drawing chars render.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass
from dataclasses import dataclass, field, replace
from typing import Dict, List, Tuple

# ============================================================================
# CONFIG — every tunable number lives here. CURRENT mirrors the live code.
# ============================================================================

R = ("wood", "stone", "fiber", "berry", "tool")  # resource ids we track


@dataclass
class ManualAction:
    ticks: int
    energy: int
    output: float          # expected units per action
    resource: str          # "" = variable (forage)
    requires_tool: bool


@dataclass
class Building:
    name: str
    build_cost: Dict[str, int]      # materials to construct
    build_ticks: int
    cycle_ticks: int                # base cycle duration
    inputs: Dict[str, float]        # per cycle (tool counted in *tools*, see tool_charge)
    outputs: Dict[str, float]       # per cycle
    needs_worker: bool
    adjacency: bool                 # efficiency comes from adjacent terrain tiles (F6)


@dataclass
class Config:
    label: str

    # ---- time ----
    ticks_per_day: int = 1440
    ticks_per_second_base: float = 10.0   # at 1x speed

    # ---- energy ----
    energy_max: int = 100
    food_energy: Dict[str, int] = field(default_factory=lambda: {"berry": 10, "bread": 25})
    depletion_tick_mult: float = 2.0
    depletion_output_mult: float = 0.5

    # ---- manual actions (PlayerCharacter._action_configs) ----
    manual: Dict[str, ManualAction] = field(default_factory=lambda: {
        "forage":        ManualAction(50,  8, 1.0, "",      False),
        "pick_berries":  ManualAction(40,  5, 3.0, "berry", False),
        "chop_tree":     ManualAction(80, 12, 5.0, "wood",  True),
        "mine_stone":    ManualAction(60, 10, 3.0, "stone", True),
        "harvest_fiber": ManualAction(45,  6, 2.0, "fiber", False),
    })
    forage_table: Dict[str, float] = field(default_factory=lambda: {
        # equal 25% over 4 resource types (FORAGE_TABLE)
        "wood": 0.25, "stone": 0.25, "berry": 0.25, "fiber": 0.25,
    })

    # ---- tool crafting (CraftingRegistry.try_craft — the UI path) ----
    tool_recipe: Dict[str, int] = field(default_factory=lambda: {"wood": 2, "stone": 1, "fiber": 1})
    tool_recipe_energy: int = 15
    tool_recipe_ticks: int = 0            # instant in the UI path

    # ---- tool durability ----
    # How many production cycles ONE tool powers in a lumber camp / stone mason.
    # CODE REALITY: a delivered/loaded tool adds 1.0 charge, cycle cost 1.0  -> 1 cycle/tool.
    # DESIGN INTENT: tool max_charge 100, cycle cost 1.0                     -> 100 cycles/tool.
    tool_charge: float = 1.0

    # ---- efficiency wiring ----
    # CODE REALITY: F3/F4 are NOT called; cycle = base regardless of food/adjacency.
    apply_efficiency: bool = False
    # adjacency tiles assumed for adjacency buildings (1 tree neighbour -> eff 0.25)
    assumed_adjacency_tiles: int = 1
    # adjacency efficiency formula:  eff = clamp(base + per_tile * tiles, lo, hi)
    # CODE REALITY: base=0.0, per_tile=0.25, lo=0.0, hi=2.0  -> needs 4 tiles for full speed.
    adj_base: float = 0.0
    adj_per_tile: float = 0.25
    adj_lo: float = 0.0
    adj_hi: float = 2.0
    # are workers fed? (fed -> npc eff 1.0, unfed -> 0.5). Only matters if apply_efficiency.
    workers_fed: bool = True

    # ---- FOOD -> EFFICIENCY model (redesign 2026-06-11, v2: nutrition-driven) ----
    # Each food carries a NUTRITION value (data-driven, per resource). One generic curve
    # maps nutrition -> NPC efficiency. Foods are NOT special-cased; only their nutrition
    # number matters. 1 ration/NPC/day (not stackable) so density (bread) is the lever, not
    # quantity (berries). Tuned so: berry(1)->1.0, bread(3)->1.5, meat(5)->2.0, unfed(0)->0.25.
    food_state: str = "berry"                       # which food the workers eat
    # food_nutrition here = TOTAL nutrition consumed per day for that feeding scenario
    # (amount × per-item nutrition). 1 berry=1, 5 berries OR 1 bread=5, etc.
    food_nutrition: Dict[str, float] = field(default_factory=lambda: {
        "unfed": 0.0, "berry": 1.0, "fed": 5.0, "overfed": 10.0,
    })
    # curve (2026-06-12 v3):  eff = eff_unfed + min(per_unit × total_nutrition, max_bonus)
    # Linear then capped: 0→0.25, 5→1.0 (100%), >5→1.0. Food alone tops out at 100% (25% base
    # + 75% from nutrition); over-feeding gives nothing. 5 berries == 1 bread == 100%.
    eff_unfed: float = 0.25            # base efficiency at 0 nutrition (Z1)
    eff_per_nutrition: float = 0.15    # efficiency per nutrition point
    eff_nutrition_max_bonus: float = 0.75  # nutrition adds at most +0.75 → food caps at 1.0
    # Building efficiency cap (2026-06-12): buildings top out at 100% = base speed (mirrors
    # BUILDING_EFFICIENCY_MAX). Tunable; <1.0 only slows, never faster than base.
    building_eff_cap: float = 1.0
    # Decision: combine adjacency AND worker food on adjacency buildings (eff = adj * food).
    combine_adjacency_food: bool = False

    # ---- buildings (BuildingRegistry tables) ----
    buildings: Dict[str, Building] = field(default_factory=lambda: {
        "gathering_hut": Building("Gathering Hut", {"wood": 5, "stone": 2}, 80, 100,
                                   {}, {"berry": 3, "fiber": 2}, True, True),
        "lumber_camp":   Building("Lumber Camp",   {"wood": 15, "stone": 3}, 200, 100,
                                   {"tool": 1.0}, {"wood": 5}, True, True),
        "stone_mason":   Building("Stone Mason",   {"wood": 10, "stone": 5}, 200, 100,
                                   {"tool": 1.0}, {"stone": 5}, True, True),
        "tool_workshop": Building("Tool Workshop", {"wood": 10, "stone": 5}, 250, 150,
                                   {"wood": 2, "stone": 1, "fiber": 1}, {"tool": 1}, True, False),
    })

    # ---- logistics ----
    ticks_per_tile: float = 3.0
    carrier_capacity: int = 1
    # carrier NPC efficiency (food-driven, F4): effective travel = base / efficiency.
    carrier_efficiency: float = 1.0
    # whether every production building needs a dedicated input + output carrier NPC
    model_carriers: bool = True

    # ---- housing / population ----
    npcs_per_house: int = 2
    npc_spawn_interval: int = 1440        # ticks between 1st and 2nd NPC in a house

    # ---- food consumption (HungerSystem) ----
    food_per_npc_per_day: float = 1.0     # default assigned amount


def current_config() -> Config:
    return Config(label="CURRENT (live code)")


def realism_config() -> Config:
    """PROPOSED (3 changes assumed in) + a coherent TIME RESCALE for pacing/realism.

    Anchor: 1 tick ~ 1 minute, 1440 min/day. A day should hold a *believable* amount of
    work — a handful of production cycles, not ~14; construction takes hours-to-days, not
    seconds; crafting a tool takes time. Production cycles are scaled ~uniformly, so the
    ECONOMY STAYS BALANCED (net-flow ratios are preserved) — it just breathes at a human pace.
    """
    c = proposed_config()
    c.label = "REALISM (time-rescaled)"

    # Tool crafting is no longer instant (1.5 h of work).
    c.tool_recipe_ticks = 90

    # Production: ~5-6 cycles/day for a basic producer (cycle x2.5). Construction:
    # half a day (hut) up to ~2 days (workshop) — the big realism fix (was seconds).
    c.buildings = {
        #                                build  cycle  inputs                     outputs
        "gathering_hut": Building("Gathering Hut", {"wood": 5, "stone": 2},  640, 250,
                                   {}, {"berry": 4, "fiber": 2}, True, True),
        "lumber_camp":   Building("Lumber Camp",   {"wood": 15, "stone": 3}, 1600, 250,
                                   {"tool": 1.0}, {"wood": 5}, True, True),
        "stone_mason":   Building("Stone Mason",   {"wood": 10, "stone": 5}, 1600, 250,
                                   {"tool": 1.0}, {"stone": 5}, True, True),
        "tool_workshop": Building("Tool Workshop", {"wood": 10, "stone": 5}, 3000, 375,
                                   {"wood": 2, "stone": 1, "fiber": 1}, {"tool": 1}, True, False),
    }
    return c


def proposed_config() -> Config:
    """A tuned config — rationale is in the printed report and the .md writeup."""
    c = Config(label="PROPOSED (tuned)")

    # (1) TOOLS = CAPITAL, NOT FUEL.
    # Realize tool durability so one tool powers many cycles (wire the tool's charge
    # through the carrier/manual-load path, or set charge in the table). This turns the
    # tool workshop from a treadmill into a small, occasional investment.
    c.tool_charge = 30.0

    # (2) WIRE EFFICIENCY (F3/F4) so food + placement finally matter...
    c.apply_efficiency = True
    # Adjacency curve (2026-06-12: softened to +10%/tile, higher base): base 0.7 + 0.10/tile,
    #   1 tile -> 0.80, 2 -> 0.90, 3+ -> 1.00 (capped). Resource tiles are a gentle modifier now.
    c.adj_base = 0.7
    c.adj_per_tile = 0.10
    c.adj_lo = 0.5
    c.adj_hi = 1.0
    c.assumed_adjacency_tiles = 3          # a normal placement that reaches 100%
    c.workers_fed = True
    # Food -> efficiency redesign: combine adjacency AND food. Steady-state assumes workers
    # are fed to baseline (5 nutrition = 100%; e.g. 5 berries/day or 1 bread/day).
    c.combine_adjacency_food = True
    c.food_state = "fed"

    # (3) CARRIERS: shared pool (1 carrier serves many routes) collapses the NPC overhead.
    # Capacity 2 (2026-06-12) so one carrier keeps pace with one producer at typical distances
    # (capacity 1 made the carrier the binding bottleneck and stalled buildings). Still an
    # upgradeable per-carrier stat. Map shows a "×N" badge on the carrier when hauling >1.
    c.carrier_capacity = 2

    # (5) TRANSPORT SPEED: base 5 ticks/tile = travel at 100% carrier efficiency. F4 then divides
    # by carrier food-efficiency, so 50% = 10/tile (the anchored "current" value), 25% = 20/tile.
    # Faster carriers (better fed) traverse quicker; distance + feeding both matter.
    c.ticks_per_tile = 5.0

    # (4) Mild building retune around the new tool economy. Outputs nudged up so a
    # single fed+placed producer is satisfying; gathering hut yields a touch more food.
    c.buildings = {
        "gathering_hut": Building("Gathering Hut", {"wood": 5, "stone": 2}, 80, 100,
                                   {}, {"berry": 4, "fiber": 2}, True, True),
        "lumber_camp":   Building("Lumber Camp",   {"wood": 15, "stone": 3}, 200, 100,
                                   {"tool": 1.0}, {"wood": 5}, True, True),
        "stone_mason":   Building("Stone Mason",   {"wood": 10, "stone": 5}, 200, 100,
                                   {"tool": 1.0}, {"stone": 5}, True, True),
        "tool_workshop": Building("Tool Workshop", {"wood": 10, "stone": 5}, 250, 150,
                                   {"wood": 2, "stone": 1, "fiber": 1}, {"tool": 1}, True, False),
    }
    return c


# ============================================================================
# HELPERS
# ============================================================================

def fmt(x: float, w: int = 8, p: int = 2) -> str:
    return f"{x:>{w}.{p}f}"


def rule(ch: str = "─", n: int = 78) -> str:
    return ch * n


def header(title: str) -> str:
    return f"\n{rule('═')}\n  {title}\n{rule('═')}"


def nutrition_to_efficiency(cfg: Config, n: float) -> float:
    """Generic, data-driven curve: food nutrition -> NPC efficiency."""
    bonus = min(cfg.eff_per_nutrition * max(0.0, n), cfg.eff_nutrition_max_bonus)
    return cfg.eff_unfed + bonus


def worker_food_factor(cfg: Config, b: Building) -> float:
    """NPC efficiency from the NUTRITION of the food the workers eat (redesigned F1/F5)."""
    if not b.needs_worker:
        return 1.0
    n = cfg.food_nutrition.get(cfg.food_state, 0.0)
    return nutrition_to_efficiency(cfg, n)


def building_efficiency(cfg: Config, b: Building) -> float:
    """Mirror BuildingInstance.recalculate_efficiency + EfficiencyFormulas (+ redesign)."""
    if not cfg.apply_efficiency:
        return 1.0  # F3 not wired -> efficiency never divides the cycle
    wf = worker_food_factor(cfg, b)
    cap = cfg.building_eff_cap   # buildings capped at 100% (2026-06-12); never faster than base
    if b.adjacency:
        adj = cfg.adj_base + cfg.adj_per_tile * cfg.assumed_adjacency_tiles  # F6 (parameterised)
        adj = max(cfg.adj_lo, min(cfg.adj_hi, adj))
        if cfg.combine_adjacency_food:
            return max(0.0, min(cap, adj * wf))   # Decision: layout AND food both count
        return min(cap, adj)                      # legacy: gatherers ignore food
    # non-adjacency building (Tool Workshop etc.): worker food drives it (F2 identity)
    return max(0.0, min(cap, wf))


def effective_cycle(cfg: Config, b: Building) -> float:
    eff = building_efficiency(cfg, b)
    if eff <= 0:
        return float("inf")
    return b.cycle_ticks / eff  # F3 when wired; identity when eff==1


def per_tick_rates(cfg: Config, b: Building) -> Tuple[Dict[str, float], Dict[str, float]]:
    """Returns (inputs_per_tick, outputs_per_tick) for one operating building."""
    ct = effective_cycle(cfg, b)
    if ct == float("inf"):
        return ({}, {})
    ins, outs = {}, {}
    for r, q in b.inputs.items():
        if r == "tool":
            # tool consumed per cycle = q / tool_charge  (q is "tools" needed at full charge)
            ins[r] = (q / cfg.tool_charge) / ct
        else:
            ins[r] = q / ct
    for r, q in b.outputs.items():
        outs[r] = q / ct
    return ins, outs


# ============================================================================
# PART 1 — Manual action economics
# ============================================================================

def part1_manual(cfg: Config) -> None:
    print(header(f"PART 1 — Manual actions  [{cfg.label}]"))
    print("Action          ticks  energy   out  resource   units/1000t   energy/unit")
    print(rule())
    for name, a in cfg.manual.items():
        rate = a.output / a.ticks * 1000
        epu = a.energy / a.output if a.output else 0
        tool = " (needs tool)" if a.requires_tool else ""
        print(f"{name:<14}{a.ticks:>6}{a.energy:>8}{a.output:>6}  {a.resource or 'random':<9}"
              f"{fmt(rate,12,1)}{fmt(epu,14)}{tool}")
    print(rule())

    # Energy verdict: berries are wildly net-positive.
    pb = cfg.manual["pick_berries"]
    berry_e = cfg.food_energy["berry"]
    net = pb.output * berry_e - pb.energy
    print(f"\nEnergy reality check:")
    print(f"  pick_berries: spend {pb.energy} energy -> {pb.output:.0f} berries "
          f"-> eat for {pb.output*berry_e:.0f} energy  =>  NET +{net:.0f} energy/action.")
    print(f"  Energy is therefore self-solving: any berry tile makes energy a non-constraint.")
    print(f"  => The energy/depletion 'strategic choice' the GDD promises does not bite.")


# ============================================================================
# PART 2 — Bootstrap: time from bare hands to first automation
# ============================================================================

def part2_bootstrap(cfg: Config) -> None:
    print(header(f"PART 2 — Bootstrap to first automation  [{cfg.label}]"))
    print("Goal: gather by hand -> craft 1st tool -> build Gathering Hut + House -> assign NPC.")
    print("(Gathering Hut needs NO tool, so it is the cheapest first automation.)\n")

    ft = cfg.forage_table
    # First tool needs 2 wood + 1 stone (+1 fiber via harvest_fiber, cheap & deterministic).
    # Pre-tool, wood & stone come ONLY from forage (random 25% each).
    need_wood, need_stone = cfg.tool_recipe["wood"], cfg.tool_recipe["stone"]
    # Expected forages dominated by the rarer-of-needs requirement.
    e_forage_wood = need_wood / ft["wood"]
    e_forage_stone = need_stone / ft["stone"]
    e_forages = max(e_forage_wood, e_forage_stone)
    forage = cfg.manual["forage"]
    t_tool_mats = e_forages * forage.ticks
    print(f"  Pre-tool wood/stone source: forage only (25% each).")
    print(f"  Expected forages for {need_wood} wood: {e_forage_wood:.0f}; "
          f"for {need_stone} stone: {e_forage_stone:.0f}  -> ~{e_forages:.0f} forages.")
    print(f"  Ticks to first tool's materials: ~{t_tool_mats:.0f}  ({t_tool_mats/cfg.ticks_per_day:.2f} days)")

    # After tool: gather hut + house = 15W + 5S total (5+2 + 10+3). Net of the 2W+1S spent on tool.
    hut = cfg.buildings["gathering_hut"].build_cost
    house = {"wood": 10, "stone": 3}
    total_w = hut["wood"] + house["wood"]
    total_s = hut["stone"] + house["stone"]
    # surplus from forage run (got ~e_forages items: 25% each)
    surplus_w = e_forages * ft["wood"] - need_wood
    surplus_s = e_forages * ft["stone"] - need_stone
    rem_w = max(0, total_w - surplus_w)
    rem_s = max(0, total_s - surplus_s)
    chop = cfg.manual["chop_tree"]
    mine = cfg.manual["mine_stone"]
    t_wood = rem_w / chop.output * chop.ticks
    t_stone = rem_s / mine.output * mine.ticks
    print(f"\n  Buildings: Gathering Hut ({hut['wood']}W+{hut['stone']}S) + "
          f"House ({house['wood']}W+{house['stone']}S) = {total_w}W + {total_s}S")
    print(f"  With tool: chop_tree {chop.output:.0f}W/{chop.ticks}t, mine_stone {mine.output:.0f}S/{mine.ticks}t")
    print(f"  Remaining to gather: {rem_w:.0f}W (~{t_wood:.0f}t) + {rem_s:.0f}S (~{t_stone:.0f}t)")
    house_build = 1200 if cfg.buildings["gathering_hut"].build_ticks > 300 else 150
    t_build = cfg.buildings["gathering_hut"].build_ticks + house_build  # hut + house build
    total = t_tool_mats + cfg.tool_recipe_ticks + t_wood + t_stone + t_build
    print(f"  Build time (hut {cfg.buildings['gathering_hut'].build_ticks}t + house {house_build}t): {t_build}t")
    print(rule())
    print(f"  TOTAL time-to-first-automation: ~{total:.0f} ticks "
          f"= {total/cfg.ticks_per_day:.2f} in-game days")
    print(f"  At 1x ({cfg.ticks_per_second_base:.0f} ticks/s): "
          f"~{total/cfg.ticks_per_second_base/60:.1f} min of active play (more with menu time).")


# ============================================================================
# PART 3 — Steady-state production-chain equilibrium + bottleneck finder
# ============================================================================

def part3_steady_state(cfg: Config, counts: Dict[str, int]) -> Dict[str, float]:
    print(header(f"PART 3 — Steady-state flow  [{cfg.label}]"))
    print("Village: " + ", ".join(f"{n}x {cfg.buildings[k].name}" for k, n in counts.items() if n))
    print()
    net: Dict[str, float] = {r: 0.0 for r in R}
    print("Building          eff   cyc(t)   per-cycle in -> out             contribution/1000t")
    print(rule())
    for key, n in counts.items():
        if not n:
            continue
        b = cfg.buildings[key]
        eff = building_efficiency(cfg, b)
        ct = effective_cycle(cfg, b)
        ins, outs = per_tick_rates(cfg, b)
        for r, v in ins.items():
            net[r] -= v * n
        for r, v in outs.items():
            net[r] += v * n
        in_s = "+".join(f"{q:g}{r[:1]}" for r, q in b.inputs.items()) or "—"
        out_s = "+".join(f"{q:g}{r[:1]}" for r, q in b.outputs.items())
        contrib = []
        for r in R:
            d = (outs.get(r, 0) - ins.get(r, 0)) * n * 1000
            if abs(d) > 1e-9:
                contrib.append(f"{r}:{d:+.1f}")
        print(f"{b.name:<16}{fmt(eff,5,2)}{ct:>9.0f}   {in_s:<8}->{out_s:<8}    "
              f"{('  '.join(contrib)):<30}")
    print(rule())
    print("NET per 1000 ticks (≈0.69 days):")
    for r in R:
        v = net[r] * 1000
        flag = ""
        if v < -1e-6:
            flag = "  <-- DEFICIT (chain starves)"
        elif abs(v) < 1e-6:
            flag = "  (balanced)"
        print(f"   {r:<7}{fmt(v,10,2)} /1000t{flag}")
    # per day
    print("NET per day (1440t):")
    for r in R:
        print(f"   {r:<7}{fmt(net[r]*cfg.ticks_per_day,10,2)} /day")
    return net


# ============================================================================
# PART 4 — NPC & carrier budget (the real expansion constraint)
# ============================================================================

def part4_npc_budget(cfg: Config, counts: Dict[str, int], houses: int,
                     avg_route_tiles: int) -> None:
    print(header(f"PART 4 — NPC / carrier budget  [{cfg.label}]"))
    workers = 0
    out_carriers = 0
    in_carriers = 0
    for key, n in counts.items():
        if not n:
            continue
        b = cfg.buildings[key]
        if b.needs_worker:
            workers += n
        if cfg.model_carriers:
            # every producing building needs an output carrier to move goods to storage
            if b.outputs:
                out_carriers += n
            # one input carrier per distinct non-trivial input resource
            in_carriers += n * len(b.inputs)
    total_npc = workers + out_carriers + in_carriers
    cap = houses * cfg.npcs_per_house
    print(f"  Workers (1 per building):            {workers}")
    print(f"  Output carriers (1 per producer):    {out_carriers}")
    print(f"  Input carriers (1 per input slot):   {in_carriers}")
    print(rule())
    print(f"  TOTAL NPCs required:                 {total_npc}")
    print(f"  Housing available ({houses} houses x {cfg.npcs_per_house}): {cap}")
    short = total_npc - cap
    if short > 0:
        print(f"  >>> SHORT BY {short} NPCs — need {(-(-short//cfg.npcs_per_house))} more house(s).")
    else:
        print(f"  >>> OK ({cap-total_npc} spare).")

    # carrier throughput check on a representative output route
    rt = 2 * avg_route_tiles * cfg.ticks_per_tile  # round trip, ignoring wait/deposit
    cps = cfg.carrier_capacity / rt if rt else 0
    print(f"\n  Carrier throughput @ {avg_route_tiles} tiles: round trip {rt:.0f}t "
          f"-> {cps*1000:.2f} items/1000t per carrier (capacity {cfg.carrier_capacity}).")
    # compare to a lumber camp output rate
    lc = cfg.buildings["lumber_camp"]
    _, outs = per_tick_rates(cfg, lc)
    lc_rate = outs.get("wood", 0) * 1000
    print(f"  Lumber camp emits {lc_rate:.2f} wood/1000t; one carrier moves {cps*1000:.2f}/1000t.")
    if cps * 1000 < lc_rate:
        print(f"  >>> Carrier CANNOT keep up at this distance — output buffer backs up,")
        print(f"      building STALLS when buffer (20) fills. Distance is a hard throttle.")
    else:
        print(f"  >>> One carrier keeps up.")


# ============================================================================
# PART 5 — Knob sensitivity: tool_charge is the dominant lever
# ============================================================================

def part5_sensitivity(cfg: Config) -> None:
    print(header(f"PART 5 — Sensitivity: tool_charge sweep  [{cfg.label}]"))
    print("How many tool workshops are needed to keep ONE lumber camp at full speed,")
    print("and the net wood after the chain pays for its own tools.\n")
    lc = cfg.buildings["lumber_camp"]
    tw = cfg.buildings["tool_workshop"]
    print(" tool_charge   tools/1000t needed   workshops/lumbercamp   net wood/1000t*")
    print(rule())
    for tc in (1, 2, 5, 10, 20, 40, 100):
        test = replace(cfg, tool_charge=float(tc))
        lc_in, lc_out = per_tick_rates(test, lc)
        tw_in, tw_out = per_tick_rates(test, tw)
        tools_needed = lc_in.get("tool", 0) * 1000
        tw_tool_rate = tw_out.get("tool", 0) * 1000
        workshops = tools_needed / tw_tool_rate if tw_tool_rate else 0
        # net wood = lumber output - wood the needed workshops consume
        wood_out = lc_out.get("wood", 0) * 1000
        wood_in_workshops = workshops * tw_in.get("wood", 0) * 1000
        net_wood = wood_out - wood_in_workshops
        print(f"{tc:>10}   {fmt(tools_needed,16,3)}   {fmt(workshops,20,2)}   {fmt(net_wood,14,2)}")
    print(rule())
    print(" *net wood after the tool workshops feeding this lumber camp take their wood cut.")
    print(" tool_charge=1 (current) => tools are a brutal tax; the chain barely nets wood and")
    print(" demands ~1.5 workshops (each w/ its own NPC) per lumber camp. Higher charge =")
    print(" tools become capital, the loop breathes, NPCs free up for expansion.")


# ============================================================================
# PART 6 — Food->efficiency optimisation, food sustainability, shared carriers
# ============================================================================

def total_item_flow(cfg: Config, counts: Dict[str, int]) -> float:
    """Items per 1000t that must be carried (all outputs to storage + all inputs from storage)."""
    flow = 0.0
    for key, n in counts.items():
        if not n:
            continue
        b = cfg.buildings[key]
        ins, outs = per_tick_rates(cfg, b)
        flow += sum(outs.values()) * 1000 * n
        flow += sum(ins.values()) * 1000 * n
    return flow


def village_wood_rate(cfg: Config, counts: Dict[str, int]) -> float:
    b = cfg.buildings["lumber_camp"]
    _, outs = per_tick_rates(cfg, b)
    return outs.get("wood", 0) * 1000 * counts.get("lumber_camp", 0)


def part6_food_and_carriers(cfg: Config, counts: Dict[str, int], avg_route_tiles: int) -> None:
    print(header(f"PART 6 — Food tiers, sustainability & shared carriers  [{cfg.label}]"))

    if not cfg.apply_efficiency:
        print("  (efficiency not wired in this config -> food has NO effect; see CURRENT findings)")
        return

    # (a) Food tier optimisation: lumber camp throughput per food state.
    print("  Nutrition -> Lumber Camp throughput (adj=%d tiles, combine=%s):"
          % (cfg.assumed_adjacency_tiles, cfg.combine_adjacency_food))
    print("   scenario     totalNutr   npc_eff   bld_eff   cycle(t)   wood/1000t   vs fed(100%)")
    print("  " + rule("-", 78))
    base = None
    for fs in ("unfed", "berry", "fed", "overfed"):
        test = replace(cfg, food_state=fs)
        b = test.buildings["lumber_camp"]
        n = test.food_nutrition.get(fs, 0.0)
        npc_eff = nutrition_to_efficiency(test, n)
        bld = building_efficiency(test, b)
        ct = effective_cycle(test, b)
        _, outs = per_tick_rates(test, b)
        wr = outs.get("wood", 0) * 1000
        if fs == "fed":
            base = wr
        vs = f"{wr/base*100:5.0f}%" if base else "  —"
        print(f"   {fs:<12}{fmt(n,9,1)}{fmt(npc_eff,11,2)}{fmt(bld,9,2)}{ct:>11.0f}"
              f"{fmt(wr,13,1)}     {vs}")
    print("  " + rule("-", 78))
    print("  => Efficiency depends on TOTAL nutrition consumed (amount × food nutrition).")
    print("     5 berries == 1 bread == 5 nutrition == 100%. Bread = same effect, 1/5 the items.")
    print("     1 berry alone = 40%; over-feeding (>5) stays 100% (food caps there); unfed = 25%.\n")

    # (b) Food sustainability: how many NPCs does one gathering hut feed?
    gh = cfg.buildings["gathering_hut"]
    _, gh_out = per_tick_rates(cfg, gh)
    berry_per_day = gh_out.get("berry", 0) * cfg.ticks_per_day
    npcs_full = berry_per_day / 5.0   # 5 berries/day -> 100%
    npcs_min = berry_per_day / 1.0    # 1 berry/day  -> 40%
    print(f"  Food sustainability: 1 Gathering Hut -> {berry_per_day:.0f} berries/day")
    print(f"   -> feeds ~{npcs_full:.0f} NPCs at 100% (5 berries each) OR ~{npcs_min:.0f} at 40% (1 each).")
    print(f"   => berries are BULKY (need 5/NPC for 100%); bread (5 nutrition/item) does it with")
    print(f"      1 item — so the bread chain mainly buys LOGISTICS relief, at equal efficiency.\n")

    # (c) Shared carrier pool budget vs the old per-route model.
    workers = sum(n for k, n in counts.items() if cfg.buildings[k].needs_worker)
    flow = total_item_flow(cfg, counts)
    rt = 2 * avg_route_tiles * cfg.ticks_per_tile
    per_carrier = cfg.carrier_capacity / rt * 1000 if rt else 0
    carriers = -(-int(flow) // max(1, int(per_carrier))) if per_carrier else 0
    carriers = max(1, (int(flow) + int(per_carrier) - 1) // int(per_carrier)) if per_carrier else 0
    total = workers + carriers
    print(f"  Shared carrier pool (Z4): total item flow {flow:.0f}/1000t, "
          f"carrier moves {per_carrier:.0f}/1000t @ {avg_route_tiles} tiles.")
    print(f"   Workers {workers} + shared carriers {carriers} = {total} NPCs "
          f"({-(-total//cfg.npcs_per_house)} houses).")
    print(f"   vs per-route model = 13 NPCs. => expansion driven by layout/food, not carrier admin.")


# ============================================================================
# PART 7 — Realism / per-day pacing
# ============================================================================

def part7_pacing(cfg: Config, counts: Dict[str, int]) -> None:
    print(header(f"PART 7 — Per-day pacing  [{cfg.label}]"))
    d = cfg.ticks_per_day
    print(f"Day = {d} ticks  (anchor: 1 tick ~ 1 minute => a day of work).\n")
    print("Building          cycle(t)  cycles/day   output/day              build(t)  build(days)")
    print(rule())
    for key, n in counts.items():
        b = cfg.buildings[key]
        ct = effective_cycle(cfg, b)
        cpd = d / ct if ct else 0
        outs = "  ".join(f"{q*cpd:.1f} {r}" for r, q in b.outputs.items()) or "—"
        bdays = b.build_ticks / d
        print(f"{b.name:<16}{ct:>9.0f}{cpd:>12.1f}   {outs:<22}{b.build_ticks:>9}{bdays:>11.2f}")
    print(rule())
    # tool craft
    print(f"Tool craft: {cfg.tool_recipe['wood']}W+{cfg.tool_recipe['stone']}S+{cfg.tool_recipe['fiber']}F"
          f", {cfg.tool_recipe_ticks} ticks ({cfg.tool_recipe_ticks/60:.1f} h)"
          + ("  <-- was instant" if cfg.tool_recipe_ticks > 0 else "  (instant)"))
    # food cadence
    gh = cfg.buildings["gathering_hut"]
    _, gh_out = per_tick_rates(cfg, gh)
    npcs_fed = gh_out.get("berry", 0) * d / cfg.food_per_npc_per_day
    print(f"1 Gathering Hut feeds ~{npcs_fed:.0f} NPCs/day (vs ~58 in the fast config).")
    print("\nReality check: a basic producer now does ~5-6 cycles/day (was ~14);")
    print("a house takes ~1 day to build (was ~0.1); a workshop ~2 days. The in-game DAY")
    print("becomes a meaningful planning unit instead of a blur.")


# ============================================================================
# PART 8 — Transport speed (ticks/tile) + F4 efficiency scaling
# ============================================================================

def part8_transport(cfg: Config, dist: int) -> None:
    print(header(f"PART 8 — Transport pacing  [{cfg.label}]"))
    lc = cfg.buildings["lumber_camp"]
    _, outs = per_tick_rates(cfg, lc)
    bld_rate = outs.get("wood", 0) * 1000  # items the building emits per 1000t
    cyc = effective_cycle(cfg, lc)
    print(f"Reference: 1 Lumber Camp emits {bld_rate:.1f} items/1000t (cycle {cyc:.0f}t), "
          f"carrier capacity {cfg.carrier_capacity}.")
    print(f"How fast can ONE FED carrier (eff 1.0) clear it, and how far can it range?\n")
    print(" t/tile   roundtrip@%-2dt   items/1000t   builds/carrier   max dist to keep 1 builder"
          % dist)
    print(rule())
    for tpt in (3, 5, 8, 10, 12, 15):
        rt = 2 * dist * tpt
        per = cfg.carrier_capacity / rt * 1000 if rt else 0
        builds = per / bld_rate if bld_rate else 0
        # max distance d where roundtrip 2*d*tpt <= cycle (carrier keeps pace w/ 1 builder)
        max_d = cyc / (2 * tpt) if tpt else 0
        mark = "   <-- chosen" if abs(tpt - cfg.ticks_per_tile) < 0.01 else ""
        print(f"{tpt:>6}{rt:>14}{fmt(per,14,1)}{fmt(builds,17,2)}{max_d:>18.0f} tiles{mark}")
    print(rule())
    print("F4 scaling (chosen t/tile=%g, %d tiles): travel = base / carrier_efficiency."
          % (cfg.ticks_per_tile, dist))
    base_rt = 2 * dist * cfg.ticks_per_tile
    for fs, eff in (("unfed", 0.25), ("half-fed (anchor)", 0.5), ("fed", 1.0)):
        print(f"   {fs:<10} eff {eff:>4}: roundtrip {base_rt/eff:>6.0f}t   "
              f"({(base_rt/eff)/cfg.ticks_per_day:.2f} day)")
    print("   => 50% efficiency = the anchored 10/tile; fed carriers (100%) haul 2× faster.")


# ============================================================================
# DRIVER
# ============================================================================

def run(cfg: Config) -> None:
    part1_manual(cfg)
    part2_bootstrap(cfg)
    # A representative "early automated village":
    counts = {"gathering_hut": 1, "lumber_camp": 1, "stone_mason": 1, "tool_workshop": 1}
    part3_steady_state(cfg, counts)
    part4_npc_budget(cfg, counts, houses=2, avg_route_tiles=8)
    part5_sensitivity(cfg)
    part6_food_and_carriers(cfg, counts, avg_route_tiles=8)
    part7_pacing(cfg, counts)
    part8_transport(cfg, dist=8)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--proposed", action="store_true", help="only run the tuned config")
    ap.add_argument("--current", action="store_true", help="only run the live-code config")
    ap.add_argument("--realism", action="store_true", help="only run the time-rescaled config")
    args = ap.parse_args()

    if args.realism:
        run(realism_config())
    elif args.proposed:
        run(proposed_config())
    elif args.current:
        run(current_config())
    else:
        run(current_config())
        print("\n\n" + "#" * 78)
        print("#  Re-running with the PROPOSED tuning for side-by-side comparison")
        print("#" * 78)
        run(proposed_config())


if __name__ == "__main__":
    main()

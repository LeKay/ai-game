# Epic: Save/Load System

> **Layer**: Persistence
> **GDD**: None — design governed by ADR-0006
> **Architecture Module**: WorldSaveManager
> **Status**: Ready
> **Stories**: 3 stories created

## Overview

The Save/Load System provides game persistence through a JSON file format with schema versioning, orchestrated by a `WorldSaveManager` Autoload that enforces a deterministic load-order invariant. Each system implements `serialize() -> Dictionary` and `deserialize(Dictionary) -> void` with the orchestrator collecting and writing the merged data. Save slots use platform-specific `user://` paths with atomic writes (write-to-tmp-then-rename) and companion metadata files for fast save listing. Corrupted saves never crash the game — they show error dialogs and allow fallback to other slots.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0006: Save and Load Format and Serialization Order | WorldSaveManager orchestrator, JSON format, schema versioning, deterministic load order, atomic writes | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-sv-001 | JSON data registry at res://data/resources.json loaded at startup | ADR-0006 ✅ |
| TR-sv-002 | Schema validation on load with fail-fast: invalid data halts loading | ADR-0006 ✅ |
| TR-sv-??? | WorldSaveManager orchestrator — collect serialize() dicts, merge, write JSON | ADR-0006 ✅ *(TR-ID TBD)* |
| TR-sv-??? | Deterministic load order: ResourceRegistry → GridMap → Inventory → Buildings → NPCs → Hunger → Player → Tick | ADR-0006 ✅ *(TR-ID TBD)* |
| TR-sv-??? | Save slots: at least 3 concurrent save slots (default 10) | ADR-0006 ✅ *(TR-ID TBD)* |
| TR-sv-??? | Schema versioning — reject future versions, handle missing fields in older versions | ADR-0006 ✅ *(TR-ID TBD)* |
| TR-sv-??? | Atomic writes — write to .tmp, then rename | ADR-0006 ✅ *(TR-ID TBD)* |
| TR-sv-??? | Error handling — corrupted save = error dialog, no crash | ADR-0006 ✅ *(TR-ID TBD)* |

> ⚠️ **No GDD exists** for save-load-system. TR-IDs are reserved but numbers TBD when a GDD is written. All requirements above are traced to ADR-0006.

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from ADR-0006 are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | WorldSaveManager Orchestrator | Logic | Ready | ADR-0006 |
| 002 | Save Slot Management and Metadata | Logic | Ready | ADR-0006 |
| 003 | Schema Versioning and Error Handling | Logic | Ready | ADR-0006 |

## Next Step

Run `/story-readiness production/epics/save-load-system/story-001-world-save-manager.md` to begin implementation.

# Epic: Resource System

> **Epic Slug**: resource-system
> **Layer**: Foundation
> **System**: Resource Data Registry
> **GDD**: `design/gdd/resource-system.md`
> **Governing ADR**: `docs/architecture/adr-0002-resource-data-registry.md`

## Overview

Implement the centralized data registry that defines all collectable and tradeable resources. ResourceRegistry is an Autoload singleton that loads `res://data/resources.json` at startup, validates the schema, caches definitions in a Dictionary for O(1) lookup, and exposes read-only query methods. All gameplay systems (Inventory, Production, Hunger, Trading, HUD, Building) reference this registry rather than hardcoding resource types.

## Governing ADRs

| ADR | Title | Status |
|-----|-------|--------|
| ADR-0002 | Resource Data Registry Format and Loading | Accepted |

## GDD Requirements Table

| TR-ID | Requirement | Status |
|-------|-------------|--------|
| TR-res-001 | JSON data registry at res://data/resources.json loaded at startup | Covered by ADR-0002 |
| TR-res-002 | Resource definition: id, display_name, category, stack_limit, icon_path (required); optional fields | Covered by ADR-0002 |
| TR-res-003 | Schema validation on load with fail-fast: invalid data halts loading | Covered by ADR-0002 |
| TR-res-004 | O(1) id-keyed runtime lookup via Dictionary[StringName, ResourceDefinition] | Covered by ADR-0002 |
| TR-res-005 | Two categories: Consumables / Production Goods | Covered by ADR-0002 |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [JSON File Loading and Registry Schema](story-001-json-loading-and-schema.md) | Logic | Ready | ADR-0002 |
| 002 | [Schema Validation and Fail-Fast](story-002-schema-validation.md) | Logic | Ready | ADR-0002 |
| 003 | [Dictionary Cache and O(1) Lookup API](story-003-lookup-api.md) | Logic | Ready | ADR-0002 |
| 004 | [Category System and Filtering](story-004-category-filtering.md) | Logic | Ready | ADR-0002 |
| 005 | [Version Migration and Deprecated Resources](story-005-version-migration-and-deprecated.md) | Integration | Ready | ADR-0002, ADR-0006 |

## Dependencies

- **Depends on**: None (Foundation layer — lowest infrastructure)
- **Unlocks**: Inventory System, Building System, Production System, Hunger System, Trading System, HUD System, NPC System — all reference ResourceRegistry

## Risks

- **Engine**: HIGH — FileAccess.open() returns FileAccess object (null on failure) in 4.4+, NOT a bool. Must null-check.
- **Verification**: Test JSON parsing performance with 100+ entries; verify error handling on missing/malformed files

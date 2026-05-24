# Epic: Grid/Map System

> **Layer**: Core
> **GDD**: design/gdd/grid-map-system.md
> **Architecture Module**: GridMap
> **Status**: Ready
> **Stories**: 6 stories created

## Overview

The Grid/Map System is the spatial foundation of the game world — a procedurally generated tile grid that serves as the canvas for all gameplay. It generates a 30×30 tile world using Perlin noise-based algorithms that place resource nodes in natural clusters. The grid uses a 3-layer data model (TerrainLayer, ResourceLayer, BuildingLayer) with independent mutability rules. All placement validation flows through a single `validate_placement` gate. Coordinate conversion bridges tile-space logic and pixel-space rendering for input and camera systems.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0004 | 30×30 3-layer data model, TileMapLayer rendering (not TileMap), FastNoise Perlin generation, single validate_placement gate, Manhattan+Euclidean distance functions | HIGH |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-grid-001 | 30×30 tile grid, 3-layer data model: TerrainLayer (write-once), ResourceLayer (mutable), BuildingLayer (mutable) | ADR-0004 ✅ |
| TR-grid-002 | TileMapLayer rendering (TileMap is deprecated since 4.3 and must not be used) | ADR-0004 ✅ |
| TR-grid-003 | Perlin noise procedural terrain generation at world init with deterministic seed | ADR-0004 ✅ |
| TR-grid-004 | Single validate_placement gate checks all 3 layers before any building placement | ADR-0004 ✅ |
| TR-grid-005 | Manhattan and Euclidean distance functions exposed as grid API | ADR-0004 ✅ |
| TR-grid-006 | World-space to tile-coordinate and tile-coordinate to world-space conversion | ADR-0004 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/grid-map-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Grid Data Model and Core Read API | Logic | Ready | ADR-0004 |
| 002 | Procedural Generation Pipeline | Logic | Ready | ADR-0004 |
| 003 | Building Placement Validation Gate | Logic | Ready | ADR-0004 |
| 004 | Coordinate Conversion | Logic | Ready | ADR-0004 |
| 005 | Distance Functions and Spatial Queries | Logic | Ready | ADR-0004 |
| 006 | TileMapLayer Rendering Integration | Visual/Feel | Ready | ADR-0004 |

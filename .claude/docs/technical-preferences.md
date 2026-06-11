# Technical Preferences

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Rendering**: Godot 2D rendering pipeline (forward+ or mobile, TBD based on performance profiling)
- **Physics**: Godot 2D PhysicsServer2D (Default)

## Input & Platform

- **Target Platforms**: PC (Steam / Epic)
- **Input Methods**: Keyboard/Mouse, Gamepad
- **Primary Input**: Keyboard/Mouse
- **Gamepad Support**: Partial (navigation + core gameplay, no d-pad required)
- **Touch Support**: None
- **Platform Notes**: PC-first design. No console/mobile considerations.

## Naming Conventions

- **Classes**: PascalCase (e.g., `PlayerController`)
- **Variables/functions**: snake_case (e.g., `move_speed`)
- **Signals**: snake_case past tense (e.g., `health_changed`)
- **Files**: snake_case matching class (e.g., `player_controller.gd`)
- **Scenes**: PascalCase matching root node (e.g., `PlayerController.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_HEALTH`)

## Performance Budgets

- **Target Framerate**: 60 fps
- **Frame Budget**: 16.6ms
- **Draw Calls**: < 1000 for main gameplay view
- **Memory Ceiling**: 512 MB (soft), 1 GB (hard)

## Testing

- **Framework**: GdUnit4 (addons/gdUnit4)
- **Minimum Coverage**: Core logic systems (formulas, state machines)
- **Required Tests**: Balance formulas, gameplay systems, tick system

### Running Tests

Tests are GdUnit4 `GdUnitTestSuite` classes — they cannot be run as standalone Godot scripts.

**Run full suite:**
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/
```

**Run a single test suite:**
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/unit/tick/speed_pause_test.gd
```

**Ignore a specific test case:**
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/ -i tests/unit/tick/speed_pause_test.gd:test_pause_no_accumulation
```

**Continue on failure (run all tests, don't stop at first failure):**
```bash
bash addons/gdUnit4/runtest.sh --godot_binary /Applications/Godot.app/Contents/MacOS/godot -a res://tests/ --continue
```

Adjust `--godot_binary` for your system (e.g. Linux: `$(which godot)`). HTML/XML reports are written to `reports/`.

## Forbidden Patterns

- **`Engine.get_singleton("Name")`** — NEVER use for GDScript Autoloads. Returns `null` silently.
  Access Autoloads directly by their registered name: `PathSystem.has_path(pos)`, `BuildingRegistry.get_movement_cost(id)`.
  `Engine.get_singleton()` is only for C++ engine singletons and plugin singletons.
  See `.claude/rules/godot-singletons.md` for the full rule and Autoload table.

## Allowed Libraries / Addons

- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and cross-cutting code review. Invoke GDScript specialist for code quality, signal architecture, static typing enforcement, and GDScript idioms. Invoke shader specialist for material design and shader code. Invoke GDExtension specialist only when native extensions are involved.

### File Extension Routing

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |

# Smoke Test: Critical Paths

**Purpose**: Run these 10-15 checks in under 15 minutes before any QA hand-off.
**Run via**: `/smoke-check` (which reads this file)
**Update**: Add new entries when new core systems are implemented.

## Core Stability (always run)

1. Game launches to main menu without crash
2. New game / session can be started from the main menu
3. Main menu responds to all inputs without freezing

## Core Mechanic (update per sprint)

<!-- Add the primary mechanic for each sprint here as it is implemented -->
<!-- Example: "Player can move, jump, and the camera follows correctly" -->
4. Tick system accumulates ticks at 1x speed (1000 ticks in ~100s) — verified by unit tests
5. Tick system respects pause (no auto-accumulation) — verified by unit tests
6. Tick system clamps lag spikes to 100 ticks per frame — verified by unit tests

## Data Integrity

7. Save game completes without error (once save system is implemented)
8. Load game restores correct state (once load system is implemented)

## Performance

9. No visible frame rate drops on target hardware (60fps target)
10. No memory growth over 5 minutes of play (once core loop is implemented)

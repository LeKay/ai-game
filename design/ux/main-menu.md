# UX Spec: Main Menu

> **Status**: In Design
> **Author**: User + ux-designer
> **Last Updated**: 2026-05-18
> **Journey Phase(s)**: unknown — no player journey map
> **GDD Alignment**: pending — GDDs not yet authored; alignment to be validated when GDDs exist
> **Platform Target**: PC (Steam / Epic) — KBM + Gamepad (partial)
> **Template**: UX Spec

---

## Purpose & Player Need

The main menu serves as the functional gateway between launching the game and entering gameplay. It has four responsibilities:

1. **Start a new game** — begin a fresh village. The player wants to play, not navigate.
2. **Continue** — load the last saved game session. The player wants to resume where they left off without re-navigating.
3. **Access settings** — configure input bindings, audio levels, and accessibility options before playing. Settings modal deferred to MVP — "Settings" button visible but disabled in VS.
4. **Quit** — exit cleanly.

What would go wrong if this screen was hard to use? If the player can't find "New Game" quickly, the first friction point kills the invitation feeling the art bible describes for the menu/dusk state. If settings are buried, the player has to restart to adjust something.

---

## Player Context on Arrival

The main menu appears in two scenarios:

1. **First launch** — player has just launched the game for the first time. No prior context. The art bible's "Invitation" mood applies: warm, welcoming, anticipatory. The dusk village diorama signals this is a game about starting something.
2. **Return session** — player quit or paused mid-session and is back later. They may remember their village state, what they were working on. The mood is familiar — "there's work to be done."

In both cases, the player is not time-pressured. The art bible specifies "Open-ended — the player sets their own pace." The design must allow a moment to absorb the atmosphere before the player commits to an action.

The player's immediate need after reading the game concept or seeing store art is to *start playing*. Friction here destroys the invitation.

---

## Navigation Position

The main menu lives at the root of the navigation hierarchy.

```
Main Menu (root)
├── Gameplay (New Game / Continue)
├── Settings Screen
└── Exit
```

It is always reachable when the player is not in an active gameplay session. In the vertical slice, the only return path to the main menu from gameplay is through the pause menu. Nothing sits above the main menu — it is the entry point.

Alternate entry paths: none beyond launch and return-from-pause in the vertical slice scope.

---

## Entry & Exit Points

| Entry Source | Trigger | Player carries this context |
|---|---|---|
| Game launch | Player clicks desktop icon / Steam "Play" | Nothing — fresh session |
| Pause menu | Player presses Pause/Esc → "Return to Main Menu" | Last saved game state (session memory) |

| Exit Destination | Trigger | Notes |
|---|---|---|
| Gameplay | Click/Tap "New Game" or "Continue" | New Game starts with fresh world; Continue loads last save via WorldSaveManager (ADR-0006) |
| Settings Screen | Click/Tap "Settings" | Disabled in VS — deferred to MVP |
| Exit game | Click/Tap "Quit" | Saves current game state before exit if any unsaved progress exists |

---

## Layout Specification

### Information Hierarchy

1. **Game title** — visual anchor, establishes identity. Art bible: `#F0EDE6` with `#D4A85C` golden outline. Large, centered, at eye level.
2. **"New Game" button** — primary call-to-action. First interactive element the player reaches.
3. **"Continue" button** — secondary action. Visible but lower priority.
4. **"Settings" button** — utility, disabled in VS (deferred to MVP).
5. **"Quit" button** — destructive action, least priority. At bottom edge to prevent accidental activation.

### Layout Zones

- **Zone 1 — Title**: Centered near top. Art bible: `#F0EDE6` fill with `#D4A85C` golden outline. Largest typographic element. Visual anchor.
- **Zone 2 — Primary actions**: New Game and Continue, centered vertical stack below title. Primary button colors: `#5A5A5A` fill, `#E8E4DC` text (idle). Hover: `#4A7EA8` fill, `#F0EDE6` text. Selected: `#F0EDE6` fill, `#3A3A3A` text.
- **Zone 3 — Utility actions**: Settings (disabled in VS) and Quit at bottom edge. Settings muted. Quit uses same button color system as Zone 2.
- **Zone 4 — Background**: Solid dark gradient (VS only — dusk diorama deferred to MVP). UI uses neutral-cool palette (`#3A3A3A` panels, `#5A5A5A` borders).

### Component Inventory

| Zone | Component | Type | Content | Interactive | Notes |
|------|-----------|------|---------|-------------|-------|
| Title | Title label | Label | Game title ("From Scratch") | No | Silkscreen ~20px |
| Primary | New Game button | Button | "New Game" | Yes | Silkscreen 16px, sharp rectangle |
| Primary | Continue button | Button | "Continue" | Yes | Silkscreen 16px, sharp rectangle |
| Utility | Settings button | Button | "Settings" | No (disabled in VS) | Deferred to MVP — placeholder, muted color, no interaction |
| Utility | Quit button | Button | "Quit" | Yes | Silkscreen 16px, sharp rectangle |
| Overlay | Try Again button | Button | "Try Again" | Yes | Visible only in Load Failed state, Silkscreen 16px |
| Overlay | New Game (fallback) button | Button | "New Game" | Yes | Visible only in Load Failed state, Silkscreen 16px |

All buttons follow the art bible shape grammar: sharp rectangles (0px corner radius normal → 2px hover → 4px active). Pure text labels, no icons.

### ASCII Wireframe

```
    ┌──────────────────────────┐
    │                          │
    │       From Scratch       │  ← Zone 1: Title, centered ~20% from top
    │                          │
    │     ┌──────────────┐     │
    │     │  New Game    │     │  ← Zone 2: Primary actions
    │     └──────────────┘     │
    │     ┌──────────────┐     │
    │     │  Continue    │     │     (vertically centered stack)
    │     └──────────────┘     │
    │                          │
    │     ┌──────────────┐     │
    │     │  Settings    │     │  ← Zone 3: Utility actions
    │     └──────────────┘     │        (disabled, muted)
    │     ┌──────────────┐     │
    │     │  Quit        │     │        (bottom edge)
    │     └──────────────┘     │
    │                          │
    └──────────────────────────┘
         Zone 4: Background
```

---

## States & Variants

| State / Variant | Trigger | What Changes |
|---|---|---|
| Default | Normal load | All buttons visible. Title centered, buttons in column. |
| No save | Continue checked — no save file exists | "Continue" button disabled (grayed), `#5A5A5A` fill, muted text color. No tooltip in VS. |
| Settings disabled | Persistent state in VS | "Settings" button disabled — muted color, not focusable, no interaction. Deferred to MVP. |
| Loading | Player clicks Continue (save exists) | "Loading..." label displayed. WorldSaveManager.load() in progress. All buttons disabled. |
| Load Failed | Player clicks Continue; WorldSaveManager.load() fails (corrupt save, missing file, I/O error) | "Loading failed" message displayed. Two buttons shown: "Try Again" (retries the load) and "New Game" (abandons load, starts fresh). All original buttons re-enabled. |
| Quit | Player clicks "Quit" | Game state saved (if any unsaved progress), then process exits immediately. No confirmation dialog. |

---

## Interaction Map

| Component | Player Action | Input | Immediate Feedback | Outcome |
|---|---|---|---|---|
| New Game | Left click / Gamepad A | Mouse click / Gamepad button | Button highlights to `#4A7EA8` (hover color) | Start new game scene, destroy main menu |
| Continue | Left click / Gamepad A | Mouse click / Gamepad button | Button highlights to `#4A7EA8` (hover color) | Load last save → start game scene |
| Settings | — | — | No interaction (disabled in VS) | Deferred to MVP — button visible but not focusable or clickable |
| Quit | Left click / Gamepad long-press A (≥500ms) | Mouse click / Gamepad button (held ≥500ms) | Button highlights to `#4A7EA8` (hover color) | Save state (if needed), quit process |

**Focus order** (top to bottom): New Game → Continue → Quit (Settings disabled in VS, not focusable)

**Input mappings:**
- **Mouse**: hover to navigate, click to select
- **Gamepad**: D-pad / stick to cycle focus, A button to confirm. Quit requires long-press A (≥500ms) to prevent accidental activation while navigating.
- **Keyboard**: Tab to cycle focus, Enter/Space to confirm, Escape — no action (main menu is root screen, no parent to return to)

---

## Events Fired

| Player Action | Event Fired | Payload / Data |
|---|---|---|
| New Game | `game_started` | `{"mode": "new", "timestamp": <iso8601>}` |
| Continue | `game_loaded` | `{"save_file": "last_save.json", "timestamp": <iso8601>}` |
| Settings | None (disabled in VS) | — |
| Quit | `game_exited` | `{"timestamp": <iso8601>}` |

**Note**: Events modify no game state — they are observational only. Any persistent state changes come from `WorldSaveManager` (ADR-0006), not from menu actions.

---

## Transitions & Animations

| Trigger | Animation | Duration | Easing |
|---|---|---|---|
| Screen enter | Fade in from black | 300ms | ease-out |
| Screen exit | Fade out to black | 300ms | ease-out |
| Button press | Instant color change (no animation) | — | — |

Follows art bible Section 7.4: "Functional, not decorative." No spring/overshoot. Max 1 simultaneous animation (screen transition). Settings modal deferred to MVP.

---

## Data Requirements

| Data | Source System | Read / Write | Notes |
|------|--------------|--------------|-------|
| Save file existence | WorldSaveManager (ADR-0006) | Read | Checked on menu load and on return from gameplay. If WorldSaveManager returns null/error, treat as "No save." Determines if "Continue" is enabled or disabled. |
| Last save metadata | WorldSaveManager (ADR-0006) | Read | Not displayed in VS — Continue button is minimal text only |
| Player settings (audio, input) | SettingsManager (singleton) | Read | Settings modal deferred to MVP — settings storage exists, no UI |

The menu owns no game state. It's purely a navigation layer. No write operations from menu to game systems except triggering `WorldSaveManager.load()` or `WorldSaveManager.save()` on quit.

---

## Accessibility

- **Focus indicator**: 2px `#D4A85C` golden outline ring on all focusable buttons. Matches art bible golden accent. Solid stroke, no glow/shadow effect. Always visible — not dependent on hover state.
- **Keyboard navigation**: Tab cycles through focusable buttons in order (New Game → Continue → Quit). Settings is not focusable in VS. Enter/Space confirms. Escape — no action (root screen). Godot's Control node focus system handles this natively.
- **Gamepad navigation**: D-pad/stick cycles focus in same order as keyboard. A button confirms. Settings button is disabled and not focusable in VS.
- **Text contrast**: `#F0EDE6` on `#3A3A3A` background ≈ 10:1 ratio (well above WCAG AA 4.5:1). `#E8E4DC` button text on `#5A5A5A` fill ≈ 5.0:1 (exceeds WCAG AA 4.5:1 at 16px).
- **Font minimum**: 20px title, 16px button text. No text below 14px (per art bible).
- **Color-independent disabled state**: Disabled "Continue" uses muted text color AND reduced opacity — not color change alone. Disabled "Settings" button uses the same treatment.
- **Reduced motion**: A reduced-motion preference disables animations. Fade transitions and slide animations become instant.

---

## Localization Considerations

All button labels are short enough that 40% text expansion (e.g., German "Neues Spiel" = 11 chars) won't break the centered button layout. No number/date/currency formatting needed in the main menu.

Button widths should be flexible (not fixed-pixel) to accommodate 40% text expansion — the layout must reflow naturally rather than clipping or overflowing text in expanded locales.

| Text Element | English | Max Length (40% expansion) | Locale-Critical |
|---|---|---|---|
| Title | "From Scratch" | 16 chars | No — title stays as-is |
| Button 1 | "New Game" | 12 chars | No — 9 chars fits comfortably |
| Button 2 | "Continue" | 12 chars | No — 10 chars, tight but fits |
| Button 3 | "Settings" | 12 chars | No — 8 chars, plenty of room |
| Button 4 | "Quit" | 8 chars | No — 4 chars, trivial |

For the vertical slice, all strings are hardcoded English. Should be extracted to external locale files before MVP.

---

## Acceptance Criteria

- [ ] Main menu screen loads within 500ms of game launch (or engine ready signal)
- [ ] Main menu layout is functional and readable at 800x600, 1920x1080, and 3440x1440 (21:9)
- [ ] All focusable buttons are reachable via keyboard (Tab cycling) and gamepad (D-pad/stick)
- [ ] "Continue" button is disabled (grayed) when no save file exists, enabled when a save file exists
- [ ] "Settings" button is disabled (grayed) in VS — no interaction
- [ ] Clicking "New Game" starts a new game scene and destroys the main menu
- [ ] Clicking "Continue" loads the last save via WorldSaveManager (ADR-0006) and transitions to game scene
- [ ] Clicking "Quit" exits the process cleanly (no hang, no crash)
- [ ] All interactive elements have visible focus indicators when navigated via keyboard or gamepad
- [ ] "Loading..." state appears within 200ms of clicking "Continue" (after WorldSaveManager.load() begins)
- [ ] Pressing Escape on the main menu produces no action (main menu is root — no "previous screen" to return to)

---

## Open Questions

1. **Window size** — Main menu opens in windowed mode (not fullscreen). Exact resolution and aspect ratio TBD during implementation.
2. **Settings modal scope** — Deferred to MVP. "Settings" button is disabled in VS.
3. **Background diorama** — Deferred to MVP. VS uses solid dark gradient.
4. **Game title text** — English ("From Scratch") confirmed for VS.

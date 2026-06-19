class_name UiPalette
## Single source of truth for the dark-theme UI palette and shared sizing.
##
## These values were previously copy-pasted across the grid components and detail
## panels (identical literals confirmed before centralisation). Reference them
## instead of re-declaring local colour constants.
##
## See docs/architecture/refactor-plan-code-consolidation-2026-06-13.md (Phase 4).

# ── Panel chrome (detail / transportation panels) ─────────────────────────────
const PANEL_BG: Color = Color(0.176, 0.176, 0.176, 0.97)  ## #2D2D2D translucent
const SEPARATOR: Color = Color(0.35, 0.35, 0.35, 1.0)

# ── Icon-block grids (inventory / building / crafting / npc) ───────────────────
const BLOCK_BG: Color = Color("#2a2a2a")
const BLOCK_BORDER: Color = Color("#4a4a4a")
const HOVER_BORDER: Color = Color("#A8A49C")
const BLOCK_BG_DISABLED: Color = Color("#1a1a1a")
const BLOCK_BORDER_DISABLED: Color = Color("#2e2e2e")

# ── Text ──────────────────────────────────────────────────────────────────────
const TEXT_PRIMARY: Color = Color("#F0EDE6")
const TEXT_DIM: Color = Color("#A8A49C")

# ── Sizing ────────────────────────────────────────────────────────────────────
const ICON_SIZE: int = 48
const BLOCK_GAP: int = 8
const DISABLED_ALPHA: float = 0.5

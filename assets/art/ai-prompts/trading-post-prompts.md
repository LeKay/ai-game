# Trading Post — AI Asset Prompts

Generated: 2026-06-24

## Global Style Reference (from sprite-prompts.md)

- **Perspective**: buildings at ~60–70° above horizon ("classic top-down RPG perspective") — top + narrow front strip visible.
- **Light**: source top-left, shadows fall bottom-right.
- **Palette**: earthy, muted — no neon/saturated colors. 2–3 shading levels per hue.
- **Outline**: no outer outline — internal depth lines only.
- **Composition**: object centered, ≥2–4 px margin on all sides, transparent background.
- **Footprint**: ~18–20 px wide, ~14–16 px tall. Gabled roof (highlight left, shadow right), narrow front-wall strip with door (~3×4 px), one characteristic prop for instant recognisability.

---

### 1. Trading Post / Trading Post — `bld_tile_trading_post.png`

A small market building with a covered awning, a banner or sign post out front, and stacked barrels/crates beside the entrance — immediately readable as a commerce hub.

**Prompt:**
```
Classic top-down RPG perspective, ~60–70° above horizon. A compact trading post building with a gabled wooden roof seen from slightly above. The roof has a central ridge running left-to-right with a highlight strip on the left face and a deep shadow on the right face. The front wall strip shows a wide arched doorway (~4×4 px) draped with a cloth awning in warm ochre. A small wooden sign post stands to the right of the entrance. Two stacked wooden crates and a barrel are nestled against the left wall. Light source top-left, shadows fall bottom-right. Earthy, muted palette — warm timber browns, ochre awning, cream-white walls. 2–3 shading levels per color. No outer outline, only internal depth lines. Object perfectly centered with at least 3 px transparent margin on all sides. Everything outside the building silhouette is fully transparent.
```

**Target colors:** Roof highlight `#C8A860` · Roof midtone `#A07838` · Roof shadow `#6B4E20` · Wall `#D4C8A0` · Door/awning `#C89040` · Crates `#A07840` · Sign post `#8B6530`
**Background:** Transparent

---

## Assembly Notes

- Export from PixelLab as PNG at exactly 64×64 px.
- Place at `assets/art/buildings/bld_tile_trading_post.png`.
- Godot import settings: Filter = Nearest, Mipmaps = Disabled.
- `.import` sidecar is auto-generated on first editor scan — do not create manually.
- After placing in Godot, verify the building tile renders correctly in build mode and the detail panel shows the "Dispatch Goods" recipe.

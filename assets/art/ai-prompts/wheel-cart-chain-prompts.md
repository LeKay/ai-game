# AI Asset Prompts — Wheel & Cart Chain

Generated: 2026-06-24

## Global Style (inherited from sprite-prompts.md)

- **Perspective:** slightly elevated ~60–70° above the horizon ("classic top-down RPG") — top face plus narrow front strip visible.
- **Light:** upper-left source, shadows fall to the lower-right.
- **Palette:** earthy, muted — no saturated neons. 2–3 shading tones per colour (highlight, midtone, shadow).
- **Outline:** none around the full object — only internal depth lines.
- **Background:** fully transparent — no ground, no frame, no fill.
- **Composition:** object centred, all four sides equal margin, nothing clipped, ≥2–4 px gap to every edge.
- **Building footprint:** ~18–20 px wide, ~14–16 px tall. Saddle roof (highlight left, shadow right), narrow front-wall strip with door (~3×4 px), one characteristic trade prop.

---

## 1. Wheel Maker / Rad-Werkstatt — `bld_tile_wheel_maker.png`

A small workshop where a wheelwright shapes and carves raw logs into large wooden wheels. Characteristic prop: two or three large spoked wooden wheels leaning against the side wall.

**Prompt:**
```
Pixel art building tile for a top-down RPG game. A wheel maker workshop seen from a slightly elevated angle (~60-70 degrees above horizon), showing the top face and a narrow front strip. The building has a warm brown saddle roof with highlight on the left slope and shadow on the right. A narrow front wall below the roof has a small wooden door (~3x4 px). Leaning against the right side of the building are two or three large spoked wooden wheels — each wheel is roughly 6 px in diameter, rendered with a circular rim, four or five thin spoke lines radiating from a small dark hub at centre, with highlight on the upper-left arc and shadow on the lower-right arc. The walls are warm tan-brown timber planks with subtle vertical plank lines. Light source upper-left, earthy muted palette, 2-3 shading tones per colour, no outline around the full object, only internal depth lines. Everything outside the building silhouette is fully transparent. Color palette: roof highlight #8B5A2B, roof midtone #6B3F1E, roof shadow #4A2B10, wall plank #C8A06A, door #5C3A1E, wheel rim #A07840, wheel spoke #8B6030, wheel hub #4A3018.
```

**Target colours:** Roof highlight `#8B5A2B` · Roof mid `#6B3F1E` · Roof shadow `#4A2B10` · Wall `#C8A06A` · Door `#5C3A1E` · Wheel rim `#A07840` · Wheel spoke `#8B6030` · Hub `#4A3018`
**Background:** Transparent

---

## 2. Cart Workshop / Karren-Werkstatt — `bld_tile_cart_workshop.png`

A workshop where carts are assembled from planks and wheels. Characteristic prop: a finished wooden cart with two large wheels sitting in front of the entrance.

**Prompt:**
```
Pixel art building tile for a top-down RPG game. A cart workshop seen from a slightly elevated angle (~60-70 degrees above horizon), showing the top face and a narrow front strip. The building has a dark tan saddle roof with highlight on the left slope and shadow on the right. A narrow front wall below the roof has a small wooden door (~3x4 px). In front of the entrance sits a small finished wooden cart — the cart body is a flat rectangular plank frame about 8 px wide and 5 px tall, with two spoked wheels (each ~5 px diameter) visible on either side, rendered with rim arc, spokes, and a small hub. The cart casts a tiny shadow to the lower-right. The walls are warm tan timber planks with subtle plank lines. Light source upper-left, earthy muted palette, 2-3 shading tones per colour, no outline around the full object, only internal depth lines. Everything outside the building silhouette is fully transparent. Color palette: roof highlight #7A4A22, roof midtone #5A3215, roof shadow #3A200B, wall plank #C8A06A, door #5C3A1E, cart body #B89050, cart shadow #6B4E28, wheel #A07840, wheel hub #4A3018.
```

**Target colours:** Roof highlight `#7A4A22` · Roof mid `#5A3215` · Roof shadow `#3A200B` · Wall `#C8A06A` · Door `#5C3A1E` · Cart body `#B89050` · Cart shadow `#6B4E28` · Wheel `#A07840` · Hub `#4A3018`
**Background:** Transparent

---

## 3. Wheel (UI Icon) — `assets/ui/icons/resources/wheel.png`

A single large spoked wooden wheel, centred on transparent background. Used in carrier animation and resource HUD.

**Prompt:**
```
Pixel art resource icon for a top-down RPG game. A single large wooden wheel with spokes, seen from a slightly elevated angle (~60-70 degrees above horizon). The wheel has a thick circular wooden rim rendered with highlight on the upper-left arc and shadow on the lower-right arc. Five or six straight spoke lines radiate from a small dark circular hub at the centre to the inner edge of the rim. The rim is wider at the top (facing the light source) and narrower in shadow at the bottom-right. The wheel is exactly centred in the 64x64 tile with equal margins on all sides, fully visible, no part clipped, at least 6 px gap to every edge. Light source upper-left, earthy muted palette, no outline around the full object, only internal depth lines. Everything outside the wheel silhouette is fully transparent. Color palette: rim highlight #C8A06A, rim midtone #A07840, rim shadow #6B4E28, spoke #8B6030, hub #4A3018, hub highlight #6B4E28.
```

**Target colours:** Rim highlight `#C8A06A` · Rim mid `#A07840` · Rim shadow `#6B4E28` · Spoke `#8B6030` · Hub `#4A3018`
**Background:** Transparent

---

## 4. Cart (UI Icon) — `assets/ui/icons/resources/cart.png`

A small wooden cart with two spoked wheels, centred on transparent background. Used in carrier animation and resource HUD.

**Prompt:**
```
Pixel art resource icon for a top-down RPG game. A small wooden cart seen from a slightly elevated angle (~60-70 degrees above horizon), showing the top face of the flat cart bed and a narrow front strip. The cart body is a simple rectangular flat-bed frame made of planks — roughly 20 px wide and 14 px tall in the tile. Two large spoked wooden wheels (each ~10 px diameter) are attached on either side of the cart body, visible as circular rims with four or five spokes radiating from a small hub. The cart bed planks have subtle horizontal grain lines and a light shadow at the lower-right edge. The cart is exactly centred in the 64x64 tile with equal margins, fully visible, no part clipped, at least 4 px gap to every edge. Light source upper-left, earthy muted palette, no outline around the full object, only internal depth lines. Everything outside the cart silhouette is fully transparent. Color palette: cart bed highlight #C8A06A, cart bed midtone #A07840, cart bed shadow #6B4E28, wheel rim #8B6030, wheel hub #4A3018, plank grain #B89050.
```

**Target colours:** Bed highlight `#C8A06A` · Bed mid `#A07840` · Bed shadow `#6B4E28` · Wheel `#8B6030` · Hub `#4A3018` · Grain `#B89050`
**Background:** Transparent

---

## Atlas / Next Steps

1. Generate PNGs via PixelLab `create-image-pixen` (64×64, `high top-down`, `lineless`, `no_background: true`).
2. Place building tiles → `assets/art/buildings/bld_tile_wheel_maker.png` and `bld_tile_cart_workshop.png`
3. Place UI icons → `assets/ui/icons/resources/wheel.png` and `assets/ui/icons/resources/cart.png`
4. `.import` sidecars are created automatically on the next Godot editor scan.
5. Verify visually against art bible (palette, perspective, characteristic prop visible).

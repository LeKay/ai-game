# Accessibility Requirements

> **Status**: Draft
> **Last Updated**: 2026-05-18
> **Template**: Accessibility Requirements

---

## Accessibility Tier

**Standard**

This tier requires:
- Keyboard navigation fully specified for all interactive screens
- Focus order defined (Tab order for keyboard, d-pad order for gamepad)
- Text contrast ratios meeting WCAG AA (4.5:1)
- Color-independent communication for all color-coded information
- Reduced motion option for all screen animations

---

## Platform Requirements

- **PC (Steam / Epic)**: Keyboard/Mouse (primary) + Gamepad (partial, navigation + core gameplay)
- **Touch Support**: None — no touch-specific accessibility considerations

---

## Screen-Level Requirements

Each screen spec must document:
1. Input method coverage (keyboard, gamepad)
2. Focus order and navigation flow
3. Color-independent communication for all status indicators
4. Text minimum size (14px body, 16px controls)
5. WCAG AA contrast compliance
6. Reduced motion behavior

Referenced in each UX spec header under an `Accessibility` section.

---

## Game-Wide Rules

1. **No color-only indicators**: Every color-coded state must have an icon or text alternative.
2. **All interactive elements must be reachable via keyboard/gamepad**: If a player can click it, they must be able to focus and activate it without a mouse.
3. **Focus indicators are always visible**: Minimum 2px outline ring on focused elements.
4. **Text is never smaller than 14px**: Controls and headers at 16px minimum.
5. **All animations can be disabled**: A global reduced-motion toggle eliminates all non-essential animations and makes state changes instant.

# Desktop secondary menu theme verification

Desktop secondary menus inherited the dark toolbar's white foreground and lacked a background. Theme colors previously applied only inside the touch-layout media query. Menus now use the editor's background, text, fill, accent, divider and muted colors at all viewport sizes, with a border and shadow. Dark primary actions retain dark foregrounds for contrast against the light accent.

Validation:
- `npm run typecheck`, `npm test` (27 passed), `npm run build`.
- macOS WKWebView fixture at 1280 × 900: style, table, list, code, link and node action menus in both light and dark themes. Checks require an opaque menu surface, foreground contrast of at least 4.5:1 and enabled action icon contrast of at least 3:1. Existing list interaction checks also passed.
- Screenshots: `docs/screenshots/desktop-menu-theme-2026-10-05/`; light style and dark table screenshots visually inspected.
- `./scripts/build_native.sh macos-app` succeeded. Built and installed web entry files and executables match. Updated `/Applications/Siye.app` after graceful quit and reopened it.

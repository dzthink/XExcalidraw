# Unified desktop toolbar style

The primary toolbar now follows the document theme, matching secondary menus with a 12px radius, border, shadow and 36px controls. Both levels use the same SVG icon family and hover/selection colors. Expanded primary entries expose `aria-expanded` and highlight the currently open menu. Desktop inputs use the corresponding native color scheme; the keyboard-dismiss control is hidden on desktop.

Verification:
- TypeScript check, 27 unit tests and production web build passed.
- macOS WKWebView fixture at 1280 × 900 passed list interactions, all six menus in light/dark themes, icon contrast, identical primary/secondary surface styles, button dimensions and expanded-state checks.
- Screenshots in `docs/screenshots/desktop-toolbar-style-2026-10-05/`; light/dark format menu screenshots visually inspected.
- macOS app build succeeded; installed in `/Applications/Siye.app` after graceful quit and reopened. Installed embedded web entry and executable match the current build.

Follow-up: Removed the duplicate indent/outdent entries from the more-actions menu, retaining the text-format list commands. TypeScript check, production build and the WebKit fixture passed, including format-menu indent/outdent interactions. Visually checked the updated more-actions screenshot in `docs/screenshots/desktop-indent-menu-2026-10-05/`. Rebuilt and updated the desktop app.

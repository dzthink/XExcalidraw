# Outline hierarchy guides — 2026-10-03

## Change

Compared the outline with the user-provided Mubu document. Each outline level now
connects adjacent siblings with a subtle vertical guide aligned with their bullets.
Guides continue alongside expanded subtrees, stop at the final sibling, and retain
the existing 28px indentation. Expanded final nodes retain the guide alongside
their children. Decorative guides do not intercept pointer input.

## Validation

- `npm run typecheck`: passed.
- `npm test`: all 16 existing tests passed.
- `npm run build`: passed (existing bundle-size warning).
- Browser fixture: checked nested siblings, terminal leaves, expanded/collapsed
  subtrees, selection, multiline content, light/dark themes, and a 390×844 viewport.
- `./scripts/build_native.sh macos-app`: passed; the packaged Web entry matches
  the production build.
- Ran the new macOS app from `build/native/macos/Siye.app` and opened a dedicated
  temporary mind-map file through the native folder picker.
- Native WebKit: checked three levels of siblings, the final parent and its final
  nested subtree, collapse/re-expand, and terminal leaves. Guides stay aligned and
  do not continue below the final leaf.
- Tiled the native window to the left half of the screen: the long sibling wraps
  to three lines while its guide still connects to the next sibling. Restored the
  previous window size afterward.
- Clicked and edited a native outline node, then used Command-Z: the node content
  returned to its original text and the app reported saved.
- Desktop automation initially failed to connect; after reconnection, the native
  visual and interaction checks above completed. iOS was not rebuilt or tested.

## Screenshots

- [Desktop](../screenshots/outline-guides/desktop.jpg)
- [390×844 viewport](../screenshots/outline-guides/mobile.jpg)
- [Native macOS expanded](../screenshots/outline-guides/macos-expanded.jpg)
- [Native macOS collapsed](../screenshots/outline-guides/macos-collapsed.jpg)
- [Native macOS half-window](../screenshots/outline-guides/macos-half-window.jpg)

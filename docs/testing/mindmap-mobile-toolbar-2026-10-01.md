# iOS mind-map keyboard toolbar — 2026-10-01/02

The previous web-positioned toolbar has been replaced on iOS with a native `inputAccessoryView`. UIKit attaches the floating material capsule to the current keyboard, independently of input-method height. The bar supports horizontal scrolling and a pinned keyboard-dismiss button. Desktop and standalone browser hosts retain the web toolbar.

Native buttons invoke current React action handlers directly. They no longer simulate clicks on hidden web controls. iOS suppresses the web action strip throughout keyboard and focus transitions. Contextual menus use a matching translucent material, rounded containers and buttons, consistent touch sizes, and a title/close row. Closing a menu explicitly restores the rich editor focus before removing its controls; the actual iPhone exposed keyboard dismissal here that the simulator did not.

The native accessory reports its actual top edge to the page after converting through the WebView's adjusted safe-area inset. Web contextual menus sit above that edge, and the map moves the editing node into view. This fixes the earlier mismatch where a menu could open behind the keyboard. No keyboard-height constant determines iOS toolbar placement.

The image button presents a native image-file picker. WebKit input focus is cleared before presentation and restored after dismissal. Touch-layout notes use 16px text to avoid iOS focus zoom displacing the menus. Selected image data follows the existing attachment-save acknowledgement flow. Test fixtures use separate temporary folders and defaults, with files seeded before adding the indexed folder; user document sources are unaffected.

## Validation

- TypeScript check, production web build, and 8 web tests passed.
- `build/ios-native-menus-focus-final.xcresult`: all 3 final simulator UI tests passed (canvas/mind-map opening, settings, onboarding picker, and toolbar).
- `build/iphone-native-menus-focus-2.xcresult`: the expanded toolbar test passed on the connected iPhone 17 in both outline and map modes.
- The test verifies native accessory bounds, visible editing text, list/table/code/link/node menus, keyboard retained after menu closure and bold, input-method switching, actual text undo/redo, notes, image-picker presentation/cancellation, resumed input, dismissal, and hidden web action controls.
- Device screenshots: `build/iphone-native-menus-focus-2-screenshots/`. Actual dark appearance and nine-key Chinese/English input were inspected.
- The final signed app is installed and was launched without fixture environment variables for normal user verification.

Only input methods available on the connected devices are exercised; third-party keyboards are not individually certified. Attachment persistence is covered by the existing unit tests. These UI tests verify picker entry and cancellation, not selecting and importing an actual photo.

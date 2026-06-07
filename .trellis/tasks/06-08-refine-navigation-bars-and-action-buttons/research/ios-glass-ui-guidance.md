# iOS / Liquid Glass UI Guidance

## Sources

* Apple HIG Materials: https://developer.apple.com/design/human-interface-guidelines/materials
* Apple HIG Tab bars: https://developer.apple.com/design/human-interface-guidelines/tab-bars/
* Apple WWDC25 Meet Liquid Glass: https://developer.apple.com/videos/play/wwdc2025/219/
* Apple WWDC25 Build a SwiftUI app with the new design: https://developer.apple.com/videos/play/wwdc2025/323/

## Takeaways

* Liquid Glass should be a functional navigation/control layer floating above content, not a decorative treatment inside the content layer.
* Content may peek through navigation materials, but controls must remain legible through tint, border, and shadow.
* Floating tab bars and toolbars can minimize or move at paint level while scrolling to preserve content visibility.
* Tab bars should remain stable and predictable. They are for top-level navigation, while current-view actions belong in toolbars or floating action controls.
* Monochrome icons, grouped controls, spacing, rounded shapes, subtle inner highlights, and clear touch targets reduce noise while increasing perceived polish.
* Avoid stacking glass on glass or applying blur to large scroll/video/WebView content because that can harm hierarchy and performance.

## Mapping To FluxDO

* Keep the existing paint-level show/hide mechanics for bottom bars; do not change body padding or scroll viewport size.
* Reuse small, bounded `BackdropFilter` surfaces already present in `AdaptiveScaffold` and `TopicBottomBar`.
* Upgrade top/bottom controls by tuning shape, tint, border, shadow, and selected icon treatment rather than adding expensive full-screen effects.
* Keep primary content area untouched: no extra cards, no content-layer glass, no reduced list height.
* Make the home create-topic FAB and topic reply FAB visually related, with gradient/blur/highlight treatments and unchanged tap targets.

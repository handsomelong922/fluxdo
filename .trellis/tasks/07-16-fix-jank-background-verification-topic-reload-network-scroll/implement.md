# Implementation Plan

1. Add tests for independent serial nested materialization and image decode width clamping; implement the queue and clamp.
2. Add CF challenge traffic-block state, clear it on verified clearance, and gate `ScreenTrack` sends while blocked; test the state transitions/policy.
3. Change only automatic `BrowserTrustCoordinator` recovery to background verification; keep explicit manual/login callers foreground and add a focused policy test where practical.
4. Add preview continuity tests for target windows without OP; use initial preview for nested loading and pass bookmark preview data into the shared route.
5. Make network-settings developer mode first-frame synchronous and stabilize diagnostics card geometry; add focused widget/policy coverage.
6. Run Dart formatting, targeted tests for every touched area, targeted analyze, broader related regression tests, full `flutter analyze --no-pub`, and full Flutter tests.
7. Review diffs for homepage/card style and request-policy regressions. Commit each independent code fix separately, then commit Trellis artifacts, archive task, and push the full batch once.

## Risk gates

- Do not change `autoExpandReplyThreshold`, nested manual expansion, homepage card widgets, or visual styles.
- Do not synthesize or cache a discontinuous authoritative `PostStream`.
- Do not clear CF blocked state without a verified fresh clearance.
- Do not suppress foreground interactive challenge entry points.
- Do not stage pre-existing untracked files outside this task directory and explicitly touched product/test/spec files.

## Validation commands

- `flutter test --no-pub test/widgets/post/reply_auto_expand_policy_test.dart test/widgets/content/lazy_image_test.dart`
- Focused CF/ScreenTrack and browser trust tests added by this task.
- `flutter test --no-pub test/pages/topic_detail_page/topic_detail_page_preview_test.dart test/pages/topic_detail_page/topic_detail_page_jump_target_test.dart`
- Focused network settings widget tests added by this task.
- `flutter analyze --no-pub <changed paths>`
- `flutter analyze --no-pub`
- `flutter test --no-pub`

# Implementation Plan

## Checklist

1. Read applicable specs through `trellis-before-dev`.
2. Inspect `MainPage`, `ProfilePage`, `NetworkLogInterceptor`, app logs/debug pages.
3. Add lazy bottom-page mounting while preserving active page state.
4. Gate profile statistics rendering behind `widget.isActive`.
5. Add bounded startup request recorder fed by `NetworkLogInterceptor`.
6. Add sorted request view or log/debug surface integration.
7. Validate no startup summary request from inactive profile in code path.
8. Run targeted `flutter analyze` on changed Dart files.

## Validation

- Static check: `flutter analyze` on changed files.
- Code inspection: confirm `/u/{username}/summary.json` is only reachable after profile page active or manual refresh.
- Runtime/manual check if environment permits:
  - Launch app.
  - Stay on homepage.
  - Inspect request ranking and logs.
  - Confirm home list and summaries load.
  - Confirm profile stats load after tapping “我的”.

## Risky Files

- `lib/main.dart`: bottom navigation page construction.
- `lib/pages/profile_page.dart`: profile rendering and refresh behavior.
- `lib/services/network/interceptors/network_log_interceptor.dart`: request timing/logging.
- Existing logs/debug UI file selected during implementation.

## Rollback Points

- After lazy mounting only.
- After profile active gate.
- After request recorder.
- After request ranking UI integration.

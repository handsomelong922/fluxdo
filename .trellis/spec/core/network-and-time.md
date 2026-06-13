# Network And Time Guidelines

## Discourse API Time

- Discourse API time strings are UTC.
- Parse API time strings with `TimeUtils.parseUtcTime()`.
- Display times with `TimeUtils.formatRelativeTime()`, `formatDetailTime()`, `formatCompactTime()`, `formatShortDate()`, or `formatFullDate()`.
- Do not use `DateTime.parse()` or `DateTime.tryParse()` directly in model or UI code for Discourse API fields.
- Do not call `.toLocal()` outside `lib/utils/time_utils.dart`.

Evidence:
- `AGENTS.md`
- `CODEX.md`
- `lib/utils/time_utils.dart`
- `lib/widgets/content/discourse_html_content/builders/local_date_builder.dart`

## Network Layer

- Network behavior should stay inside `lib/services/network/` or focused providers that call those services.
- Cookie synchronization is a cross-layer contract between Dio/CookieJar/WebView. Review `docs/cookie-sync-status.md` before changing login, CF verification, cookie persistence, or WebView priming.
- Preserve platform-specific adapter boundaries under `lib/services/network/adapters/` and `lib/services/network/cookie/strategy/`.

## Scenario: Discourse Plugin Mutation Endpoints

### 1. Scope / Trigger
- Trigger: implementing or fixing Discourse plugin mutations observed from the web app, such as follow/unfollow, boosts, reactions, or plugin OAuth helpers.

### 2. Signatures
- Follow user: `PUT /follow/{encodedUsername}.json`
- Unfollow user: `DELETE /follow/{encodedUsername}.json`
- Request body: empty unless the browser request shows a body.

### 3. Contracts
- Use the same `.json` endpoint shape observed in browser DevTools/HAR for plugin routes.
- Encode dynamic path segments with `Uri.encodeComponent`.
- Let `DiscourseDio` provide cookies and CSRF headers; do not hard-code tokens from HAR files.
- After a mutation that changes user-visible state, refresh the server resource or merge server response instead of only flipping local UI state.

### 4. Validation & Error Matrix
- `200`/`2xx` -> mutation accepted; refresh affected resource when the response body does not carry full state.
- `401`/`403` -> auth/session problem; propagate through existing auth/error interceptors.
- Network failure after mutation but before refresh -> keep the successful target state only as a temporary UI fallback and allow the next resource load to reconcile with server state.

### 5. Good/Base/Bad Cases
- Good: `await _dio.put('/follow/$encodedUsername.json');` then `getUser(username)` to read `is_followed`.
- Base: endpoint exists but returns no useful body; refresh affected model.
- Bad: `await _dio.put('/follow/$username');` followed by `_isFollowed = !_isFollowed` with no server verification.

### 6. Tests Required
- Verify the generated path includes `.json` and URI-encoded username.
- Verify UI state does not change on request failure.
- Verify successful mutation prefers refreshed server state when available.

### 7. Wrong vs Correct

#### Wrong
```dart
await _dio.put('/follow/$username');
_isFollowed = !_isFollowed;
```

#### Correct
```dart
final encodedUsername = Uri.encodeComponent(username);
await _dio.put('/follow/$encodedUsername.json');
final refreshed = await service.getUser(username);
_isFollowed = refreshed.isFollowed ?? true;
```

Evidence:
- `docs/cookie-sync-status.md`
- `lib/services/network/discourse_dio.dart`
- `lib/services/network/cookie/`
- `lib/services/network/adapters/`

## Links And Routing

- Internal topic link extraction and internal-link routing must use compatible URL normalization.
- Regression-test malformed but common forum URLs when changing link parsing, especially referral query spacing and tree/flat topic modes.

Evidence:
- `.trellis/spec/guides/cross-layer-thinking-guide.md`
- `lib/widgets/content/discourse_html_content/`
- `lib/pages/topic_detail_page/`

## Verification

- For network/time changes, run targeted analysis on changed Dart files and search for forbidden direct parsing:
  ```bash
  rg "DateTime\.(parse|tryParse)|\.toLocal\(" lib test packages
  ```
- Existing local-storage parsing may exist outside Discourse API handling; evaluate context before changing old code.

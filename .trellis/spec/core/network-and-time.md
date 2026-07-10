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
- Startup first-screen read requests may set `skipWebViewSessionSyncExtraKey` only when they are safe idempotent reads such as the visible topic-list first page or silent home first-post previews. This skips waiting for `WebViewSessionCookieRefreshService.ensureSynced()` but still lets the session sync continue in the background. Do not apply it to login/session recovery, CSRF, CF challenge, mutations, or requests that require a freshly bootstrapped WebView runtime session cookie.

## Scenario: Visible User Profile Read Bootstrap

### 1. Scope / Trigger
- Trigger: changing the first-load path for another user's profile, profile summary statistics, or request extras used by `/u/:username` reads.

### 2. Signatures
- `Options visibleUserProfileReadOptions()`
- `GET /u/{Uri.encodeComponent(username)}.json`
- `GET /u/{Uri.encodeComponent(username)}/summary.json`
- Request extras:
  - `priority: "high"`
  - `skipWebViewSessionSync: true`
  - `backgroundWebViewSessionSync: true`

### 3. Contracts
- Start the profile and summary requests concurrently; profile data remains the page-shell gate, while summary failure or latency must not cancel the profile request.
- Only the two user-profile endpoints above may use `visibleUserProfileReadOptions()`.
- Skipping the blocking session-sync wait must still trigger best-effort background WebView session sync through the explicit background flag.
- Preserve existing in-flight dedupe, five-minute summary cache, follow/block/notification mutations, and normal 401/403/CF recovery.
- Do not reuse this helper for login, CSRF, CF challenge, private messages, bookmarks, mutations, or generic user-content lists.

### 4. Validation & Error Matrix
- Profile succeeds before summary -> reveal the stable profile shell immediately; fill summary later.
- Summary fails -> keep the profile usable and retain the fixed summary placeholder geometry.
- Profile fails while summary succeeds -> show the existing profile error path; do not treat summary as a complete profile.
- Background session sync fails -> the safe GET may still complete with current cookies; existing auth/CF interceptors remain authoritative for recovery.

### 5. Good/Base/Bad Cases
- Good: both requests start in `initState`, use the dedicated options helper, and catch errors independently.
- Base: a cached summary may complete immediately while the profile request is still the page-shell gate.
- Bad: `await getUser()` before starting `getUserSummary()`, or globally marking all visible reads as session-sync-skipping.

### 6. Tests Required
- Assert the dedicated options contain high priority, blocking-sync skip, and background-sync flags.
- Assert an ordinary skip-only request does not silently gain background sync behavior.
- Keep request-session policy tests proving foreground interactive requests still wait for session sync.

### 7. Wrong vs Correct
#### Wrong
```dart
final user = await service.getUser(username);
final summary = await service.getUserSummary(username);
```

#### Correct
```dart
final summaryFuture = loadSummaryWithIndependentErrorHandling();
try {
  final user = await service.getUser(username);
  revealProfileShell(user);
} catch (error) {
  showProfileError(error);
}
await summaryFuture;
```

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

## Scenario: Notion Attachment File Uploads

### 1. Scope / Trigger
- Trigger: changing Notion export database schema, Discourse attachment persistence, `file_uploads`, or Markdown-to-Notion file blocks.

### 2. Signatures
- Database property: `Attachments: { files: {} }`.
- Page property value: `Attachments.files[] = { name, type: "file_upload", file_upload: { id } }`.
- Block value: `file.type = "file_upload"` with `file.file_upload.id`.
- API version: requests containing `file_upload` in either page properties or block children must use Notion-Version `2026-03-11`.

### 3. Contracts
- `notionExportDatabaseProperties()` and `notionExportUpgradeableProperties()` must both include `Attachments`.
- `NotionSyncService` downloads Discourse attachment links, uploads successful files through `NotionClient.uploadSinglePartFile()`, and writes the same uploaded file ids into both content blocks and the `Attachments` database property.
- Failed single-file downloads/uploads are skipped with debug logging and must not fail the entire page sync.
- Legacy schema fallback may drop `Attachments` only after schema upgrade/create fails with a missing-property validation error.

### 4. Validation & Error Matrix
- Missing `Attachments` column -> `upgradeDatabase()` adds the files property before sync.
- Page properties or children contain `file_upload` -> create/append request uses Notion-Version `2026-03-11`.
- Attachment exceeds direct upload limit or download fails -> omit that file property item and continue syncing remaining content.
- Notion missing-property validation after upgrade failure -> retry with legacy-compatible properties.

### 5. Good/Base/Bad Cases
- Good: attachment link becomes a Notion file block and also appears in the database `Attachments` files column.
- Base: no attachments produce no `Attachments` page property.
- Bad: storing only the original download URL in the database column, or checking only children for `file_upload` while properties still use the old Notion version.

### 6. Tests Required
- Assert export/upgrade database properties contain `Attachments.files`.
- Assert page creation with property-level `file_upload` sends Notion-Version `2026-03-11`.
- Assert uploaded attachments build `{ type: "file_upload", file_upload: { id } }` files property items.
- Assert Markdown attachment links still convert to Notion file blocks when upload metadata is available.

### 7. Wrong vs Correct

#### Wrong
```dart
await client.createPage(
  databaseId: databaseId,
  properties: {'Attachments': {'files': [{'external': {'url': url}}]}},
);
```

#### Correct
```dart
final uploadId = await client.uploadSinglePartFile(...);
await client.createPage(
  databaseId: databaseId,
  properties: {
    'Attachments': {
      'files': [
        {
          'name': filename,
          'type': 'file_upload',
          'file_upload': {'id': uploadId},
        },
      ],
    },
  },
);
```

## Verification

- For network/time changes, run targeted analysis on changed Dart files and search for forbidden direct parsing:
  ```bash
  rg "DateTime\.(parse|tryParse)|\.toLocal\(" lib test packages
  ```
- Existing local-storage parsing may exist outside Discourse API handling; evaluate context before changing old code.

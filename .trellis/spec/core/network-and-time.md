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
- Safe idempotent visible reads may bypass blocking WebView session sync only through the shared visible-read option path. That path must still request session sync in the background, and it must not be applied to login/session recovery, CSRF bootstrap, CF challenge recovery, mutations, or flows that require a freshly bootstrapped WebView runtime session cookie.

## Scenario: Visible Read Requests Must Not Block On Session Bootstrap

### 1. Scope / Trigger
- Trigger: changing foreground GET/read request options for topic lists, user profile pages, bookmarks/history/private messages, badge/user summary pages, or the Dio auth interceptor's WebView session-sync gate.

### 2. Signatures
- `const String skipWebViewSessionSyncExtraKey = 'skipWebViewSessionSync'`
- `const String backgroundWebViewSessionSyncExtraKey = 'backgroundWebViewSessionSync'`
- `bool shouldAwaitWebViewSessionSyncForRequest({required Map<String, dynamic> extra, required Map<String, dynamic> headers})`
- `Options _visibleReadOptions({Options? options})`
- `Options? visibleTopicListReadOptions({required int page, Options? options})`

### 3. Contracts
- Foreground visible read-only requests should use high priority and must not await `WebViewSessionCookieRefreshService.ensureSynced()` on the critical path.
- Those same requests should still request a background session sync attempt by setting both:
  - `skipWebViewSessionSyncExtraKey = true`
  - `backgroundWebViewSessionSyncExtraKey = true`
- This contract applies to safe idempotent visible reads such as:
  - topic list page 0 and load-more pages
  - user profile / summary / action / reaction reads
  - bookmarks, browsing history, private message lists, and similar visible user-content reads
- Do not use `_visibleReadOptions()` for mutations, login/session recovery, CSRF bootstrap, CF challenge recovery, or other flows that must wait for a fresh WebView runtime session.

### 4. Validation & Error Matrix
- Visible topic list page > 0 -> request proceeds immediately; session sync continues in background.
- Visible user profile open -> `/u/:username.json` and `/u/:username/summary.json` do not block on session bootstrap.
- Silent/background reads -> continue using low-priority background options.
- Mutations or auth recovery -> still use the existing blocking/auth-safe path; do not silently downgrade them to background sync.

### 5. Good/Base/Bad Cases
- Good: opening a profile or loading the second page of `/latest.json` is not stalled by a 15s WebView bootstrap timeout.
- Base: foreground visible reads still trigger best-effort background sync so session freshness can recover without blocking UI.
- Bad: every visible GET awaits `ensureSynced()` and makes profile/list pages feel frozen, or all visible requests fully skip sync without allowing the background recovery path to run.

### 6. Tests Required
- Unit-test `shouldAwaitWebViewSessionSyncForRequest()` for:
  - explicit skip
  - explicit background sync
  - silent background request
  - normal foreground request
- Unit-test `visibleTopicListReadOptions()` for:
  - high priority
  - skip flag present
  - background-sync flag present on later pages too

### 7. Wrong vs Correct
#### Wrong
```dart
final response = await _dio.get(
  '/latest.json',
  queryParameters: {'page': 1},
  options: _foregroundReadOptions(),
);
```

#### Correct
```dart
final response = await _dio.get(
  '/latest.json',
  queryParameters: {'page': 1},
  options: _visibleReadOptions(),
);
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

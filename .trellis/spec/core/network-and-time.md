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

## Scenario: CF Challenge Background Recovery And Reading-Telemetry Fuse

### 1. Scope / Trigger
- Trigger: changing CF challenge detection/recovery, browser-trust startup repair, `cf_clearance` synchronization, or `ScreenTrack` `/topics/timings` sends.

### 2. Signatures
- `CfChallengeService.markChallengeDetected()`
- `CfChallengeService.markClearanceResolved()`
- `CfChallengeService.isBusinessTrafficBlocked -> bool`
- `CfChallengeService.businessTrafficBlockedUntil -> ValueNotifier<DateTime?>`
- `CfChallengeService.showManualVerify(BuildContext? context, [bool forceForeground = true])`
- `shouldDeferScreenTrackSend(isBusinessTrafficBlocked) -> bool`
- `forceForegroundForAutomaticBrowserTrustRecovery == false`

### 3. Contracts
- An authoritative CF challenge response must call `markChallengeDetected()` before recovery. This opens a five-minute fuse for non-critical reading telemetry; pending local timing data remains buffered, but `ScreenTrack` must not send `/topics/timings` while the fuse is active.
- A verified fresh clearance stored through the existing CookieJar/WebView boundary must call `markClearanceResolved()` and clear the fuse immediately. A timeout alone is not success. After the five-minute fuse expires, at most the normal next telemetry send may probe; another authoritative challenge reopens the fuse.
- Startup/resume browser-trust self-recovery must call the existing verification flow with `forceForeground=false`. It retains the Headless WebView, Cookie synchronization, bootstrap retry, success detection, timeout, and cleanup behavior without mounting a visible route/barrier.
- Explicit user actions from login or Network Settings must pass `forceForeground=true`; they remain the supported fallback for a challenge that genuinely needs interaction.
- Do not bypass Cloudflare, forge clearance, drop accumulated reading time, or disable authenticated first-screen requests through this fuse.

### 4. Validation & Error Matrix
- `/topics/timings` receives an authoritative CF 403 -> mark blocked and keep later timing batches buffered without repeated sends during five minutes.
- Fresh clearance succeeds before expiry -> clear the block immediately and allow the next consolidated timing send.
- Background automatic verification succeeds -> no visible dialog/white route appears; cookies synchronize and bootstrap retry continues.
- Background verification requires interaction or times out -> do not report false success; retain the explicit foreground verification entry.
- User taps manual verification -> foreground UI remains visible and behaves as before.

### 5. Good/Base/Bad Cases
- Good: one CF rejection pauses reading telemetry, background trust recovery obtains clearance invisibly, and the next timing batch resumes after verified synchronization.
- Base: without a challenge, `ScreenTrack` keeps its existing batching, authentication, and retry behavior.
- Bad: retry `/topics/timings` every few seconds while CF is active, clear the block merely because a timer elapsed, or force a visible WebView during automatic startup recovery.

### 6. Tests Required
- Unit-test challenge detection, active block, expiry probe, and verified-clearance reset.
- Unit-test `ScreenTrack` defers sends while blocked without deleting consolidated timings.
- Assert automatic browser-trust recovery uses background presentation and explicit login/settings callers still request foreground presentation.
- Keep CF interceptor retry, Cookie boundary synchronization, browser-trust bootstrap, login, and logout regressions green.

### 7. Wrong vs Correct
#### Wrong
```dart
await CfChallengeService().showManualVerify(context, true);
await service.topicsTimings(...); // keeps probing during the challenge
```

#### Correct
```dart
final cf = CfChallengeService();
cf.markChallengeDetected();
await cf.showManualVerify(context, false);

if (!shouldDeferScreenTrackSend(
  isBusinessTrafficBlocked: cf.isBusinessTrafficBlocked,
)) {
  await service.topicsTimings(...);
}
```

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

## Scenario: WebView Session Bootstrap Retry Governance

### 1. Scope / Trigger
- Trigger: changing fingerprint plugin discovery, WebView session bootstrap success caching, failure retry timing, logout state reset, or plugin candidate preloading.

### 2. Signatures
- `WebViewSessionCookieRefreshService.ensureSynced({reason, force})`
- `WebViewSessionCookieRefreshService.markSynced(...)`
- `WebViewSessionCookieRefreshService.resetSessionState({reason})`
- `PreloadedDataService.invalidatePluginCandidates()`
- Failure cooldown: `45s -> 90s -> 3m -> 6m -> 12m -> 15m cap`.

### 3. Contracts
- A successful bootstrap is cached for the current process × login session; ordinary foreground/background requests must not restart the Headless WebView every 15 minutes.
- `force: true` may bypass success/cooldown only for explicit login or CF recovery paths; it does not create a scheduler bypass for native requests.
- Every executed failure increments the streak once. Cooldown/active-join/no-token early returns do not increment it.
- Fingerprint endpoint 404 or `phase == "discover"` invalidates preloaded plugin candidates and marks the next attempt for one fresh discover. Do not retry inside the same failure callback.
- Fresh discover omits injected candidates and loads plugin JavaScript with `cache: reload`; normal discovery keeps `force-cache`.
- Success and `markSynced` reset failure/fresh state. Logout resets success, last-attempt, failure, and fresh state before the next account session.
- Endpoint extraction may accept changing minified function identifiers, but must remain bounded by the stable `POST` plus `visitor_id` request shape.

### 4. Validation & Error Matrix
- Endpoint POST returns 404 -> finish current attempt, invalidate candidates, apply exponential cooldown, fresh-discover on the next allowed attempt.
- Plugin cannot be discovered -> same stale-candidate behavior as 404; no immediate second WebView lifecycle.
- Network/CF failure -> return the existing failure result; BrowserTrust/CF recovery remains authoritative and may later call `force`.
- Bootstrap succeeds -> sync cookies through `BoundarySyncService`, mark the login session successful, and stop ordinary repeat bootstraps.
- Logout/account switch -> next authenticated session performs a new bootstrap; old success state cannot suppress it.

### 5. Good/Base/Bad Cases
- Good: a stale endpoint causes increasingly sparse attempts and one fresh plugin fetch after cooldown.
- Base: normal login runs bootstrap once, then SPA-like app navigation reuses the session state.
- Bad: fixed 45-second retries for permanent 404, immediate retry inside `runOnController`, or clearing/replacing the CookieJar/BrowserTrust architecture.

### 6. Tests Required
- Assert the exact cooldown sequence and 15-minute cap.
- Assert fingerprint regex accepts `_`, `L`, and `$a1`, while rejecting invalid identifiers, GET requests, and missing `visitor_id` shape.
- Assert stale plugin candidates can be invalidated and rebuilt by later preload parsing.
- Keep Cookie/CF, login/logout, request-session policy, and full Flutter tests green.

### 7. Wrong vs Correct
#### Wrong
```dart
if (result.status == 404) {
  await runOnController(controller); // immediate full WebView retry
}
```

#### Correct
```dart
if (result.status == 404 || result.phase == 'discover') {
  markNextAttemptFresh();
  PreloadedDataService().invalidatePluginCandidates();
}
// The next attempt runs only after exponential cooldown.
```

## Scenario: Upload Short URL Lookup Containment

### 1. Scope / Trigger
- Trigger: changing `/uploads/lookup-urls`, `resolveShortUpload`, upload image rendering, Notion short-link replacement, or caches containing `upload://` keys.

### 2. Signatures
- `POST /uploads/lookup-urls`
- Body: `{ "short_urls": List<String> }`
- `ResolvedUploadUrl.missing`
- `DiscourseService.resolveShortUpload(String) -> Future<ResolvedUploadUrl?>`
- `DiscourseImageUtils.resolveUploadUrl(String) -> Future<String?>`

### 3. Contracts
- Same short URL shares one active Future. Different short URLs created in the same short event-loop window are sent in one POST.
- The lookup request must use the normal `DiscourseDio` interceptor chain; do not set `skipScheduler` and do not add client-side multi-retry loops.
- HTTP success plus an absent requested key means confirmed missing and may be cached as `ResolvedUploadUrl.missing`.
- Network errors, CF/auth failures, 429, malformed responses, or other thrown failures are transient: return null, do not write missing, and allow a later scheduler-governed attempt.
- Positive and negative service cache entries share a bounded LRU capacity. Logout clears them and invalidates old-session in-flight responses by generation.
- Widget-level image cache may store positive URLs and confirmed missing null entries, but must not cache transient null. Reading a null LRU entry must not remove it accidentally.
- `resolveShortUrl`, link resolution, image rendering, and Notion export must treat `missing` as unavailable; never call `mediaUrl()`/`linkUrl()` on the sentinel.

### 4. Validation & Error Matrix
- Two widgets request the same short URL synchronously -> one Future and one network key.
- Several images request different short URLs in one build -> one POST containing all keys.
- Successful response omits one key -> returned keys resolve; omitted key becomes cached missing and causes zero later requests.
- First request throws, second later succeeds -> first returns null without cache; second sends a new request and resolves.
- Logout during pending/in-flight lookup -> pending callers complete safely; old response does not populate the new session cache.

### 5. Good/Base/Bad Cases
- Good: a post with five upload images emits one lookup POST; a deleted sixth upload becomes a bounded negative cache entry.
- Base: a single uncached upload waits for the micro-batch window and sends one normal request.
- Bad: every `FutureBuilder` rebuild sends its own POST, caching all failures as null, or retrying 429 three times from the upload layer.

### 6. Tests Required
- Assert same-key Future identity/in-flight dedupe and multi-key micro-batching.
- Assert confirmed missing is cached and does not retry.
- Assert transient failure is not cached and can recover.
- Assert widget cache preserves a missing null entry and does not cache transient null.
- Assert reset completes unsent batches without a request and prevents stale-session cache writes.
- Assert Notion leaves confirmed-missing short links unchanged.

### 7. Wrong vs Correct
#### Wrong
```dart
final resolved = await service.resolveShortUrl(shortUrl);
cache[shortUrl] = resolved; // transient null becomes permanent
```

#### Correct
```dart
final resolved = await service.resolveShortUpload(shortUrl);
if (resolved == null) return null; // transient, retry later
if (resolved.isMissing) {
  cacheConfirmedMissing(shortUrl);
  return null;
}
return resolved.mediaUrl();
```

## Links And Routing

- Internal topic link extraction and internal-link routing must use compatible URL normalization.
- Regression-test malformed but common forum URLs when changing link parsing, especially referral query spacing and tree/flat topic modes.

Evidence:
- `.trellis/spec/guides/cross-layer-thinking-guide.md`
- `lib/widgets/content/discourse_html_content/`
- `lib/pages/topic_detail_page/`

## Scenario: Web-Equivalent Related Topics

### 1. Scope / Trigger
- Trigger: adding or changing the topic-detail related-topic list, final-page pagination, or the
  Discourse response fields consumed by that list.

### 2. Signatures
- `TopicDetail.relatedTopics: List<Topic>?`
- `GET /t/{topicId}/{postNumber}.json`
- `DiscourseService.getRelatedTopics(topicId, {required postNumber})`
- `selectRelatedTopics(topics, currentTopicId: ...) -> List<Topic>`

### 3. Contracts
- Consume `related_topics` only; never substitute `suggested_topics`.
- `TopicDetail.fromJson` uses `null` when the response omits `related_topics` and an empty list when
  the server explicitly returns an empty list.
- Pagination `copyWith` operations preserve an existing related list when a later page omits the
  field. Once the post stream reaches its end and the list is still null, request the final-page
  endpoint once and merge its list without making comment loading fail.
- The UI filters the current topic and blank titles, sorts by `created_at` descending, takes at most
  five entries, starts expanded, and navigates through `buildTopicDetailRoute(...)`.
- API `created_at` values are parsed with `TimeUtils.parseUtcTime()`; no direct `DateTime.parse`.

### 4. Validation & Error Matrix
- Missing field -> preserve existing data during merges; hide the related section if no data exists.
- Explicit empty list -> store empty and hide the section without retrying.
- Final-page request failure -> keep loaded posts and hide only the related section.
- Duplicate/current/blank items -> filter before sorting and truncating.
- Equal or missing dates -> deterministic ID tie-breaker; null dates sort last.

### 5. Good/Base/Bad Cases
- Good: initial topic data carries related topics, or the provider fills them after the final page,
  while the footer remains a pure rendering consumer.
- Base: a short topic reaches the end in its initial response and already has an explicit empty list.
- Bad: display `suggested_topics`, request a cloud search endpoint, or replace a known list with null
  from an intermediate `/posts.json` response.

### 6. Tests Required
- Model tests for omitted/empty/valid fields and `copyWith` preservation.
- Service test for the exact final-page URL and `related_topics`/`suggested_topics` separation.
- Provider integration test for initial data -> final page -> related merge and failure isolation.
- Widget tests for filtering, order, five-item cap, default expansion, empty hiding, and route tap.

### 7. Wrong vs Correct
#### Wrong
```dart
final suggestions = data['suggested_topics'] ?? data['related_topics'];
detail = TopicDetail.fromJson(data); // later page can erase old related data
```

#### Correct
```dart
if (data.containsKey('related_topics')) {
  detail = detail.copyWith(relatedTopics: parseRelatedTopics(data));
}
```

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

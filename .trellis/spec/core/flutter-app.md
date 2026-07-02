# Flutter App Guidelines

## Layer Boundaries

- UI pages live in `lib/pages/`; reusable UI belongs in `lib/widgets/`.
- Riverpod providers live in `lib/providers/` and should own state orchestration rather than pushing business logic into widgets.
- Business/network/storage behavior belongs in `lib/services/`, `lib/models/`, and focused local packages.
- Keep local packages independent from the app shell. If a package needs host behavior, expose a callback or extension point instead of importing app pages or services.

Evidence:
- `lib/pages/topic_detail_page/`
- `lib/providers/topic_detail_provider.dart`
- `lib/providers/topic_detail/`
- `lib/services/network/`
- `packages/`
- `.trellis/spec/guides/cross-layer-thinking-guide.md`

## UI And Interaction Changes

- Preserve stable viewport/layout dimensions during scroll-linked animations; prefer paint-level transforms, opacity, or clipping over changing scaffold slot height while dragging.
- When overlays, sheets, or routes visually exit, ensure they do not keep intercepting pointer input after the active layer below should be interactive.
- For established app surfaces, follow existing Material/Riverpod/component patterns instead of introducing a new visual framework.
- Check text overflow and hit targets on both mobile and desktop sizes when changing compact controls.
- Open in-app `TopicDetailPage` routes through `buildTopicDetailRoute(...)` from `lib/services/navigation/topic_detail_route.dart` unless the caller deliberately needs different route semantics. This preserves the same horizontal swipe-back behavior used by the home topic list for search results, internal topic links, preview dialogs, AI summaries, and multi-level topic chains.

Evidence:
- `lib/pages/topic_detail_page/`
- `lib/widgets/common/`
- `lib/services/navigation/topic_detail_route.dart`
- `.trellis/spec/guides/cross-layer-thinking-guide.md`

## State And Async Behavior

- Optional anchors, linked posts, restored scroll targets, and search hits must have terminal fallback states. Do not keep the base page in a permanent loading state while waiting for an optional target.
- Keep ordinary search, AI search, and forum-authenticated retrieval paths separate unless the task explicitly combines them.
- When adding preference-dependent behavior, centralize interpretation in a provider/helper when more than one widget needs it.
- Startup preloading that provides first-screen data must remain part of the gate that reveals the home page when the UI expects to synchronously consume that cache. Do not convert `PreloadedDataService().ensureLoaded()` into an unawaited warm-up without also changing the home topic provider contract; otherwise the app can show the home shell before `topicList` is available, trigger duplicate `/latest.json` requests, and leave the user on skeleton loading.
- Initial topic-list backfill for filtered results must not block the first visible page. Return page 0 as soon as it is processed, then append any "fill to minimum visible count" pages in the background or through normal load-more flow.
- Keep startup gates focused on first-screen hard dependencies. Non-critical work such as home excerpt warmup or decorative minimum splash delays must not block the user after the initial topic list is ready.

## Scenario: Topic Detail Preview Handoff

### 1. Scope / Trigger
- Trigger: changing home/search topic-card navigation, `TopicDetailPage` initial preview fields, restored reading position, or topic-detail initial post-window loading.

### 2. Signatures
- `buildTopicDetailRoute(topicId, initialTitle?, scrollToPostNumber?, initialTopicPreview?, initialFirstPostHtml?)`
- `TopicDetailPage.initialTopicPreview` and `initialFirstPostHtml` are first-paint preview data only.
- `scrollToPostNumber` is an explicit navigation target and must remain stronger than preview/restored state.

### 3. Contracts
- Home topic cards that already have first-post HTML must pass preview data and no `scrollToPostNumber`; comments/replies load below the stable first post.
- For home entry with no explicit target, seed the topic-detail runtime cache/provider with that preview first post and let the full detail arrive through background refresh. Do not render preview through a one-off page branch that is immediately replaced by a second full-page load path.
- Preview-driven entry from home/search may preserve the user's nested-view preference, but nested-view loading must continue rendering the preview first post while replies load below. Do not switch from preview paint to a full-page nested skeleton.
- Search result cards may pass preview data and `scrollToPostNumber`; the preview accelerates first paint but must not cancel the search hit jump.
- Restored reading state is a fallback only. Do not apply it when first-post preview is available and no explicit target was requested.
- Loading replies, post windows, boosts, likes, or metadata must not replace the visible first-post preview with a global skeleton.

### 4. Validation & Error Matrix
- Preview + no explicit target -> render first post immediately; fetch the normal first page/window for replies.
- Preview + explicit target -> render preview immediately; preserve the target post number and position when loaded, and do not swap back to a global skeleton while waiting for the target window.
- No preview + explicit target -> existing jump-target skeleton behavior is allowed.
- Target post missing after load -> use the existing unreachable-target fallback; do not silently jump to the wrong floor.

### 5. Good/Base/Bad Cases
- Good: home card preview opens with `scrollToPostNumber: null`, then replies append/load below.
- Base: search result preview opens with `scrollToPostNumber: post.postNumber` and uses the search blurb as first paint.
- Bad: treating every preview as permission to ignore `scrollToPostNumber`, or passing home `lastReadPostNumber` together with first-post preview.

### 6. Tests Required
- Assert preview without explicit target resolves to first-post loading, not restored reading position.
- Assert preview with explicit target preserves that target for search/notification-style navigation.
- Assert search post cards expose preview topic data and blank blurbs do not create fake preview HTML.
- Keep render identity tests stable across preview-to-real `post.id` handoff.

### 7. Wrong vs Correct
#### Wrong
```dart
buildTopicDetailRoute(
  topicId: topic.id,
  scrollToPostNumber: topic.lastReadPostNumber,
  initialTopicPreview: topic,
  initialFirstPostHtml: firstPostHtml,
);
```

#### Correct
```dart
buildTopicDetailRoute(
  topicId: topic.id,
  scrollToPostNumber: firstPostHtml == null ? topic.lastReadPostNumber : null,
  initialTopicPreview: topic,
  initialFirstPostHtml: firstPostHtml,
);
```

## Scenario: Topic Detail Snapshot Cache

### 1. Scope / Trigger
- Trigger: changing topic-detail reopen behavior, Riverpod family keys, route `instanceId`, post stream loading, or detail-page stale-while-revalidate caching.

### 2. Signatures
- Provider identity remains `TopicDetailParams(topicId, postNumber?, instanceId)`.
- Cache lookup key is `topicId + current username`; route `instanceId` is not part of the cache key.
- Cache service contract:
- `read(topicId, username?, targetPostNumber?) -> TopicDetailCacheEntry?`
- `write(TopicDetail, username?)`
- `writePreviewSeed(TopicDetail, username?)`
- `shouldRevalidate(entry, targetPostNumber?) -> bool`

### 3. Contracts
- Do not remove `instanceId` from `TopicDetailParams` equality/hashCode; it isolates route-local UI state, scroll targets, filters, and MessageBus ownership.
- Cache complete `TopicDetail` snapshots, including the currently loaded `postStream.posts` and `postStream.stream`, so reopen can render the same visible detail immediately.
- Use a hard TTL of 1 day for snapshot validity and a shorter soft TTL for background refresh.
- A snapshot may render immediately only when the requested `targetPostNumber` is null or already present in `postStream.posts`.
- Preview-seed snapshots are allowed only for first-post home preview handoff and must always trigger background revalidation.
- Filtered views (`summary`, author-only, top-level-only) must not overwrite the normal unfiltered topic cache.
- New replies and volatile action state must be reconciled by background refresh or MessageBus/local mutation updates; cached data is a fast first paint, not an authority for 24 hours.

### 4. Validation & Error Matrix
- Cache miss -> load via normal `getTopicDetail` path.
- Hard-expired cache -> discard and load via normal path.
- Soft-stale cache -> render snapshot, then refresh in the background.
- Target post missing from snapshot -> treat as cache miss to avoid opening the wrong scroll window.
- Background refresh failure -> keep the rendered cached detail and log/debug only; do not replace the page with a global error.
- User changes -> use a different username cache bucket; do not leak action/bookmark state between users.

### 5. Good/Base/Bad Cases
- Good: keep route `instanceId`, read a `topicId + username` snapshot, render immediately, refresh after soft TTL.
- Base: cache only in memory when full model serialization is unavailable; add disk persistence later only with explicit model/raw-JSON contracts.
- Bad: remove `instanceId` to force provider reuse, cache filtered views over normal detail, or skip refresh for a whole day.

### 6. Tests Required
- Unit-test cache hit/miss, user isolation, hard TTL, soft revalidation, target-post miss, and LRU eviction.
- Provider tests should assert cached detail renders before a stale background refresh result when a fake service is available.
- Regression-test that target-post routes do not use snapshots missing that post number.

### 7. Wrong vs Correct

#### Wrong
```dart
class TopicDetailParams {
  int get hashCode => topicId;
}
```

#### Correct
```dart
final cached = cache.read(
  arg.topicId,
  username: currentUsername,
  targetPostNumber: arg.postNumber,
);
if (cached != null) {
  unawaited(refreshIfStale());
  return cached.detail;
}
```

## Link Launching

- For external links, do not use `canLaunchUrl(uri)` as a hard gate before `launchUrl`. On Android and iOS it can return false because of package visibility/query limits even when launching would work, which makes content links appear unresponsive.
- Preferred pattern: call `launchUrl(uri, mode: LaunchMode.externalApplication)` directly, check the returned bool, catch platform errors, and show a visible failure hint when no handler is available.
- Linux.do internal links must continue through `launchContentLink` internal branches first: user links, topic links (`/t`, `/n`, `/topic`), post short links, CDK links, uploads, and same-prefix internal URLs should not be converted into generic external links.

## Scenario: External Browser Selection

### 1. Scope / Trigger
- Trigger: changing `launchExternalLink`, `launchInExternalBrowser`, reading settings for external links, or the Android `com.github.lingyan000.fluxdo/browser` MethodChannel.

### 2. Signatures
- Dart:
  - `ExternalBrowserService.listAvailableBrowsers() -> Future<List<ExternalBrowserApp>>`
  - `ExternalBrowserService.openUrl(url, packageName?) -> Future<bool>`
  - `launchInExternalBrowser(url, preferredBrowserPackageName?) -> Future<bool>`
- Android channel methods:
  - `listBrowsers() -> List<{ packageName: String, label: String }>`
  - `openInBrowser({ url: String, packageName?: String }) -> bool`

### 3. Contracts
- Persist the user selection in `pref_external_browser_package_name`; `null` means "system default browser".
- `launchExternalLink` should keep respecting `openExternalLinksInAppBrowser`; only the true external-open path may consult the selected browser package.
- Only `http/https` links should use the browser-selection path. `mailto:` and other non-browser schemes must continue through the generic external-app launcher.
- `launchContentLink` must still resolve Linux.do internal routes, uploads, short post links, and CDK links before considering any external-browser preference.
- Android should exclude this app's own package from the browser list and from fallback selection so `openInBrowser` never loops back into FluxDO.

### 4. Validation & Error Matrix
- No selected package -> try Android default browser first, then other installed browsers, then report failure.
- Selected package installed -> call native `openInBrowser` with that package and stop when native launch succeeds.
- Selected package missing/unavailable -> native layer falls back to default/other browsers; do not crash or block the link.
- Native browser channel unavailable or returns false -> fall back to `launchUrl(..., externalApplication)` and keep the existing error toast behavior.
- Non-browser scheme -> skip browser selection entirely and use the generic external-app launch path.

### 5. Good/Base/Bad Cases
- Good: user sets Chrome in Reading settings, taps an external `https://` link in a post, and FluxDO launches Chrome directly.
- Base: user keeps "system default browser", and external links behave like before.
- Bad: applying the browser preference to Linux.do internal topic links, or forcing `mailto:` links through the browser channel.

### 6. Tests Required
- Preference test: selected browser package persists and can be reset to default (`null`).
- Service test: `listAvailableBrowsers` parses native maps, and `openUrl` forwards the selected package name.
- Link-launcher regression: when Android browser selection succeeds, `launchExternalLink` must not call `UrlLauncherPlatform.launchUrl`.

### 7. Wrong vs Correct
#### Wrong
```dart
await launchUrl(uri, mode: LaunchMode.externalApplication);
```

#### Correct
```dart
await launchInExternalBrowser(
  uri.toString(),
  preferredBrowserPackageName: prefs.externalBrowserPackageName,
);
```

Evidence:
- `lib/providers/topic_detail/`
- `lib/providers/search_ai_chat_provider.dart`
- `lib/utils/link_launcher.dart`
- `.trellis/spec/guides/code-reuse-thinking-guide.md`
- `.trellis/spec/guides/cross-layer-thinking-guide.md`

## Build And Release Verification

- APK release artifacts are normally produced by GitHub Actions, not by local desktop builds.
- Local Windows workspaces can fail `flutter build apk` before project compilation because of non-ASCII workspace paths, missing Visual Studio C++ `link.exe` for Rust build scripts, Android SDK/NDK differences, or local signing file layout.
- For APK packaging fixes, use local `flutter analyze`, targeted tests, and the closest build smoke test the machine can support; treat GitHub Actions as the authoritative APK packaging verification.
- Do not add project configuration such as `android.overridePathCheck=true` only to make one local Windows path build. Prefer fixing repository code and validating through Actions.

Evidence:
- `.github/workflows/build.yaml`
- `android/`
- `core/doh_proxy/`

## Local Packages

- Avoid adding app-shell imports to reusable packages under `packages/`.
- Preserve package API boundaries; inject host-specific widgets or navigation behavior from the app layer.
- Run package-local checks when changing a package with its own `pubspec.yaml`.

Evidence:
- `packages/ai_model_manager/`
- `packages/enhanced_cookie_jar/`
- `packages/flutter_inappwebview_linux/`
- `.trellis/spec/guides/cross-layer-thinking-guide.md`

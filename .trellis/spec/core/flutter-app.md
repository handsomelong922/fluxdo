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
- Bottom navigation pages that are not currently active must not be eagerly mounted if their build path can watch providers that issue network requests. Use lazy mounting or an explicit `isActive` gate so default home startup does not trigger profile, bookmarks, messages, or other non-first-screen requests. Account-authenticated home preload, Cookie/CSRF/CF trust, and `data-preloaded.topicList` remain first-screen dependencies and must not be delayed by this rule.
- Home topic excerpts load asynchronously inside a `NestedScrollView`; keep the final card height adaptive to the real excerpt content and the user-selected max-line setting. Do not force every card into the same fixed excerpt height just to suppress scroll jank. If loading-time layout updates need smoothing, prefer isolating rebuild scope or temporarily pausing excerpt fetch/render work during the active drag.
- Scroll-linked feedback providers must publish only the minimum state their consumers need. If the selected tab icon only cares about "at top / below threshold / above threshold", do not emit per-pixel provider updates on every drag frame; quantize the state before writing to Riverpod.
- When scroll-linked providers intentionally publish quantized `0/1` visibility for performance, the consuming UI must still animate the transition with transform/opacity (for example `AnimatedSlide`, `AnimatedOpacity`, or a mobile-only `TweenAnimationBuilder`). Do not render quantized visibility directly as an instant `Opacity`/`FractionalTranslation` jump.
- Startup request ranking and other performance diagnostics must not depend on verbose release-mode disk logging. Keep ranking/session inspection in memory when possible, and gate high-frequency request/cookie/WebView trace persistence behind explicit developer mode or warning/error paths.
- List providers that support sort/filter switching plus pagination must treat in-flight page requests as generation-scoped. A stale page or stale sort response must not write old `roots/items/sort/page` back over the current state.

## Scenario: Async Sorted List Provider Requests

### 1. Scope / Trigger
- Trigger: changing Riverpod providers that combine sort/filter selection, pagination, and async service calls, especially visible scroll lists such as topic detail nested replies.

### 2. Signatures
- `Future<void> changeSort(String newSort)`
- `Future<void> loadMoreRoots()`
- Equivalent provider methods that mutate `items`, `sort/filter`, `currentPage`, `isLoadingMore`, or refresh flags after an awaited request.

### 3. Contracts
- Capture the request generation, selected sort/filter, and source page before awaiting.
- Increment the root-list generation whenever a sort/filter reset invalidates previous pages.
- After await, read the latest provider state and apply the response only if generation, sort/filter, and source page still match.
- Use the latest state as the merge base, not the stale `current` captured before await.
- When a sort/filter reset starts, clear stale pagination flags such as `isLoadingMore` if the old page request has been invalidated.

### 4. Validation & Error Matrix
- Old page response returns after sort changes -> discard it; current sort and roots/items remain unchanged.
- Earlier sort response returns after a later sort was selected -> discard it; later selection remains visible.
- Active page request fails after generation changes -> ignore the failure for state rollback; do not restore old items.
- Current page request fails without generation change -> clear the loading flag and keep the latest visible items.

### 5. Good/Base/Bad Cases
- Good: `loadMoreRoots()` captures generation and page, then appends to `latest.roots` only when still current.
- Base: one sort request at a time may still race with old pagination, so generation checks are required.
- Bad: `await service.fetch(...); state = AsyncValue.data(current.copyWith(...))` where `current` was captured before the user changed sort/filter.

### 6. Tests Required
- Regression-test stale load-more response after a sort/filter change.
- Regression-test fast sort/filter switching where the earlier response returns last.
- Assert loading flags are not left stuck after stale responses are ignored.

### 7. Wrong vs Correct
#### Wrong
```dart
final current = state.value;
final response = await service.getNestedRoots(sort: current.sort, page: nextPage);
state = AsyncValue.data(
  current.copyWith(roots: [...current.roots, ...response.roots]),
);
```

#### Correct
```dart
final generation = _rootRequestGeneration;
final requestSort = current.sort;
final requestPage = current.currentPage;
final response = await service.getNestedRoots(sort: requestSort, page: requestPage + 1);
final latest = state.value;
if (latest == null ||
    generation != _rootRequestGeneration ||
    latest.sort != requestSort ||
    latest.currentPage != requestPage) {
  return;
}
state = AsyncValue.data(
  latest.copyWith(roots: [...latest.roots, ...response.roots]),
);
```

## Scenario: Scroll-Linked Navigation Feedback And Diagnostic Logging

### 1. Scope / Trigger
- Trigger: changing `navScrollProgressProvider` publishers/consumers, bottom-navigation selected-icon feedback, startup request ranking, or request/cookie/WebView diagnostics that can fire during active scrolling or page bootstrap.

### 2. Signatures
- `double collapseNavScrollProgress(double rawProgress)`
- `WidgetRef.publishNavScrollProgress(String id, double rawProgress)`
- `AppLogSettingsService.initialize(SharedPreferences prefs)`
- `AppLogSettingsService.setEnabled(bool value)`
- `AppLogSettingsService.setMaxEntries(int value)`
- `RuntimeLogSettings.configure({required bool developerModeEnabled})`
- `RuntimeLogSettings.shouldPersistRequestLog({required String level, required bool isSilent})`
- `RuntimeLogSettings.shouldPersistDiagnosticEvent({required String level})`

### 3. Contracts
- `navScrollProgressProvider` is a feedback-state channel, not a telemetry stream. Publishers must quantize values to:
  - `0.0` -> at top
  - `1.0` -> left the top but still below `navScrollIconThreshold`
  - `navScrollIconThreshold` -> crossed the action-icon threshold
- Selected navigation icons should watch only whether the threshold is crossed, not raw pixel deltas.
- `StartupRequestRecorder` remains the authoritative in-memory source for launch request ranking; ranking must keep working even when persistent request logs are reduced.
- Silent/background request logs may still be recorded in memory for ranking, but must not be persisted to JSONL by default in normal mode.
- High-frequency cookie/session/WebView lifecycle diagnostics must default to warning/error-only persistence. Full verbose persistence requires explicit developer mode.
- App-log user settings live in shared preferences:
  - `pref_app_logs_enabled`
  - `pref_app_logs_max_entries`
- Turning app-log recording off must stop both persistent app-log writes and startup-request ranking collection. Re-enabling should resume both with the currently selected retention limit.
- The selectable retention limit must stay within `50..300` and be quantized in 25-entry steps before applying it to file retention and startup ranking memory buffers.

### 4. Validation & Error Matrix
- Scroll stays below threshold -> provider state remains `1.0`; selected icon does not switch to the action glyph.
- Scroll crosses threshold -> provider state becomes `navScrollIconThreshold`; selected icon may switch.
- Scroll returns to top -> provider state returns to `0.0`.
- Developer mode off + silent info request -> request may appear in in-memory ranking, but JSONL write is skipped.
- Developer mode off + warning/error diagnostic -> persistent log is still written.
- Developer mode on -> verbose request/cookie/WebView diagnostics persist as before.
- App-log recording off -> `StartupRequestRecorder.records` stays empty, and `LogWriter` skips new JSONL writes.
- App-log retention limit lowered -> both the in-memory startup ranking buffer and `app_log.jsonl` must trim older entries down to the new limit.

### 5. Good/Base/Bad Cases
- Good: list scrolling flips navigation feedback only on top/threshold transitions, while startup ranking still shows silent excerpt requests in-memory.
- Base: normal browsing persists only actionable warnings/errors, and developers can opt into full traces when investigating session issues.
- Bad: every scroll frame writes new pixel values into `navScrollProgressProvider`, or release browsing flushes every silent request / cookie trace to disk.

### 6. Tests Required
- Unit-test `collapseNavScrollProgress()` for top / below-threshold / above-threshold quantization.
- Unit-test `RuntimeLogSettings` for silent-request suppression and warning/error retention.
- Unit-test that disabling app logs suppresses both persistent request/diagnostic logging and startup ranking retention.
- Unit-test that startup ranking trims to the configured max-entry limit.
- Keep startup request recorder tests proving in-memory ranking still records request timing independently from persistent logs.

### 7. Wrong vs Correct
#### Wrong
```dart
ref.read(navScrollProgressProvider(id).notifier).state = scrollController.offset;
LogWriter.instance.write({
  'level': 'info',
  'type': 'cookie_trace',
  'message': 'every silent request persisted',
});
```

#### Correct
```dart
ref.publishNavScrollProgress(id, scrollController.offset);
if (RuntimeLogSettings.shouldPersistRequestLog(
  level: level,
  isSilent: isSilent,
)) {
  LogWriter.instance.write(entry);
}
```

#### Correct
```dart
await AppLogSettingsService.instance.setEnabled(false);
await AppLogSettingsService.instance.setMaxEntries(150);
```

## Scenario: Topic Detail Deferred Media Loading During Active Scroll

### 1. Scope / Trigger
- Trigger: changing topic-detail long-post image rendering, `LazyImage`, `d-image-grid`, `LazyLoadScope`, or scroll-notification handling in `TopicPostList`.

### 2. Signatures
- `class LazyLoadPauseScope extends InheritedNotifier<ValueListenable<bool>>`
- `LazyImage(...)`
- `_GridImageTileState._scheduleLoadIfReady()`
- `_TopicPostListState._resumeAutoLoadReplies()`

### 3. Contracts
- Topic-detail descendants may expose a `LazyLoadPauseScope` whose notifier is `true` while the list is actively scrolling and returns to `false` only after the existing mobile idle delay.
- Visibility-triggered first loads for post images must check the pause scope before calling `setState(() => _shouldLoad = true)`.
- When the pause scope flips back to `false`, topic detail should call `VisibilityDetectorController.instance.notifyNow()` so currently visible placeholders load immediately instead of waiting for the mobile detector interval.
- Standalone post images with stable width/height metadata should prefer the same lazy-loading path as gallery/grid images instead of starting network/decode work the moment the post widget builds.

### 4. Validation & Error Matrix
- Visible image enters viewport while pause scope is `true` -> keep placeholder only; do not start the first image load.
- Same image remains visible after pause scope becomes `false` -> load starts on the next frame without requiring another manual scroll.
- Topic detail has no pause scope ancestor -> existing lazy-image behavior continues; do not block image loading globally.
- Scroll ends on mobile with throttled `VisibilityDetector` updates -> `notifyNow()` flushes visible detectors so image loading does not lag for up to the global interval.

### 5. Good/Base/Bad Cases
- Good: fast-flinging through an image-heavy long topic keeps placeholders during the drag, then visible images start decoding only after the list settles.
- Base: off-topic surfaces without the pause scope still load visible images as before.
- Bad: every `VisibilityDetector` callback starts image decoding during active drag, or visible placeholders remain blank for a long time after scrolling stops because no detector flush occurs.

### 6. Tests Required
- Widget-test that `LazyImage` stays unloaded while a visible pause scope is `true`.
- Widget-test that the same `LazyImage` loads once the pause scope flips to `false`.
- Keep topic-detail scroll performance tests green to ensure the scroll pipeline still compiles with the added pause scope.

### 7. Wrong vs Correct
#### Wrong
```dart
onVisibilityChanged: (info) {
  if (info.visibleFraction > 0) {
    _triggerLoad();
  }
}
```

#### Correct
```dart
onVisibilityChanged: (info) {
  _isVisible = info.visibleFraction > 0;
  _scheduleLoadIfReady();
}
```

## Scenario: Nested Reply Auto-Load During Active Scroll

### 1. Scope / Trigger
- Trigger: changing `NestedPostList`, `NestedPostCard`, nested reply expansion state, or any automatic child-reply loading in topic detail.

### 2. Signatures
- `ValueListenable<bool>? autoLoadChildrenPausedListenable`
- `_NestedPostCardState._scheduleAutoLoadChildren()`
- `_NestedPostListState._setAutoLoadChildrenPaused(bool paused)`

### 3. Contracts
- Automatic child-reply loading must pause while the nested topic list is actively scrolling.
- Resume automatic child-reply loading only after the same mobile/desktop idle delay style used for topic-detail media/reply auto-load.
- Automatic child-reply loading must enqueue through the shared reply prefetch queue instead of launching every visible card immediately in parallel.
- Queued automatic child loads must be canceled when the card collapses, the pause flag turns back on, the route disposes, or the card identity changes.
- Manual user actions such as tapping expand/load-more must remain immediate and must not be blocked by the auto-load pause flag.
- Pass the pause listenable through recursive `NestedPostCard` children so deep reply trees follow the same rule.

### 4. Validation & Error Matrix
- Scroll start/update -> visible nested cards do not start first automatic child loads.
- Scroll end + idle delay -> cards that still need children may schedule their automatic load.
- Scroll end with multiple visible expandable cards -> automatic child requests run sequentially, and list height grows in smaller steps instead of one burst.
- User taps expand while paused -> load runs immediately because it is an explicit action.
- Route pop / card dispose while queued -> pending automatic child load is canceled and must not keep fetching in the background.
- Pause listenable missing, such as in a bottom sheet -> existing behavior continues.

### 5. Good/Base/Bad Cases
- Good: long nested reply trees render and scroll without starting a chain of child-fetch/setState work under the user's finger.
- Base: root pagination can still be initiated by the list load-more policy near the bottom.
- Bad: every newly built nested card calls `loadChildren()` during a fling through a large reply tree.

### 6. Tests Required
- Regression-test the pause/listenable helper or widget behavior when a lightweight harness is available.
- Keep shared prefetch-queue cancellation tests green because nested child auto-load now relies on the same sequential queue semantics.
- Keep nested provider stale-response tests green.
- Keep topic-detail scroll performance tests green.

### 7. Wrong vs Correct
#### Wrong
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  _loadChildren();
});
```

#### Correct
```dart
if (_autoLoadChildrenPaused) return;
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!_autoLoadChildrenPaused) {
    _loadChildren();
  }
});
```

## Scenario: Home Topic Excerpt Background Prefetch While Detail Routes Are Visible

### 1. Scope / Trigger
- Trigger: changing `HomeTopicExcerptLoader`, topic-list excerpt warmup, home cards, or full-screen `TopicDetailPage` route lifecycle.

### 2. Signatures
- `HomeTopicExcerptPauseController.acquire(Object token)`
- `HomeTopicExcerptPauseController.release(Object token)`
- `HomeTopicExcerptLoader.setPaused(bool paused)`
- `homeTopicExcerptPausedProvider`

### 3. Contracts
- Background home excerpt preview requests must pause while a full-screen topic-detail route is visible above the home list.
- Pause state must be token-based, not a single bool flip, so stacked topic-detail routes and home-list scroll pauses can coexist safely.
- Releasing one pause source must not resume loader activity while another pause source still holds a token.
- While paused, finished excerpt HTML may be buffered but must not be applied to hidden home cards until the pause state is cleared.
- Embedded/master-detail topic panes must not pause the home excerpt loader globally just because the detail pane is visible beside the list.

### 4. Validation & Error Matrix
- First topic-detail push over home -> excerpt loader pauses and home cards stop issuing new `/t/:id/1.json` preview requests.
- Nested topic-detail push -> second token is added; popping only the top route keeps excerpt loading paused until the lower detail route becomes hidden or disposes.
- Home list scroll pause + topic-detail pause coexist -> releasing only one source keeps `homeTopicExcerptPausedProvider` true.
- Final token release -> loader resumes and any buffered excerpt HTML may render on home cards.

### 5. Good/Base/Bad Cases
- Good: entering a long topic stops hidden-home excerpt warmup so topic detail is not competing with dozens of low-priority first-post preview fetches.
- Base: when no topic-detail route is visible, existing home excerpt pause/resume behavior during active list scroll stays the same.
- Bad: one route or timer blindly sets the global pause bool to false while another route still expects excerpt warmup to remain suspended.

### 6. Tests Required
- Unit-test token acquire/release ordering so the loader stays paused until the final token releases.
- Keep home excerpt loader queue tests green to ensure paused requests still resume correctly afterward.

### 7. Wrong vs Correct
#### Wrong
```dart
ref.read(homeTopicExcerptLoaderProvider).setPaused(false);
ref.read(homeTopicExcerptPausedProvider.notifier).state = false;
```

#### Correct
```dart
final pauseController = ref.read(homeTopicExcerptPauseControllerProvider);
pauseController.acquire(routeToken);
pauseController.release(routeToken);
```

## Scenario: Topic Post Author Header Labels

### 1. Scope / Trigger
- Trigger: changing `PostHeader`, `PostHeaderSection`, first-post preview handoff, nested OP rendering, or `Post.fromJson` author metadata.

### 2. Signatures
- `Post.trustLevel`
- `resolvePostTrustLevel({int? trustLevel, String? userTitle})`
- `PostItem(useUsernameAsPrimaryLabel: true)` for OP/first-post paths that should avoid display-name work.

### 3. Contracts
- OP/first-post entries that use cached preview data should render `@username` as the primary bold author label instead of the custom display name.
- Trust-level UI must use already available post payload data (`trust_level`) or known `user_title` mappings; do not fetch user profile data just to draw the author header.
- Known trust-level titles such as `活跃用户` / `Regular` must render as compact `LV3` style labels, not as raw localized words.
- Unknown non-level custom titles may continue to render as text to preserve existing behavior.

### 4. Validation & Error Matrix
- `trust_level: 3` + `user_title: 活跃用户` -> display `LV3` and prefer the numeric API field.
- `user_title: 活跃用户` without `trust_level` -> display `LV3`.
- unknown custom title -> keep the title text.
- nested topic OP path -> pass `useUsernameAsPrimaryLabel: true`, matching the flat topic-detail first-post path.

### 5. Good/Base/Bad Cases
- Good: screenshot-style OP row shows bold `@username` with `LV3` underneath and no duplicated nickname line.
- Base: normal replies may still show display name primary plus `@username` secondary.
- Bad: opening a topic triggers extra user-detail requests just to replace the header label.

### 6. Tests Required
- Widget-test primary username mode and trust-level badge rendering.
- Unit-test trust-level title mapping and `Post.fromJson`/`copyWith` retention.

### 7. Wrong vs Correct
#### Wrong
```dart
Text(post.userTitle ?? '')
```

#### Correct
```dart
final level = resolvePostTrustLevel(
  trustLevel: post.trustLevel,
  userTitle: post.userTitle,
);
```

## Scenario: Image Viewer Loading Preview Must Remain Interactive

### 1. Scope / Trigger
- Trigger: changing `ImageViewerPage`, `ExtendedImage.loadStateChanged`, thumbnail preview handoff, or full-image loading UX inside the viewer.

### 2. Signatures
- `bool shouldUseInteractiveLoadingPreview({required String imageUrl, String? thumbnailUrl})`
- `_ImageViewerPageState._buildInteractiveLoadingPreview(...)`
- `ExtendedImage.loadStateChanged`

### 3. Contracts
- When `thumbnailUrl` exists, is non-empty, and differs from the original `imageUrl`, the image viewer loading state must render a gesture-capable preview instead of a plain `Image`.
- The preview must keep the same zoom/double-tap gesture affordances as the final viewer path and must still target the original `imageUrl` for double-tap zoom heuristics.
- If no distinct thumbnail is available, the existing loading spinner path is allowed.

### 4. Validation & Error Matrix
- Distinct thumbnail available + full image still loading -> preview is visible and accepts pinch/double-tap gestures.
- Thumbnail missing/blank/same as original -> fall back to the normal loading UI; do not try to build a duplicate preview.
- Preview load fails -> use the existing fallback/error path instead of hanging on a blank frame.

### 5. Good/Base/Bad Cases
- Good: user opens a large image and can immediately pinch the blurry preview while the original continues loading.
- Base: images without a separate thumbnail keep the normal loading indicator.
- Bad: loading state swaps in a plain `Image` that ignores all gestures until the original fully loads.

### 6. Tests Required
- Unit-test `shouldUseInteractiveLoadingPreview()` for distinct, identical, blank, and null thumbnail cases.

### 7. Wrong vs Correct
#### Wrong
```dart
return Image(
  image: discourseImageProvider(widget.thumbnailUrl!),
  fit: BoxFit.contain,
);
```

#### Correct
```dart
return _buildInteractiveLoadingPreview(
  previewUrl: widget.thumbnailUrl!,
  imageUrl: widget.imageUrl!,
  inPageView: false,
  heroTag: widget.heroTag,
);
```

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
- For this workspace/user, local APK and Windows packaging should be treated as unavailable for final verification. Do not ask the user to rely on local packaging here; use GitHub Actions as the authoritative packaging path unless the user says that environment changed.
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

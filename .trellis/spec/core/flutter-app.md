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

## Scenario: Stable User Profile Summary Geometry

### 1. Scope / Trigger
- Trigger: changing the expanded user-profile header, follow/follower counts, summary statistics, or the transition from profile loading to loaded content.

### 2. Signatures
- `UserProfileStatsArea(summary: UserSummary?, isSummaryLoading: bool, ...)`
- Fixed geometry: one follow/follower row plus one likes/views/topics/replies row inside a 50 logical-pixel area.

### 3. Contracts
- Once the base user profile is available, always mount the two-row stats area even when summary is loading or failed.
- Loading and failure placeholders use the same outer dimensions as the final values; summary arrival must not move the avatar, name, last-seen text, tabs, or following content.
- Compact labels remain single-line on narrow screens through scale-down behavior rather than wrapping and increasing height.
- Follow/follower tap targets and final-value tooltips remain usable; placeholders are visual only and do not invent click actions.
- Do not delay the whole profile page until summary completes merely to avoid layout shift.

### 4. Validation & Error Matrix
- User loads first, summary later -> page shell appears and the widget below the stats area keeps the same vertical position.
- Summary fails -> the reserved area remains; no collapse or second layout jump.
- Narrow width or longer localized labels -> rows scale down without overflow or extra height.
- Follow/follower counts are available before summary -> their normal tap behavior remains active.

### 5. Good/Base/Bad Cases
- Good: a fixed wrapper switches only the row contents from placeholders to real values.
- Base: the full-page skeleton may still be used while the base user object is unavailable.
- Bad: `if (summary != null) UserStats(...)`, which inserts the whole block late and shifts the header.

### 6. Tests Required
- Widget-test the vertical position of content after the stats area before and after summary completion.
- Widget-test narrow-width single-line behavior and follow/follower taps.
- Keep profile request-option tests separate from layout tests so network and geometry failures are independently diagnosable.

### 7. Wrong vs Correct
#### Wrong
```dart
if (summary != null) UserStats(summary: summary),
```

#### Correct
```dart
UserProfileStatsArea(
  summary: summary,
  isSummaryLoading: isSummaryLoading,
),
```

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
- `PerformanceDiagnosticsService.shouldSampleFrame(severity, now, lastSampleAt)`
- `PerformanceDiagnosticsService.readLogs()` / `clear()` / `setEnabled(false)`

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
- Performance diagnostics must aggregate every frame into `frame_window`, but detailed slow-frame JSONL entries must be severity-rate-limited. Frozen frames are never sampled out.
- Ordinary jank entries keep route/cache/component attribution but do not duplicate the full recent-event queue; severe/frozen frames, UI-isolate stalls, and manual markers may include recent events.
- High-frequency performance events must be appended in bounded batches rather than opening/appending the trace file once per event. `readLogs()` must flush queued entries before reading.
- Disabling diagnostics must close the event ingress before awaiting pending writes. Clearing diagnostics must suppress writes during the clear boundary and then emit only the new `cleared` marker.

### 4. Validation & Error Matrix
- Scroll stays below threshold -> provider state remains `1.0`; selected icon does not switch to the action glyph.
- Scroll crosses threshold -> provider state becomes `navScrollIconThreshold`; selected icon may switch.
- Scroll returns to top -> provider state returns to `0.0`.
- Developer mode off + silent info request -> request may appear in in-memory ranking, but JSONL write is skipped.
- Developer mode off + warning/error diagnostic -> persistent log is still written.
- Developer mode on -> verbose request/cookie/WebView diagnostics persist as before.
- App-log recording off -> `StartupRequestRecorder.records` stays empty, and `LogWriter` skips new JSONL writes.
- App-log retention limit lowered -> both the in-memory startup ranking buffer and `app_log.jsonl` must trim older entries down to the new limit.
- Repeated slow/jank frames inside their severity cooldown -> window counters still increase, but duplicate detailed entries are skipped.
- Frozen frame inside any cooldown -> detailed entry is still written.
- Share immediately after scrolling -> queued trace lines are flushed before the exported file is read.
- Disable/clear while frame callbacks are active -> no late pre-boundary event is appended after the operation completes.

### 5. Good/Base/Bad Cases
- Good: list scrolling flips navigation feedback only on top/threshold transitions, while startup ranking still shows silent excerpt requests in-memory.
- Base: normal browsing persists only actionable warnings/errors, and developers can opt into full traces when investigating session issues.
- Bad: every scroll frame writes new pixel values into `navScrollProgressProvider`, or release browsing flushes every silent request / cookie trace to disk.
- Bad: every slow frame JSON-encodes a recent-event snapshot and performs an individual file append, causing the diagnostic tool to amplify the jank it measures.

### 6. Tests Required
- Unit-test `collapseNavScrollProgress()` for top / below-threshold / above-threshold quantization.
- Unit-test `RuntimeLogSettings` for silent-request suppression and warning/error retention.
- Unit-test that disabling app logs suppresses both persistent request/diagnostic logging and startup ranking retention.
- Unit-test that startup ranking trims to the configured max-entry limit.
- Keep startup request recorder tests proving in-memory ranking still records request timing independently from persistent logs.
- Unit-test slow-frame sampling cooldowns, including unconditional frozen-frame retention.
- Regression-test that share/read flushes queued trace entries and that disable/clear cannot leak late queued writes across their boundary.

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

#### Wrong
```dart
for (final timing in timings) {
  writeJsonLine(buildDetailedFrameEntry(timing, includeRecentEvents: true));
}
```

#### Correct
```dart
if (PerformanceDiagnosticsService.shouldSampleFrame(
  severity: severity,
  now: now,
  lastSampleAt: lastSampleAt,
)) {
  queueTraceLine(buildDetailedFrameEntry(timing));
}
```

## Scenario: Scroll-Busy Media And Background Work Coordination

### 1. Scope / Trigger
- Trigger: changing standalone post images, image grids, AVIF animation, global scroll notifications, or the persistent CF Headless WebView.

### 2. Signatures
- `ScrollBusySignal.touch()` / `ScrollBusySignal.isBusy`
- `constrainImageDecodeSize(...) -> ImageDecodeSize`
- `ResizeImage(..., policy: ResizeImagePolicy.fit)`
- `decideCfWebViewScrollPauseAction(...) -> CfWebViewScrollPauseAction`
- `InAppWebViewController.pause()` / `resume()` on Android only

### 3. Contracts
- The app root may call `ScrollBusySignal.touch()` on scroll start/update, but the signal must remain timestamp-only: no listeners, provider writes, or widget rebuilds on the hot path.
- Standalone topic images must mount a normal Flutter `Image` without a per-image `VisibilityDetector`; rely on sliver virtualization and Flutter's scroll-aware image provider behavior.
- Decode constraints use the rendered logical size times DPR and cap both width and height/long edge. The full-screen image viewer keeps the original provider path.
- Standalone images, gallery tiles, and animated media own an image-local `RepaintBoundary`; an unknown-size image may remember its decoded aspect ratio to stabilize recycle/rebuild geometry.
- AVIF animation freezes the current frame while `ScrollBusySignal.isBusy` and resumes decoding after the busy window; do not replace the current frame with a placeholder.
- The CF WebView ticker runs only on Android after the initial Turnstile request has appeared. Pause only while scrolling is busy, `_initialTimer == null`, and no RC request is active; an active RC request or scroll idle must resume it.
- CF pause/resume transitions are serialized and generation/controller scoped. Stop, app-background pause, disposal, startup failure, and a new WebView generation cancel the ticker and clear the scroll-pause state.
- A failed pause keeps the internal state resumed. A failed resume keeps the state paused so the next ticker retries; never mark a failed resume as completed.
- Do not add `ImagePaintGate`, scroll anchoring, or a transition-time body-hiding branch through this contract.

### 4. Validation & Error Matrix
- Fast scroll through large standalone images -> no detector callback churn; decode size stays within both caps.
- Open the image viewer -> original/full-resolution provider remains available.
- Scroll starts during AVIF playback -> current frame remains painted and no new animation frame is decoded until idle.
- Non-Android CF service -> no WebView pause/resume platform call.
- Initial Turnstile or active RC request -> CF WebView remains resumed even while scrolling.
- Resume throws -> state remains retryable as paused; stop/dispose still clears it without depending on a successful resume.

### 5. Good/Base/Bad Cases
- Good: one root scroll timestamp coordinates AVIF and CF background work, while image widgets stay virtualized and repaint-isolated.
- Base: non-topic images may keep their established loading mechanism when they are not in the long scrolling post pipeline.
- Bad: one `VisibilityDetector` per standalone post image, width-only decode caps for long screenshots, or calling WebView pause/resume directly from every scroll notification.

### 6. Tests Required
- Widget-test that `LazyImage` mounts an `Image` without a `VisibilityDetector` and remembers decoded aspect ratio.
- Unit-test decode width/height caps and `ScrollBusySignal` busy/idle windows.
- Keep image-viewer tests proving the original-image path and interactive preview behavior.
- Unit-test CF decisions for non-Android, initial challenge, active RC, busy pause, idle resume, and already-matching states.
- Run CF challenge, WebView session, and cookie-boundary regressions after changing the ticker lifecycle.

### 7. Wrong vs Correct
#### Wrong
```dart
VisibilityDetector(
  onVisibilityChanged: (info) => setState(() => shouldLoad = info.visibleFraction > 0),
  child: Image(image: provider),
);
```

#### Correct
```dart
RepaintBoundary(
  child: Image(
    image: ResizeImage(provider, width: targetWidth, height: targetHeight),
  ),
);
```

## Scenario: Topic Post Progressive Materialization

### 1. Scope / Trigger
- Trigger: changing `TopicPostList` first mount, append/prepend pagination, long-post segmentation, parse warm-up, or the center post used for jump navigation.

### 2. Signatures
- `detectTopicPostGrowth(oldPostIds, newPostIds) -> TopicPostGrowth?`
- `planTopicPostPagingMaterialization(...) -> TopicPostMaterializationPlan?`
- `initialAfterMaterializationCap(segmentPostIds, centerScrollIndex)`
- `initialTopicPostMaterialization(segmentPostIds, centerScrollIndex) -> TopicPostInitialMaterialization`
- `didTopicPostCenterChange(...) -> bool`
- `materializedSegmentCount(total, cap) -> int`
- `shouldAdvanceTopicPostMaterialization(isScrollActive, hasPendingMaterialization) -> bool`

### 3. Contracts
- First mount may cap both remote sides and grow by four segments per frame, but the center post's complete segment run plus four nearby after-segments must be present on the first frame.
- This complete-center rule protects the home-detail preview handoff: `initialTopicPreview`, `_initialPreviewDetail`, and `mergeTopicDetailWithInitialPreview` must still show the full OP immediately while replies continue loading.
- Restart a cap only for a pure append or pure prepend with at least eight new segments. Gap fill, replacement, and small growth keep the previous all-at-once behavior.
- A paging cap starts no lower than the previously loaded side plus four, so already materialized elements are never removed.
- Prepend index shifts that retain the same center `postNumber` do not count as a center change. An explicit same-topic center change must reset initialization and rebuild finite caps around the new center; never release caps to `null`, because a large loaded topic can then build dozens of distant floors and images in one frame.
- New-page parse warm-up is generation-scoped and scheduled at idle priority. Long posts reuse `HtmlChunkCache`/`LongPostRenderData`; short posts may warm `GalleryInfo`. Warm-up failure must not affect normal rendering fallback.
- Active drag/ballistic scrolling pauses cap advancement. An already scheduled post-frame callback must return without `setState`; `ScrollEndNotification` resumes from the existing cap rather than resetting it.
- Do not apply this cap to nested/tree lists or replace the existing jump, search, MessageBus, gap, and load-more provider semantics.

### 4. Validation & Error Matrix
- Long OP split into more than four segments -> every OP segment is visible on first paint, then nearby replies materialize progressively.
- Tail append -> only the after cap restarts; old visible elements keep identity.
- Head prepend -> only the before cap restarts and the logical center remains the same post.
- Middle gap fill or whole-window replacement -> no paging plan is created.
- Explicit local jump while caps are active -> the new target's complete segment run and nearby segments render immediately, while distant elements rematerialize progressively.
- A second page arrives during warm-up -> the previous generation exits without writing stale work.
- Scroll starts while caps remain -> visible/materialized segments stay unchanged and no expansion rebuild runs until scroll end.
- Scroll ends with a pending cap -> progressive growth resumes from the prior cap automatically.

### 5. Good/Base/Bad Cases
- Good: the preview OP paints fully, pagination adds distant reply segments over several frames, and cached parsing reduces build-frame work.
- Base: a small page or gap fill uses normal sliver virtualization without an extra materialization cap.
- Bad: a fixed four-segment after cap truncates a long OP, or prepend index movement is mistaken for a new center target.
- Bad: cap advancement calls `setState` every frame while the user's finger or fling is moving the list.
- Bad: setting both caps to `null` on a center change, which turns a target jump into an all-loaded-floor build burst.

### 6. Tests Required
- Unit-test append, prepend, gap, replacement, small-growth, complete-center, cap clamp, prepend center shift, explicit center change, and finite initial caps around the new center.
- Unit-test the scroll-active materialization gate for paused, resumed, and no-pending states.
- Keep topic preview, jump-target, render-identity, scroll-performance, long-post cache, and MessageBus batching tests green.
- Verify tree view and explicit search targets still use their existing navigation semantics.

### 7. Wrong vs Correct
#### Wrong
```dart
_materializeCapAfter = 4;
```

#### Correct
```dart
_materializeCapAfter = initialAfterMaterializationCap(
  segmentPostIds: segmentPostIds,
  centerScrollIndex: centerScrollIndex,
);
```

#### Wrong
```dart
WidgetsBinding.instance.addPostFrameCallback((_) => setState(_growCap));
```

#### Correct
```dart
if (shouldAdvanceTopicPostMaterialization(
  isScrollActive: _materializationPausedForScroll,
  hasPendingMaterialization: hasPendingCap,
)) {
  setState(_growCap);
}
```

## Scenario: Runtime Memory Pressure Cache Handling

### 1. Scope / Trigger
- Trigger: changing `MainPage.didHaveMemoryPressure`, Flutter `ImageCache`, decoded HTML/render caches, or mounted bottom-page eviction.

### 2. Signatures
- `WidgetsBinding.handleMemoryPressure()` calls `PaintingBinding.handleMemoryPressure()` before notifying `WidgetsBindingObserver.didHaveMemoryPressure()`.
- `shouldPruneMountedBottomPages(mountedPageIds, activePageId) -> bool`
- Diagnostic stage after the framework callback: `after_framework_image_cache_clear`.

### 3. Contracts
- Flutter's painting binding already calls `imageCache.clear()` before app observers run. The app observer must not repeat that operation.
- Never call `imageCache.clearLiveImages()` for memory pressure. Live entries still have widget listeners; removing their cache tracking does not free those images and can cause duplicate resolve/decode work after resume.
- Project-owned HTML, long-post, emoji, blocked-user, and syntax caches may be cleared after the framework image-cache step.
- Bottom-page retention may shrink to the active page, but call `setState` only when the mounted-id set is not already exactly that page.
- Background `hidden` handling may continue clearing non-live keep-alive images independently; it must not be changed into live-image eviction.

### 4. Validation & Error Matrix
- Memory pressure with two live visible images -> framework keep-alive cache is empty, live tracking remains intact after the app observer.
- Repeated pressure after pages already shrink to the active page -> runtime caches may clear again, but the main widget tree is not rebuilt solely to write the same mounted-id set.
- Multiple mounted bottom pages -> retain only the active page and rebuild once.
- No resolved bottom pages -> skip page-pruning state changes without throwing.

### 5. Good/Base/Bad Cases
- Good: rely on the framework image-cache clear, clear only project caches, and conditionally prune inactive pages.
- Base: a visible live image remains referenced until its normal listener lifecycle reaches zero.
- Bad: call `clear()` and then `clearLiveImages()` from `didHaveMemoryPressure`, producing image reattachment/decode storms without freeing listener-owned images.

### 6. Tests Required
- Unit-test `shouldPruneMountedBottomPages` for exact-active, multiple-page, and wrong-active sets.
- Keep LazyImage, topic preview, long-post render cache, performance diagnostics, and mounted-page retention tests green.
- When diagnosing devices, compare `memory_pressure` and `runtime_cache_cleared` image snapshots: live count must no longer be forced to zero by the app observer.

### 7. Wrong vs Correct
#### Wrong
```dart
void didHaveMemoryPressure() {
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  setState(() => mountedPages = {activePage});
}
```

#### Correct
```dart
void didHaveMemoryPressure() {
  // Flutter has already cleared non-live keep-alive images.
  clearProjectRuntimeCaches();
  if (shouldPruneMountedBottomPages(
    mountedPageIds: mountedPages,
    activePageId: activePage,
  )) {
    setState(() => mountedPages = {activePage});
  }
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

## Scenario: Home Detailed Topic Excerpt Request Governance

### 1. Scope / Trigger
- Trigger: changing `PreheatGate`, `TopicsPage`, `homeDetailedTopicList`, `HomeTopicExcerptLoader`, or first-post preview handoff.

### 2. Signatures
- Preference gate: `PreferencesState.homeDetailedTopicList`
- Visible-card loader: `homeTopicExcerptProvider(topic.id)`
- First-post endpoint: `GET /t/{topicId}/1.json`
- Preview handoff: `TopicDetailCacheService.writePreviewSeed(...)`

### 3. Contracts
- `PreheatGate` must not independently warm first-post excerpts. Startup and visible cards must never use separate loaders that can request the same topic without shared in-flight deduplication.
- When `homeDetailedTopicList == false`, building or scrolling the home list must not create excerpt providers or send background `/t/{topicId}/1.json` requests.
- When enabled, only mounted visible-card excerpt consumers may progressively request uncached first posts through the shared loader and global request scheduler. Disposing a queued card must cancel its unstarted work.
- Cached first-post HTML may remain after the preference is disabled. Reading that cache is local-only and may still accelerate an explicit user navigation; it must not itself start a request.
- A cached preview seed accelerates the OP only. Topic detail must still revalidate in the background and progressively load replies and volatile metadata.

### 4. Validation & Error Matrix
- Preference disabled at startup -> zero automatic first-post excerpt requests; normal HTML bootstrap, topic-list reads, and MessageBus polling remain allowed.
- Preference disabled while old excerpts exist -> no background fetch; an explicit card/detail action may reuse the cache and then follow the normal interactive detail refresh path.
- Preference enabled with an uncached visible card -> one scheduler-governed first-post request shared by concurrent consumers of that topic.
- Preference enabled during continuous scrolling -> requests are limited to mounted consumers and loader scheduling; no separate startup batch may amplify them.
- Excerpt request fails or is rate-limited -> keep the card usable, apply existing cooldown/cancellation behavior, and do not retry from a second loader.

### 5. Good/Base/Bad Cases
- Good: detailed display is off, home scrolling sends no `/t/:id/1.json`; opening a topic remains an explicit interactive request.
- Base: detailed display is on, visible cards fill summaries gradually and the displayed OP is reused immediately in detail while replies revalidate.
- Bad: `PreheatGate.warmupTopics(...)` fetches the first eight OPs while visible cards independently request the same topics.

### 6. Tests Required
- Widget-test that the disabled preference does not build/call the home excerpt provider during home-card construction and scrolling.
- Test concurrent same-topic consumers share one in-flight request and released queued topics do not fetch.
- Keep topic preview and topic-detail preview-seed tests green to prove immediate OP paint plus background revalidation.
- Review startup request traces for automatic `/t/:id/1.json` entries separately from normal `/message-bus/:clientId/poll` long polling.

### 7. Wrong vs Correct
#### Wrong
```dart
// A startup loader competes with the visible-card loader.
await ref.read(homeTopicExcerptLoaderProvider).warmupTopics(topicIds);
```

#### Correct
```dart
final showExcerpt =
    isHomeTopicList && preferences.homeDetailedTopicList;
final excerpt = showExcerpt
    ? ref.watch(homeTopicExcerptProvider(topic.id))
    : null;
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
- Trigger: changing home/search/bookmark/history topic-card navigation, `TopicPreviewDialog`, `TopicDetailPage` initial preview fields, restored reading position, or topic-detail initial post-window loading.

### 2. Signatures
- `buildTopicDetailRoute(topicId, initialTitle?, scrollToPostNumber?, initialTopicPreview?, initialFirstPostHtml?)`
- `TopicPreviewDialog` keeps the loaded first-post `TopicDetail` and writes it through `TopicDetailCacheService.writePreviewSeed(...)` before invoking its detail callback.
- Preview geometry uses `minViewportHeightFactor = 0.46` (clamped to 320..420 logical pixels) and `viewportHeightFactor = 0.85` as the safe-viewport maximum, with `AnimatedSize` handling async content arrival.
- `SearchPreviewDialog.show(...)` clears the active search input with `UnfocusDisposition.scope` before pushing the preview route.
- `TopicDetailPage.initialTopicPreview` and `initialFirstPostHtml` are first-paint preview data only.
- `scrollToPostNumber` is an explicit navigation target and must remain stronger than preview/restored state.

### 3. Contracts
- Home topic cards that already have first-post HTML must pass preview data and no `scrollToPostNumber`; comments/replies load below the stable first post.
- For home entry with no explicit target, seed the topic-detail runtime cache/provider with that preview first post and let the full detail arrive through background refresh. Do not render preview through a one-off page branch that is immediately replaced by a second full-page load path.
- Preview-driven entry from home/search may preserve the user's nested-view preference, but nested-view loading must continue rendering the preview first post while replies load below. Do not switch from preview paint to a full-page nested skeleton.
- Search result cards may pass preview data and `scrollToPostNumber`; the preview accelerates first paint but must not cancel the search hit jump.
- Any unified topic preview entry (home, bookmark, browsing history, or search) that actually rendered first-post HTML may seed that same first post before opening detail. Do not issue a second first-post-only request merely to hand off data already displayed in the preview.
- A preview seed is never a complete topic response: opening detail must still revalidate in the background to load replies and volatile metadata.
- Restored reading state is a fallback only. Do not apply it when first-post preview is available and no explicit target was requested.
- Loading replies, post windows, boosts, likes, or metadata must not replace the visible first-post preview with a global skeleton.
- The preview dialog must size from real rendered content between its minimum and maximum bounds. Keep long content scrollable inside the dialog; do not estimate complex HTML height from character count or use `IntrinsicHeight` around the HTML renderer.
- Keep preview chrome lightweight: use a uniform four-side outline instead of a one-edge color strip, and separate title/author/category/tags from the post body with a low-alpha `outlineVariant` divider.
- Search preview routes must clear both the current input focus and the focus scope's remembered child before push. Otherwise popping the preview restores the search field and reopens the software keyboard. Keep this behavior in the shared search-preview entry rather than changing global dialog focus policy.

### 4. Validation & Error Matrix
- Preview + no explicit target -> render first post immediately; fetch the normal first page/window for replies.
- Preview + explicit target -> render preview immediately; preserve the target post number and position when loaded, and do not swap back to a global skeleton while waiting for the target window.
- Preview dialog loads first post, then opens detail -> first post renders from the runtime seed; full detail/replies revalidate in the background.
- No preview + explicit target -> existing jump-target skeleton behavior is allowed.
- Target post missing after load -> use the existing unreachable-target fallback; do not silently jump to the wrong floor.
- Short first post -> dialog remains at or above the minimum but below the 85% maximum; unused space must not expand to the maximum.
- Long/complex first post -> dialog stops at the 85% maximum and the content area scrolls without overflow.
- Async first-post arrival -> size changes through the configured ease-out `AnimatedSize`; no abrupt fixed-height swap.
- Focused search field + preview open/close -> the field stays unfocused after pop and the software keyboard remains hidden.

### 5. Good/Base/Bad Cases
- Good: home card preview opens with `scrollToPostNumber: null`, then replies append/load below.
- Good: bookmark/history preview writes the displayed first post to the username-scoped runtime cache before running the existing navigation callback.
- Good: constrained loose-flex content lets a two-line post stay compact and a code/image-heavy post grow only to the maximum.
- Good: every main/user-content search preview goes through `SearchPreviewDialog`, which clears the search focus scope once.
- Base: search result preview opens with `scrollToPostNumber: post.postNumber` and uses the search blurb as first paint.
- Bad: treating every preview as permission to ignore `scrollToPostNumber`, or passing home `lastReadPostNumber` together with first-post preview.
- Bad: forcing every preview to 85% height, measuring complex HTML intrinsically, or restoring a decorative strip on only one edge.
- Bad: only calling `unfocus()` after the preview pops, or changing the global dialog route so unrelated editors can no longer restore focus.

### 6. Tests Required
- Assert preview without explicit target resolves to first-post loading, not restored reading position.
- Assert preview with explicit target preserves that target for search/notification-style navigation.
- Assert search post cards expose preview topic data and blank blurbs do not create fake preview HTML.
- Widget-test preview dialog minimum/maximum adaptive geometry, resize animation, metadata divider, and its single detail action; unit-test preview seeds always revalidate and may bootstrap explicit target routes until the target loads.
- Widget-test a focused search `TextField` with visible test input, then open and close `SearchPreviewDialog`; assert focus and keyboard stay dismissed after pop.
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
cache.writePreviewSeed(previewDetail, username: currentUsername);
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
- Preview-seed snapshots are allowed only for first-post handoff from a preview-capable topic list/dialog and must always trigger background revalidation. The seed may accelerate an explicit bookmark/search target, but it must not cancel or weaken that target.
- Filtered views (`summary`, author-only, top-level-only) must not overwrite the normal unfiltered topic cache.
- New replies and volatile action state must be reconciled by background refresh or MessageBus/local mutation updates; cached data is a fast first paint, not an authority for 24 hours.

### 4. Validation & Error Matrix
- Cache miss -> load via normal `getTopicDetail` path.
- Hard-expired cache -> discard and load via normal path.
- Soft-stale cache -> render snapshot, then refresh in the background.
- Target post missing from a complete snapshot -> treat as cache miss; a first-post preview seed may render while the explicit target loads, but the target remains authoritative.
- Background refresh failure -> keep the rendered cached detail and log/debug only; do not replace the page with a global error.
- User changes -> use a different username cache bucket; do not leak action/bookmark state between users.

### 5. Good/Base/Bad Cases
- Good: keep route `instanceId`, read a `topicId + username` snapshot, render immediately, refresh after soft TTL.
- Base: cache only in memory when full model serialization is unavailable; add disk persistence later only with explicit model/raw-JSON contracts.
- Bad: remove `instanceId` to force provider reuse, cache filtered views over normal detail, or skip refresh for a whole day.

### 6. Tests Required
- Unit-test cache hit/miss, user isolation, hard TTL, soft revalidation, target-post miss, and LRU eviction.
- Provider tests should assert cached detail renders before a stale background refresh result when a fake service is available.
- Regression-test that target-post routes reject complete snapshots missing that post number, while preview seeds may bootstrap the OP without weakening the target.

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

## Scenario: Topic MessageBus Backlog Batching

### 1. Scope / Trigger

- Trigger: changing topic-channel post updates, typing presence, MessageBus JSON
  decoding, or topic-detail handling of `created/revised/acted/liked/boost` events.

### 2. Signatures

- `TopicChannelState.postUpdates` is the latest batch, not an accumulated history.
- `TopicChannelState.postUpdatesGeneration` increments once per non-empty flush.
- `dedupePostUpdateBatch(Iterable<PostUpdate>) -> List<PostUpdate>`
- `networkRefreshPostCount(Iterable<PostUpdate>) -> int`
- `decodeMessageBusMessages(String, {int isolateDecodeThreshold})`

### 3. Contracts

- `TopicChannelNotifier` must collect synchronously dispatched post updates and publish
  them once at the next microtask boundary.
- Consumers detect a new batch by generation change and consume the whole batch once.
- Ordinary updates dedupe by `postId + type`; boost updates dedupe only when a boost id
  exists, and distinct/unknown-id increments must remain separate.
- During active topic scrolling, non-`created` updates that can change layout stay deferred
  until idle. `created` updates continue updating the stream immediately.
- More than eight different posts requiring individual network refreshes collapse into one
  `refreshWithPostNumber(anchor)` final-state refresh. The current viewport anchor must be
  preserved.
- MessageBus chunks at or above 32 KiB decode with `compute`; smaller chunks decode on the
  main isolate. Callers await chunks sequentially so channel/message order cannot change.
- Presence updates may debounce for 200ms, but pending enter/leave changes must accumulate
  on the pending list and all timers must be canceled on provider disposal.

### 4. Validation & Error Matrix

- Same post/type repeated in one poll -> keep the latest payload only.
- Two different boost ids -> keep both; missing boost ids -> keep every event.
- Large backlog while scrolling -> apply `created`, defer the remainder, collapse only after
  scroll idle.
- Provider disposed before microtask/timer -> do not write state.
- Large and small JSON decode paths -> return identical ordered messages.
- Invalid JSON -> log the existing decode error and keep the polling loop alive.

### 5. Good/Base/Bad Cases

- Good: background resume publishes one generation and either applies a small deduped batch
  or performs one anchored final-state refresh.
- Base: normal real-time traffic usually publishes one or two updates per generation.
- Bad: append every event to an ever-growing state list, notify Riverpod for every message,
  or launch one post request/rebuild per backlog event.

### 6. Tests Required

- Unit-test ordinary update and boost-id dedupe behavior.
- Unit-test unique network-refresh post counting using the current notifier semantics.
- Test `TopicChannelState.copyWith` generation retention/advance.
- Test synchronous and forced-isolate MessageBus decode paths for identical ordering.
- Keep topic preview, jump target, scrolling, and overlay tests green because backlog refresh
  must not break the first-post preview handoff or viewport anchoring.

### 7. Wrong vs Correct

#### Wrong

```dart
final updates = [...state.postUpdates, update];
state = state.copyWith(postUpdates: updates);
for (final update in newUpdates) {
  notifier.refreshPost(update.postId);
}
```

#### Correct

```dart
_pendingUpdates.add(update);
scheduleMicrotask(_flushPostUpdateBatch);

if (next.postUpdatesGeneration != previous?.postUpdatesGeneration) {
  _handlePostUpdateBatch(notifier, next.postUpdates);
}
```

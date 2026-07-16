# Technical Design

## Boundaries

### 1. Complex-topic performance

- Keep the existing nested-comment view, expansion threshold, viewport visibility gate, and manual expansion behavior.
- Add a dedicated serial materialization queue so automatic child-subtree materialization applies at most once per rendered frame. Network prefetch remains on its existing independent queue.
- Clamp `LazyImage` decode width to the smaller of the declared logical width and current screen width before DPR conversion. Keep the existing height cap and `ResizeImagePolicy.fit`.
- Expose a CF business-traffic-blocked state from `CfChallengeService`. Mark it on authoritative challenge detection and clear it only after fresh clearance is stored. `ScreenTrack` keeps local timing accumulation but does not send while blocked.

### 2. Startup Cloudflare verification

- Browser trust recovery starts the existing `CfChallengePage` in background mode (`forceForeground=false`). This preserves its WebView, cookie synchronization, success detection, timeout, and cleanup contracts while removing the route/barrier from view.
- Explicit login and Network Settings manual verification keep `forceForeground=true`.
- A challenge that truly requires interaction remains recoverable through the existing explicit verification entry; background startup does not pretend to bypass it.

### 3. Preview-to-detail continuity

- Preserve the already loaded OP preview separately from the target-post window.
- While nested data is loading, use the initial preview detail to build the temporary nested OP shell even if the target response does not contain post 1.
- Bookmarks pass the same topic/first-post preview fields as home/search when opening details. Direct bookmarked-post/search target semantics remain intact; no request or navigation target is removed.
- Provider state and authoritative post stream are not rewritten with a synthetic discontinuous list.

### 4. Network settings scroll stability

- Read `developer_mode` synchronously from the existing `sharedPreferencesProvider` on the first build, eliminating delayed insertion of the developer-only rows.
- Give the cookie-diagnostics loading/error/data states a stable minimum geometry so its asynchronous completion cannot produce another large list extent change.
- Do not alter rate-limit values, persistence, Slider behavior, or card styling.

## Compatibility and rollback

- No schema, dependency, API endpoint, localization, or card visual redesign.
- Each area is committed independently and can be reverted independently.
- Existing interactive CF entry points remain foreground; only automatic browser-trust recovery changes presentation.
- Existing homepage detailed display and first-post cache handoff remain the authoritative implementation and are reused by bookmarks.

## Diagnostics

- Retain current frame/component events. The serial queue should make `nested:childrenMaterialized` events appear no more than once per frame.
- CF traffic-block state is represented by service state, avoiding repeated warning logs and network calls rather than adding high-frequency diagnostics.

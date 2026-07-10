# Verification Evidence

## GitHub Actions baseline

- Run: `29099617349`
- Head: `9faecd850533a5cc32f7783c8c2ad35ad11f94f8`
- Result: workflow, Android, Windows and upload jobs all `success`.
- Release: `v0.6.103`, exactly three non-empty assets.
- APK SHA-256: `9877310988ffd2fe4933ce5089038cd57e5deb6fdce7a0f1119acfbb8251c524` (matches GitHub digest).
- APK signing: `apksigner verify --verbose --print-certs` passed with v2 scheme.
- APK native libraries:
  - `lib/arm64-v8a/libdoh_proxy.so`
  - `lib/arm64-v8a/librhttp.so`

## Commits

- `f45f0fc9` — `fix fingerprint endpoint extraction`
- `833e0cd2` — `throttle stale fingerprint bootstrap retries`
- `f6368a02` — `dedupe upload short url lookups`
- `a2d93334` — `docs codify request containment contracts`

## Request safety inspection

- `RequestSchedulerConfig.maxConcurrent == 3`
- `RequestSchedulerConfig.maxPerWindow == 6`
- `RequestSchedulerConfig.windowSeconds == 3`
- `RequestSchedulerConfig.minIntervalMs == 250`
- No scheduler file changed in `9faecd85..HEAD`.
- No new `skipScheduler` use; the only existing use remains the CSRF internal deadlock-avoidance path.
- Upload lookup adds no client retry loop and continues through the normal `DiscourseDio` interceptor chain.

## Targeted verification

Command covered 15 files/suites and completed with 83 passing tests, including:

- WebView bootstrap cooldown and fingerprint extraction.
- Preloaded plugin candidate invalidation.
- Upload same-key in-flight, multi-key batch, missing cache and transient recovery.
- Notion missing short-link preservation.
- User-profile request options and stable stats geometry.
- Home detailed excerpt loading/pause/cache behavior.
- Initial topic preview handoff and progressive post materialization.
- Topic scroll performance helpers.
- Request scheduler priority, host sharing, spacing and 429 cooldown.
- MessageBus batching/decoding and topic-detail cache behavior.

## Full quality gate

- `flutter analyze --no-pub lib test` — exit 0, no issues.
- `flutter test --no-pub` — exit 0, 473 tests passed.
- `git diff --check` — exit 0.

## Delivery

The task is archived locally before the single final branch push so the task/archive and journal commits are included in that same push. After pushing, monitor the newly triggered GitHub Actions run to completion and verify the new release assets.

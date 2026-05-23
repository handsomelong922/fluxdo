# P0 Reading Experience Improvements And P1 Roadmap

## Goal

Stabilize the high-frequency reading experience with low-risk P0 improvements first, then define a cautious P1 roadmap for high-value features that need more design before implementation. The priority is to improve continuity, reduce interruptions, and make topic reading behaviors consistent without destabilizing the current rollback branch.

## What I Already Know

* The user wants the first implementation stage to focus on high-benefit, low-risk P0 items.
* The user also wants a systematic P1 assessment and prudent design plan before any riskier implementation.
* Current branch: `codex/rollback-to-v0.3.1`.
* Recent work already added or improved:
  * Topic detail top bar scroll hiding.
  * Default tree view preference.
  * Tree view progress/jump mapping and load-more behavior.
  * AI summary persistence and summary-to-chat continuation.
  * CF challenge background behavior and notification throttling.
  * Upstream compatibility review.
* Existing relevant code discovered:
  * `detailScrollPositionProvider` tracks per-topic scroll position in memory.
  * `TopicDetailController.currentPostNumber` tracks current topic position.
  * `PreferencesNotifier.defaultNestedTopicView` persists the default tree view preference.
  * `TopicAiSummaryCacheService` persists AI summaries in `SharedPreferences`.
  * `CfChallengeService` and `CfChallengeLogger` already expose challenge state/logging foundations.
  * `TopicProgress` exists and is now shared by flat/tree topic modes.

## Assumptions

* Stability is more important than feature breadth.
* P0 should avoid schema changes, dependency upgrades, upstream bulk merges, and large page rewrites.
* P0 can add local persistence, small settings/UI affordances, tests, and conservative behavior improvements.
* P1 design can be documented now, but implementation should be split into separate tasks after P0 is verified.

## Requirements

### P0 Stage 1: Reading Continuity

* Persist the last read post number per topic beyond the current in-memory provider, so closing/reopening the app can restore reading position.
* Preserve per-topic reading mode state where useful:
  * last selected tree/flat mode,
  * tree sort mode if already available in provider state,
  * last known post number.
* Restore position conservatively:
  * only when the user enters the same topic without an explicit `scrollToPostNumber`,
  * never override notification/search/solution/deep-link jumps.
* Add tests for preference/storage behavior where feasible.

### P0 Stage 2: Tree View Reliability

* Treat tree view as the default supported reading mode, not an experimental side path.
* Add targeted regression coverage for:
  * post number to scroll index mapping,
  * accepted-solution jump fallback,
  * load-more auto trigger guard behavior,
  * view toggle preference persistence.
* Avoid large tree rendering rewrites unless tests expose a local defect.

### P0 Stage 3: AI Summary Freshness

* Keep current summary persistence behavior.
* Add a lightweight "possibly outdated" indicator when topic reply count changes enough after the cached summary.
* Do not auto-regenerate summaries.
* Keep manual refresh as the only regeneration path.
* Preserve summary-to-chat continuation context.

### P0 Stage 4: Verification / Network Interruption Reduction

* Keep CF verification in the background.
* Add a low-noise status surface for verification state if feasible:
  * recent failure count,
  * cooldown status,
  * last verification result/time,
  * link to logs/debug tools when developer mode exists.
* Avoid foreground modal verification unless explicitly requested by the user.

### P0 Stage 5: Navigation Consistency

* Ensure flat view and tree view share the same user expectations for:
  * progress indicator,
  * floor jump,
  * search result jump,
  * accepted solution jump,
  * internal topic links.
* Prefer shared helpers over duplicated view-specific logic.

## P1 Roadmap Candidates

### P1-A: Lightweight Immersive Reading

* Add tap-to-restore controls when navigation bars are hidden.
* Consider long-press or drag on progress control for quick floor selection.
* Main risks: gesture conflicts and accidental UI hiding.
* Recommended design: prototype behind existing `hideBarOnScroll`; no new global setting until behavior is proven.

### P1-B: AI Context Visibility

* Show the active AI context source in the AI assistant:
  * cached summary,
  * first post,
  * first 5/10/20 posts,
  * all loaded replies.
* Benefit: reduces user uncertainty about why AI answered a certain way.
* Risk: low, mostly UI/state display.
* Recommended design: read-only context chip first; advanced context editing later.

### P1-C: Summary And Chat History Linking

* Let users resume the latest summary-derived AI session from the summary card.
* Provide a clear "new chat from summary" versus "continue previous chat" distinction.
* Risk: medium because session identity and topic summary cache can drift.
* Recommended design: metadata-only link from summary cache to AI session id, with graceful fallback.

### P1-D: Local Block Rule Management

* Add a management page for quick blacklist/custom local filter rules.
* Support view/delete/export/import later.
* Risk: low if kept local-only.
* Recommended design: start with read/delete only; defer import/export.

### P1-E: Login And Cookie Diagnostics

* Add a read-only diagnostics card:
  * logged-in state,
  * last cookie sync time,
  * presence of required auth cookies,
  * last login handoff status.
* Risk: low to medium; must avoid leaking sensitive cookie values.
* Recommended design: display booleans/timestamps only, never raw cookie content.

## Acceptance Criteria

* [x] P0 implementation is split into small, reviewable changes.
* [x] No dependency upgrades are introduced in P0.
* [x] Explicit topic jumps still take priority over restored reading state.
* [x] AI summaries remain cached and refresh only on manual action.
* [x] Tree view remains default-enabled and can be disabled by the user.
* [x] CF verification remains background-first and low-noise.
* [x] Targeted analyzer/tests pass for modified files.
* [x] P1 roadmap is documented with benefit, risk, and recommended sequencing.

## Definition Of Done

* P0 changes implemented with local persistence and/or UI additions only where risk is low.
* Regression tests added for new storage/state behavior.
* `dart analyze` passes for touched files.
* Relevant Flutter tests pass, or any environment blocker is explicitly documented.
* P1 remains a design artifact unless the user explicitly approves a P1 implementation task.

## Out Of Scope

* Bulk merge from `upstream/dev`.
* Large rewrite of `TopicDetailPage`.
* New dependencies.
* Automatic AI summary regeneration.
* Foreground-first CF verification.
* P1 implementation in the same commit as P0 unless explicitly approved.

## Technical Notes

* Existing in-memory reading position: `lib/providers/selected_topic_provider.dart`.
* Topic detail current position: `lib/pages/topic_detail_page/controllers/topic_detail_controller.dart`.
* Topic detail entry and explicit jump logic: `lib/pages/topic_detail_page/topic_detail_page.dart`.
* Tree view implementation: `lib/pages/topic_detail_page/widgets/nested_post_list.dart`, `lib/widgets/nested/nested_post_card.dart`.
* AI summary cache: `lib/services/topic_ai/topic_ai_summary_cache_service.dart`.
* Preferences: `lib/providers/preferences_provider.dart`, `lib/settings/definitions/reading_defs.dart`, `lib/settings/definitions/preferences_defs.dart`.
* CF verification: `lib/services/cf_challenge_service.dart`, `lib/services/network/interceptors/cf_challenge_interceptor.dart`, `lib/pages/network_settings_page/widgets/debug_tools_card.dart`.

## Proposed Implementation Plan

### PR1: Persistent Reading Continuity

* Add a small local service/provider for last topic reading state.
* Persist topic id, post number, optional view mode, and update timestamp.
* Restore only when there is no explicit jump.
* Add unit tests for storage and restore priority.

### PR2: Tree View Reliability Guardrails

* Extract testable helpers for tree post mapping/load-more arming where practical.
* Add regression tests around mapping and preference behavior.
* Avoid UI redesign unless a defect requires it.

### PR3: Summary Freshness Indicator

* Extend cached summary metadata with reply count / post count at generation time.
* Show a non-blocking stale hint when current topic count exceeds cached count.
* Manual refresh replaces cached metadata.

### PR4: Verification Status Surface

* Expose read-only challenge status from service/logger.
* Add low-noise status text/card in network/debug settings.
* Keep toast throttling and background verification behavior unchanged.

## Open Questions

* Which P0 slice should be implemented first if we want the smallest safe commit: reading continuity, summary freshness, tree guardrails, or verification status?

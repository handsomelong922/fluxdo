# P1 Reading Assistant UX Improvements

## Goal

Deliver the safest high-value P1 improvements after the P0 reading stability work. The focus is to reduce user uncertainty while reading and troubleshooting: make AI context usage visible, and add read-only login/Cookie diagnostics without changing authentication, network, Cookie write, or AI generation flows.

## What I Already Know

* The user wants P1 modules carefully designed and implemented only after P0 is verified.
* Stability is the primary constraint; no risky rewrites or dependency upgrades should be introduced.
* P0 already added reading continuity, summary freshness hints, CF status visibility, and tree-view load-more guardrails.
* Existing AI chat already supports context scope selection and context post loading, but the UI does not clearly show how many posts are actually available/loaded for the active context.
* Existing Cookie infrastructure already exposes value-free session cookie diagnostics through `CookieJarService.getSessionCookieDiagnosticsForRequest`.
* Existing network settings already have a Debug Tools card, but no concise login/Cookie status card for normal troubleshooting.

## P1 Module Design

### Implement Now: AI Context Visibility

* Show a compact, read-only status strip inside the AI assistant page.
* Status must show:
  * selected context scope,
  * loaded context post count,
  * expected context post count for the selected scope,
  * whether context is loading,
  * whether the topic detail is unavailable.
* The strip must not trigger new AI generation or mutate chat sessions.
* The strip must update when the context scope changes or context posts finish loading.
* Quick prompt scope overrides must still work and should visibly update the scope/status.

### Implement Now: Login/Cookie Diagnostics

* Add a read-only diagnostics service that summarizes login/session cookie health without exposing cookie values.
* Surface in Network Settings as a normal troubleshooting card, separate from developer-only log tools.
* Status must show:
  * whether app user state is logged in,
  * whether session cookies `_t` and `_forum_session` are present,
  * session cookie count and duplicate-name risk,
  * `cf_clearance` presence if available,
  * last check time.
* Card may provide a manual refresh action.
* Card must never print or display raw cookie values.
* Card must not clear, rewrite, or sync cookies.

### Design Only: Higher-Risk P1 Candidates

* Immersive reading gestures:
  * Benefit: better full-screen reading.
  * Risk: gesture conflicts and navigation hiding regressions.
  * Recommendation: split into a separate prototype task behind existing `hideBarOnScroll`.
* Summary/chat history linking:
  * Benefit: more seamless AI continuation.
  * Risk: session identity drift and migration complexity.
  * Recommendation: add metadata-only session links later with graceful fallback.
* Local block rule management:
  * Benefit: user control over quick blacklist rules.
  * Risk: low, but requires separate settings UI and delete/undo UX.
  * Recommendation: read/delete-only management page in a dedicated task.

## Requirements

* No dependency upgrades.
* No upstream merge.
* No authentication flow changes.
* No Cookie value exposure in UI, logs, tests, or debug output.
* No AI chat storage schema migration.
* All new derived status logic should be pure/testable where practical.
* Existing P0 behavior must remain intact.

## Acceptance Criteria

* [x] AI assistant displays current context visibility without changing generation behavior.
* [x] Context status handles empty, loading, partially loaded, and fully loaded states.
* [x] Network Settings displays a read-only login/Cookie diagnostics card.
* [x] Diagnostics never include raw cookie values.
* [x] Diagnostics can identify missing session cookies and duplicate cookie-name risk.
* [x] Targeted analyzer passes for modified files.
* [x] Relevant Flutter tests pass.
* [x] Remaining P1 candidates are documented with benefit/risk/sequencing.

## Definition Of Done

* P1 low-risk modules are implemented with unit tests.
* Static analysis passes on touched files.
* Relevant tests pass.
* Commit contains only this task's files and excludes unrelated dirty workspace files.

## Out Of Scope

* Modifying login/OAuth flow.
* Auto-repairing cookies.
* Displaying or exporting raw cookie values.
* Large AI chat session migration.
* Gesture/navigation rewrites.
* Upstream feature merge.

## Technical Notes

* AI chat page: `lib/pages/topic_detail_page/widgets/ai_chat_page.dart`
* AI context service: `lib/services/topic_ai/topic_ai_context_service.dart`
* Existing context selector: `lib/pages/topic_detail_page/widgets/ai_context_selector.dart`
* Cookie diagnostics source: `lib/services/network/cookie/cookie_jar_service.dart`
* Session snapshot model: `lib/services/network/cookie/session_snapshot.dart`
* Network settings declaration: `lib/settings/definitions/network_defs.dart`
* Relevant specs:
  * `.trellis/spec/guides/cross-layer-thinking-guide.md`
  * `.trellis/spec/guides/code-reuse-thinking-guide.md`

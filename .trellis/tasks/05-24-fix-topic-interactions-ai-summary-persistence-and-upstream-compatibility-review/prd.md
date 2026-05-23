# Fix Topic Interactions, AI Summary Persistence, And Upstream Compatibility Review

## Goal

Improve the topic reading experience on the current stable rollback branch without destabilizing the user's fork. The work focuses on topic detail navigation behavior, background verification notification pacing, AI summary persistence and continuation, tree view compatibility, and a cautious review of valuable upstream updates.

## What I Already Know

- The current branch is `codex/rollback-to-v0.3.1`.
- The true v0.3.1 baseline is `codex/anchor-v0.3.1`.
- The safety branch is `codex/safety-20260520-114042`.
- Recent local commits already changed nested topic links, Cloudflare verification behavior, OAuth cookie sync, and topic detail app bar title behavior.
- The user verified that background verification no longer forces foreground manual validation, which is the desired direction.
- The repository has Trellis enabled, but current specs mainly cover `core/doh_proxy`; Flutter UI work must follow existing code patterns and project-local conventions.
- `upstream` points to `https://github.com/Lingyan000/fluxdo.git`; `upstream/dev` has been fetched for compatibility review.

## Requirements

- Restore scroll-hide behavior for the topic detail top navigation bar while keeping the title removed.
- Keep background verification non-interruptive and reduce repeated failure notifications to a much lower frequency, targeting about 1-2 minutes between repeated foreground messages.
- Persist generated AI topic summaries per topic so reopening the same topic shows the last generated result.
- Preserve the existing refresh button behavior so manual refresh regenerates the summary and updates persistence.
- Add a "continue conversation" action next to the AI summary refresh action; tapping it should slide to the AI assistant view with the summary context available in the conversation.
- Fix tree view solution-post jump behavior for quick Q&A / accepted-solution topics.
- Add or restore floor quick-jump/progress controls in tree view when a sensible layout can be embedded without breaking current tree interactions.
- Improve tree view pagination so after the "load more" control appears, scrolling near the bottom can automatically load the next page while keeping manual loading available.
- Move the tree view toggle from the bottom action area into the settings/menu surface, default it to enabled, and use it as the persistent default topic layout.
- Review upstream additions and identify which updates are valuable and low-conflict for the current branch. Only merge changes that are demonstrably compatible.

## Acceptance Criteria

- [ ] Topic detail top bar hides and reappears while scrolling when the reading setting "hide bar on scroll" is enabled.
- [ ] Topic detail app bar still shows only back, search, and more actions; no topic title is restored.
- [ ] Cloudflare/background verification failure notifications are throttled to roughly 1-2 minutes between repeated messages.
- [ ] Generated AI summaries survive closing and reopening the topic.
- [ ] Manual AI summary refresh regenerates and replaces the stored summary.
- [ ] "Continue conversation" opens the AI assistant panel/page with a left-slide transition and summary context available.
- [ ] Tree view accepted-solution / quick-answer links jump to the intended post when the post is loaded, and trigger loading/navigation fallback when needed.
- [ ] Tree view exposes a usable quick floor locator/progress control or a documented compatible alternative.
- [ ] Tree view keeps manual load-more and also auto-loads the next page when the user scrolls near the bottom after more content is available.
- [ ] Tree view default behavior is controlled from topic settings/menu and defaults to enabled.
- [ ] Upstream review findings are recorded with compatible candidates and rejected/high-risk candidates.
- [ ] Targeted Dart analysis/tests pass for changed files, or any unrelated blocker is explicitly documented.

## Out Of Scope

- Bulk merging all upstream changes.
- Rewriting the entire topic detail page architecture.
- Changing AI provider configuration or model selection policy unless required by summary persistence.
- Making background verification foreground by default again.

## Technical Notes

- Likely Flutter files include `lib/pages/topic_detail_page/topic_detail_page.dart`, `lib/pages/topic_detail_page/widgets/topic_post_list.dart`, `lib/pages/topic_detail_page/widgets/nested_post_list.dart`, `lib/pages/topic_detail_page/widgets/topic_bottom_bar.dart`, `lib/widgets/topic/topic_summary_widget.dart`, `lib/services/topic_ai/topic_ai_summary_service.dart`, `lib/services/cf_challenge_service.dart`, and related providers/settings definitions.
- Existing generated l10n files and Trellis files are dirty/untracked from previous work and should not be reverted.
- Upstream review should be recorded under `research/upstream-compatibility.md`.

# Upstream Compatibility Review

Date: 2026-05-24
Branch reviewed: `upstream/dev` at `5b9cc29`
Current branch: `codex/rollback-to-v0.3.1`

## Summary

`upstream/dev` contains useful features, but it is not safe to merge wholesale into the current rollback branch. The diff spans hundreds of files and includes localization pipeline changes, AI model manager rewrites, build/tooling changes, login flow edits, Cloudflare verification edits, nested topic rewrites, and dependency updates.

For this task, only low-conflict ideas directly related to the user's current reading workflow were implemented locally. No upstream commit was merged directly.

## Compatible Candidates For Later Cherry-Pick

- `ca41231` post-login loading handoff:
  Valuable because it isolates login completion coordination into `login_ready_coordinator.dart` and adds tests. It overlaps with the current branch's custom OAuth/session-sync changes, so it should be cherry-picked only after reviewing `webview_login_page.dart` against the local browser-first login flow.

- `5a0210e` rhttp engine persistence:
  Valuable if users still hit the rhttp engine switch reset bug. It touches `pubspec.yaml`, lockfile, network settings UI, rhttp settings service, and l10n. It is probably cherry-pickable as a focused task, but not in this batch because it introduces dependency and localization churn unrelated to topic reading.

- `f2e4fee` desktop layout/navigation grouping:
  Useful for desktop polish and has tests. It touches shared layout widgets and `main.dart`, so it should be reviewed separately from topic detail behavior to avoid layout regressions.

- `0cf898c` Linux.do-compatible "new topic" sub-filter:
  Feature-positive and mostly topic-list scoped. It touches topic list providers, topic query service, dropdown UI, and l10n. It can be evaluated as a separate feature merge after the current topic-detail changes settle.

- `78cd459` clipboard topic link recognition:
  Useful quality-of-life feature with service tests. It touches `main.dart`, preferences, deep links, update helper, l10n, and a new snackbar widget. Good candidate for a focused cherry-pick later.

## High-Risk Or Deferred Updates

- `5b9cc29` AI provider sorting, model favorite sorting, and AI post review:
  Valuable but too broad for the current stable branch. It changes AI provider state, AI model selection UI, reply/create-topic flows, draft model behavior, preferences, l10n modules, package tests, and lockfiles. It also overlaps with local AI summary and AI chat modifications made in this task.

- `5d5818b` AI assistant optimization:
  Some ideas are relevant, but it directly touches `topic_detail_page.dart`, `ai_chat_page.dart`, `ai_chat_message_item.dart`, `ai_provider_edit_page.dart`, provider state, and introduces a Dio HTTP bridge. It conflicts with the current branch's custom AI summary continuation and stable scroll behavior.

- `17792c3` boost-to-reply changes:
  Touches nested post list/card, topic post list, post footer, reply sheets, and tests. It overlaps heavily with this task's tree-view fixes and should not be merged until tree view behavior is stable.

- Upstream localization/tooling/build migration:
  The upstream diff deletes/rewrites generated localization files, adds `slang.yaml`, changes `l10n.yaml`, updates scripts/tooling, and touches many platform build files. This is infrastructure-level work and should not be mixed into the current reading interaction fix.

## Decision

No upstream code was merged in this batch. The safest path is to keep the current stable branch focused, then cherry-pick candidates one at a time with targeted tests:

1. Login handoff, if current third-party login still has loading/cookie timing issues.
2. rhttp persistence, if network engine reset is reproducible.
3. Clipboard topic link recognition or new-topic sub-filter as independent UX features.
4. Larger AI provider/post-review changes only after resolving conflicts with local AI summary/chat customizations.

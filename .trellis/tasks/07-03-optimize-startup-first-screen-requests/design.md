# Design

## Architecture

### 1. Bottom page lazy mounting

Current `MainPage` builds every `pageEntries[i].pageBuilder` inside `IndexedStack`, which mounts `ProfilePage` during home startup. Replace eager page construction with a lazy keep-alive wrapper:

- Each bottom page keeps its state after first activation.
- The active page is always mounted.
- Inactive pages are mounted only after they have been activated once.
- Before first activation, inactive pages render `SizedBox.shrink()` inside the stack.

This preserves tab state for already visited pages while preventing startup construction of `ProfilePage`.

### 2. Profile summary request gating

Add an explicit active gate inside `ProfilePage`:

- If `widget.isActive == false`, do not build `ProfileStatsCard`.
- When active, build the existing card unchanged so `userSummaryProvider` keeps current behavior.
- Keep bottom avatar unchanged because `NavEntryRegistry._profileIcon` reads only `currentUserProvider`.

The lazy mounting should be sufficient for the default path; the `ProfilePage` active gate is a defensive layer for future cases where profile is mounted but inactive.

### 3. Startup request ranking

Use existing `NetworkLogInterceptor` as the authoritative source for request timing and add a small in-memory recorder:

- Record sanitized request events on response/error.
- Attach launch session id and `relativeStartMs` from app process start.
- Keep a bounded ring buffer in memory to avoid unbounded growth.
- Provide sorted views by duration descending and chronological order.
- Keep `LogWriter` output compatible by adding extra fields rather than replacing existing logs.

Preferred display path:

- Add a startup/network request section to the existing app logs/debug surface if a suitable UI already exists.
- If existing UI is not suitable, add a small developer-only page reachable from app logs page or network debug card.

No external software download is required for this phase. The app already instruments Dio requests via `NetworkLogInterceptor`; we can make that instrumentation sortable and easier to inspect from inside the app/logs.

## Data Contract

Request event fields:

- `timestamp`
- `relativeStartMs`
- `duration`
- `method`
- `url` sanitized to scheme + host + path
- `path`
- `statusCode`
- `level`
- `priority`
- `isSilent`
- `networkAdapter`
- `errorType` when available

Do not store:

- query string
- cookie header
- authorization header
- request body
- response body

## Trade-offs

- Lazy mounting changes lifecycle timing for inactive tabs. This is desired for startup performance but may delay background page initialization until first visit.
- Keeping home excerpt loading means startup may still issue `/t/{id}/1.json` background requests when detailed home list is enabled. That aligns with the user’s stated goal because summaries are part of desired first-screen content.
- In-memory request ranking observes current process/session only. Historical logs remain in `LogWriter`, but the live ranking intentionally stays bounded and low overhead.

## Rollback

- Revert lazy mounting wrapper to eager `IndexedStack` children if tab lifecycle regressions appear.
- Disable the request recorder by removing it from `NetworkLogInterceptor`; existing logging can remain untouched.

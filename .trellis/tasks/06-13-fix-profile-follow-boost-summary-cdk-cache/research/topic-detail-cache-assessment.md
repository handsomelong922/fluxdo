# Topic Detail Cache Assessment

## Current Behavior

`TopicDetailPage` creates a new UUID `instanceId` when the caller does not pass one. `TopicDetailParams` includes `topicId` and `instanceId` in equality/hashCode, so opening the same topic through most routes creates a fresh `topicDetailProvider` instance and fetches again.

`topicDetailProvider` is `autoDispose` with `ref.keepAlive()` and a 30 second delayed close after the last watcher disappears. This protects short layout switches, but it is not a user-facing "reopen same topic later" cache.

This looks intentional for page-state isolation: scroll position, target post, filters, MessageBus updates, and nested/flat modes can differ between route instances.

## Feasibility

Caching is feasible, but it should be implemented as stale-while-revalidate rather than "use cached data for a full day and never refresh". Topic details contain both durable content and user/session-sensitive state:

* Durable: title, cooked post content, post stream IDs, categories/tags.
* Volatile: like/bookmark/action state, notification level, deleted/hidden posts, new replies, boost state, solved status, edit state.

## Recommended Strategy

Use a two-layer cache:

1. In-memory LRU cache for fast back-and-forth navigation within the same app session.
2. Optional disk cache with a 24 hour TTL for cold reopen, using a bounded cache size rather than `SharedPreferences` for full topic payloads.

Cache the complete last-loaded `TopicDetail` snapshot, not only the first post. This gives the user the exact page they just saw immediately. Keep metadata with the snapshot:

* `topicId`
* loaded post IDs / post numbers
* post stream length
* loadedAt
* current user id / username
* content filter version if available

Then revalidate in the background after rendering the cached snapshot.

## New Replies Handling

Cached comments should not block discovery of new replies. On reopen:

1. Render cached snapshot immediately.
2. Fetch fresh topic detail in the background.
3. Compare `post_stream.stream.length`, topic `posts_count`, and loaded post IDs.
4. If new replies exist, show the existing "new replies" path or append/load missing post IDs through the normal gap/new-post loading code.
5. If volatile action state changed, merge the fresh post/action fields into cached content.

## Refresh Triggers

Always refresh when:

* Cache is missing.
* Cache is older than a short soft TTL, recommended 5 minutes.
* The route targets a specific post not included in the snapshot.
* The topic was opened from notification/search/deep link with a target post.
* The user pulls to refresh.
* The current user changes.
* A local mutation happens: reply, edit, delete, like, bookmark, boost, flag, notification-level change.

Use the 24 hour TTL as a hard expiry only. A snapshot younger than 24 hours can render immediately, but background refresh should still run unless it is very fresh.

## Main Post vs Comments

Caching only the main post is low memory but does not solve the user's observed reload for replies. Caching only comments is awkward because header/title/action state still needs topic detail. Caching both as one `TopicDetail` snapshot is the most coherent MVP.

For memory control, use LRU limits:

* Keep 10-20 recent topics in memory.
* Cap per-topic stored posts if a topic is huge, preserving the initial window and any target-post window.
* Evict large snapshots first if total serialized size crosses a limit.

## Suggested MVP

Do not change `TopicDetailParams.instanceId`; it still protects route-local UI state. Instead add a repository/cache layer under provider/service code:

* `TopicDetailCacheService` owns snapshot read/write/expiry.
* `TopicDetailNotifier.build()` asks the cache for an immediate snapshot by `topicId` before network.
* If cache exists, state renders cached data and a background refresh updates state when fresh data arrives.
* Network fetch writes fresh snapshots back to cache.

This keeps caching separate from route identity and avoids breaking master-detail reuse logic that already passes stable `instanceId`.

## Implementation Update

Implemented MVP keeps the recommended route identity boundary and adds an in-memory `TopicDetailCacheService` with a 1 day hard TTL, 5 minute soft refresh threshold, `topicId + username` buckets, target-post validation, and LRU eviction. Disk persistence remains intentionally deferred because `TopicDetail` currently has no complete `toJson` contract; persisting partial or filtered models would be higher risk than the reopen latency problem being solved.

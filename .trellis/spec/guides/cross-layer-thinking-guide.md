# Cross-Layer Thinking Guide

> **Purpose**: Think through data flow across layers before implementing.

---

## The Problem

**Most bugs happen at layer boundaries**, not within layers.

Common cross-layer bugs:
- API returns format A, frontend expects format B
- Database stores X, service transforms to Y, but loses data
- Multiple layers implement the same logic differently

---

## Before Implementing Cross-Layer Features

### Step 1: Map the Data Flow

Draw out how data moves:

```
Source → Transform → Store → Retrieve → Transform → Display
```

For each arrow, ask:
- What format is the data in?
- What could go wrong?
- Who is responsible for validation?

### Step 2: Identify Boundaries

| Boundary | Common Issues |
|----------|---------------|
| API ↔ Service | Type mismatches, missing fields |
| Service ↔ Database | Format conversions, null handling |
| Backend ↔ Frontend | Serialization, date formats |
| Component ↔ Component | Props shape changes |

### Step 3: Define Contracts

For each boundary:
- What is the exact input format?
- What is the exact output format?
- What errors can occur?

---

## Common Cross-Layer Mistakes

### Mistake 1: Implicit Format Assumptions

**Bad**: Assuming date format without checking

**Good**: Explicit format conversion at boundaries

### Mistake 2: Scattered Validation

**Bad**: Validating the same thing in multiple layers

**Good**: Validate once at the entry point

### Mistake 3: Leaky Abstractions

**Bad**: Component knows about database schema

**Good**: Each layer only knows its neighbors

### Mistake 4: Visual animation coupled to layout size

**Bad**: Top/bottom bars hide by changing scaffold slot height or body padding, so the scroll viewport changes while the user is dragging.

**Good**: Keep the viewport size stable and animate only paint-level properties such as translation, clipping, or opacity.

### Mistake 5: Exiting overlays keep intercepting input

**Bad**: A route, sheet, or overlay remains in the hit-test tree during its reverse animation, so the underlying scrollable is visible but cannot receive a new drag.

**Good**: Keep the visual exit animation, but disable pointer handling for the exiting layer during reverse animation so hit testing reaches the active layer below.

### Mistake 6: Loading state waits forever for an optional target

**Bad**: A page keeps showing a skeleton until an async target item appears, such as a linked post number, restored scroll anchor, or search hit. If the target was deleted, filtered, private, or omitted by the API window, the page never reaches a visible terminal state.

**Good**: Treat target positioning as best-effort after the base data has loaded. If the target cannot be found once loading settles, clear the pending target and show the available content, with retry/error affordances only when the base data itself failed.

### Mistake 7: URL parser and internal-link router disagree

**Bad**: A content link parser accepts a topic URL, but the later internal-link guard uses stricter `Uri.tryParse()` rules or a nested renderer (onebox, quote card, markdown preview, chunked HTML) forgets to pass the same internal-link callback. Malformed referral query spacing such as `?u = username` or view-mode URLs such as `/n/topic/388420?sort=old` can then bypass native topic navigation and fall through to WebView, which looks like a slow or stuck jump.

**Good**: Route topic links through one shared lenient URL parsing path for both extraction and internal-link checks, canonicalize complex topic URLs to stable `/topic/<id>` paths for fallback handling, and propagate the internal-link callback through every nested content renderer. Regression-test the exact malformed URL plus onebox/nested-renderer paths and fallback route state, especially when tree view and flat view have different loading behavior.

### Mistake 8: Forum-grounded AI search bypasses existing app AI contracts

**Bad**: A search assistant copies browser-script tool calling, stores a second API key, or lets provider web search mix external pages into a forum-only answer. This couples search UI to one vendor protocol and can produce answers outside the current account's forum permissions.

**Good**: Keep traditional search as the stable retrieval path, fetch forum context through the app's authenticated `DiscourseService`, and call the already configured AI provider/model with bounded context. Disable external web search for forum-grounded search answers unless the feature explicitly labels and separates external evidence.

### Mistake 9: Local package reverse-depends on the app shell

**Bad**: A reusable local package imports app pages or app-only services just to add one host-specific menu item. This creates circular dependency pressure and makes the package harder to reuse or test independently.

**Good**: Keep the package boundary one-way. Add a small extension slot or callback in the package API, then let the app shell inject host-specific widgets, pages, or navigation behavior from the outside.

---

## Checklist for Cross-Layer Features

Before implementation:
- [ ] Mapped the complete data flow
- [ ] Identified all layer boundaries
- [ ] Defined format at each boundary
- [ ] Decided where validation happens

After implementation:
- [ ] Tested with edge cases (null, empty, invalid)
- [ ] Verified error handling at each boundary
- [ ] Checked data survives round-trip
- [ ] Verified UI visibility state does not mutate the underlying viewport/layout contract
- [ ] Verified exiting visual layers do not keep intercepting pointer input after the active layer below should be interactive
- [ ] Verified optional jump/restore/search targets have a terminal fallback and cannot keep the base page in a permanent loading state
- [ ] Verified internal-link parsing and internal-link routing use compatible URL normalization, including malformed referral query spacing, Discourse view-mode URLs, and onebox/nested renderer callback propagation
- [ ] Verified forum-grounded AI search reuses existing app AI configuration, keeps ordinary search as an independent fallback, and does not silently mix external web search with account-scoped forum context
- [ ] Verified local packages do not import app-shell pages/services for host-specific UI; use app-injected slots or callbacks instead

---

## When to Create Flow Documentation

Create detailed flow docs when:
- Feature spans 3+ layers
- Multiple teams are involved
- Data format is complex
- Feature has caused bugs before

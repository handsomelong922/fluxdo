part of '../topic_detail_page.dart';

// ignore_for_file: invalid_use_of_protected_member

/// 滚动和导航相关方法
extension _ScrollActions on _TopicDetailPageState {
  void _updateEmbeddedDetailScrollPosition(int postNumber) {
    if (!widget.embeddedMode) return;
    ref.read(detailScrollPositionProvider(widget.topicId).notifier).state =
        postNumber;
  }

  void _ensurePostLookupCaches(TopicDetail detail) {
    final posts = detail.postStream.posts;
    final stream = detail.postStream.stream;
    final signature = Object.hash(
      detail.id,
      posts.length,
      stream.length,
      posts.isEmpty ? null : posts.first.id,
      posts.isEmpty ? null : posts.last.id,
      stream.isEmpty ? null : stream.first,
      stream.isEmpty ? null : stream.last,
    );
    if (_postLookupCacheSignature == signature) return;

    final postIdToStreamIndex = <int, int>{};
    for (int i = 0; i < stream.length; i++) {
      postIdToStreamIndex[stream[i]] = i + 1;
    }

    final loadedPostIndexByNumber = <int, int>{};
    final streamIndexByPostNumber = <int, int>{};
    for (int i = 0; i < posts.length; i++) {
      final post = posts[i];
      loadedPostIndexByNumber[post.postNumber] = i;
      final streamIndex = postIdToStreamIndex[post.id];
      if (streamIndex != null) {
        streamIndexByPostNumber[post.postNumber] = streamIndex;
      }
    }

    _postLookupCacheSignature = signature;
    _postNumberToLoadedPostIndex = Map.unmodifiable(loadedPostIndexByNumber);
    _postNumberToStreamIndex = Map.unmodifiable(streamIndexByPostNumber);
  }

  void _onScroll() {
    if (_isRefreshing) return;

    _syncTopEdgeState();
    _controller.handleScroll();

    if (_isNestedView) {
      return;
    }

    final params = _params;
    final detailAsync = ref.read(topicDetailProvider(params));

    if (detailAsync.isLoading) return;

    final notifier = ref.read(topicDetailProvider(params).notifier);

    if (_controller.shouldLoadPrevious(
      notifier.hasMoreBefore,
      notifier.isLoadingPrevious,
    )) {
      notifier.loadPrevious();
    }

    if (_controller.shouldLoadMore(
      notifier.hasMoreAfter,
      notifier.isLoadingMore,
    )) {
      notifier.loadMore();
    }
  }

  void _syncTopEdgeState() {
    final sc = _controller.scrollController;
    final isAtTop =
        !sc.hasClients ||
        sc.position.pixels <= sc.position.minScrollExtent + 0.5;
    if (_isAtTopNotifier.value != isAtTop) {
      _isAtTopNotifier.value = isAtTop;
    }
  }

  void _updateStreamIndexForPostNumber(int postNumber) {
    // 记录当前浏览位置，用于布局切换时恢复
    _controller.updateCurrentPostNumber(postNumber);
    _updateEmbeddedDetailScrollPosition(postNumber);
    unawaited(
      ref
          .read(topicReadingStateServiceProvider)
          .saveState(
            topicId: widget.topicId,
            postNumber: postNumber,
            nestedView: _isNestedView,
          ),
    );

    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    if (detail == null) return;
    _ensurePostLookupCaches(detail);

    final streamIndex = _postNumberToStreamIndex[postNumber];
    if (streamIndex != null) {
      _controller.updateStreamIndex(streamIndex);
    }
  }

  void _updateInitialReadPostNumbers(Set<int> readPostNumbers) {
    if (setEquals(_lastInitialReadPostNumbers, readPostNumbers)) return;
    _lastInitialReadPostNumbers = readPostNumbers;
    _controller.setInitialReadPostNumbers(readPostNumbers);
  }

  void _updateSessionReadPostNumbers(Set<int> readPostNumbers) {
    if (setEquals(_lastSessionReadPostNumbers, readPostNumbers)) return;
    _lastSessionReadPostNumbers = readPostNumbers;
    _controller.setSessionReadPostNumbers(readPostNumbers);
  }

  void _updateVisiblePosts(Set<int> visiblePostNumbers) {
    _controller.updateVisiblePosts(visiblePostNumbers);
  }

  Future<void> _scrollToTop() async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;

    if (detail != null &&
        detail.postStream.posts.isNotEmpty &&
        detail.postStream.posts.first.postNumber == 1) {
      _controller.scrollToTop();
      return;
    }

    debugPrint('[TopicDetail] First post not loaded, reloading from post 1');
    _controller.prepareJumpToPost(1);
    _controller.skipNextJumpHighlight = false;

    final notifier = ref.read(topicDetailProvider(params).notifier);
    await notifier.reloadWithPostNumber(1);
  }

  /// J 键：向下滚动一个帖子的距离
  void _scrollToNextPost() => _navigatePostByPixels(1);

  /// K 键：向上滚动一个帖子的距离
  void _scrollToPreviousPost() => _navigatePostByPixels(-1);

  /// 帖子导航：直接用像素滚动，简单可靠
  void _navigatePostByPixels(int delta) {
    if (!mounted) return;
    final sc = _controller.scrollController;
    if (!sc.hasClients) return;

    final target = sc.offset + delta * 400;
    sc.animateTo(
      target.clamp(0.0, sc.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _rememberNestedJumpPosition(int postNumber) {
    _pendingNestedRestorePostNumber = postNumber;
    _controller.updateCurrentPostNumber(postNumber);
    _updateEmbeddedDetailScrollPosition(postNumber);
    unawaited(
      ref
          .read(topicReadingStateServiceProvider)
          .saveState(
            topicId: widget.topicId,
            postNumber: postNumber,
            nestedView: true,
          ),
    );
  }

  Future<void> _scrollToPost(
    int postNumber, {
    bool preserveNestedView = false,
  }) async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    if (detail == null) return;

    if (preserveNestedView && !_isNestedView && mounted) {
      setState(() => _isNestedView = true);
    }

    if (_isNestedView) {
      _expandKnownNestedAncestors(postNumber);
      final nestedScrollIndex = _nestedPostNumberToScrollIndex[postNumber];
      if (nestedScrollIndex != null &&
          _controller.scrollController.hasClients) {
        _rememberNestedJumpPosition(postNumber);
        _pendingNestedRestorePostNumber = null;
        await _controller.scrollController.scrollToIndex(
          nestedScrollIndex,
          preferPosition: AutoScrollPosition.middle,
          duration: const Duration(milliseconds: 180),
        );
        _controller.triggerHighlight(postNumber);
        return;
      }

      _rememberNestedJumpPosition(postNumber);
      final nestedParams = NestedTopicParams(topicId: widget.topicId);
      final nestedState = ref.read(nestedTopicProvider(nestedParams)).value;
      if (nestedState != null &&
          nestedState.hasMoreRoots &&
          !nestedState.isLoadingMore) {
        await ref
            .read(nestedTopicProvider(nestedParams).notifier)
            .loadMoreRoots();
      } else if (nestedState != null &&
          !nestedState.hasMoreRoots &&
          !nestedState.isLoadingMore &&
          mounted) {
        _pendingNestedRestorePostNumber = null;
        _controller.triggerHighlight(postNumber);
      }
      return;
    }

    final posts = detail.postStream.posts;
    _ensurePostLookupCaches(detail);
    final postIndex = _postNumberToLoadedPostIndex[postNumber] ?? -1;
    final notifier = ref.read(topicDetailProvider(params).notifier);

    if (postIndex == -1) {
      debugPrint(
        '[TopicDetail] Post $postNumber not in list, loading target post window',
      );
      _controller.skipNextJumpHighlight = false;

      if (notifier.isSummaryMode ||
          notifier.isAuthorOnlyMode ||
          notifier.isTopLevelMode) {
        _controller.prepareJumpToPost(postNumber);
        await _reloadWithFilterFallback(postNumber: postNumber);
      } else {
        final loadedIndex = await notifier.loadPostNumber(postNumber);
        if (!mounted) return;

        final loadedDetail = ref.read(topicDetailProvider(params)).value;
        final loadedPosts = loadedDetail?.postStream.posts;
        if (loadedIndex != -1 && loadedPosts != null) {
          if (_controller.isPostRendered(loadedIndex)) {
            await _controller.scrollToPost(postNumber, loadedPosts);
          } else {
            _controller.jumpToPostLocally(postNumber);
            setState(() {});
          }
          _controller.triggerHighlight(postNumber);
          return;
        }

        _controller.prepareJumpToPost(postNumber);
        await notifier.reloadWithPostNumber(postNumber);
      }
      return;
    }

    // 计算距离，如果距离过大直接使用本地跳转
    bool forceLocalJump = false;
    final currentVisibleIndex = _controller.currentVisibleStreamIndex;
    final targetStreamIndex = _postNumberToStreamIndex[postNumber] ?? -1;

    if (currentVisibleIndex != -1 && targetStreamIndex != -1) {
      if ((targetStreamIndex - currentVisibleIndex).abs() > 15) {
        forceLocalJump = true;
      }
    }

    if (!forceLocalJump && _controller.isPostRendered(postIndex)) {
      await _controller.scrollToPost(postNumber, posts);
    } else {
      int? anchorPostNumber;
      if (posts.length - 1 - postIndex < 20) {
        final safeIndex = (posts.length - 20).clamp(0, posts.length - 1);
        anchorPostNumber = posts[safeIndex].postNumber;
      }
      _controller.jumpToPostLocally(
        postNumber,
        anchorPostNumber: anchorPostNumber,
      );
      if (mounted) setState(() {});
    }
    _controller.triggerHighlight(postNumber);
  }

  Future<void> _scrollToStreamIndex(
    int streamIndex,
    int postId, {
    bool preserveNestedView = false,
  }) async {
    final realPostNumber = await _resolvePostNumberForJump(
      postId,
      fallbackPostNumber: streamIndex,
    );
    if (realPostNumber == null) return;

    _controller.updateStreamIndex(streamIndex);
    await _scrollToPost(realPostNumber, preserveNestedView: preserveNestedView);
    if (preserveNestedView && mounted && !_isNestedView) {
      setState(() => _isNestedView = true);
    }
  }

  void _expandKnownNestedAncestors(int targetPostNumber) {
    final nestedState = ref
        .read(nestedTopicProvider(NestedTopicParams(topicId: widget.topicId)))
        .value;
    if (nestedState == null) return;

    final ancestors = <int>{};
    for (final root in nestedState.roots) {
      if (_collectNestedAncestors(root, targetPostNumber, ancestors)) break;
    }
    if (ancestors.isEmpty) return;

    setState(() {
      _nestedExpandedPostNumbers = {
        ..._nestedExpandedPostNumbers,
        ...ancestors,
      };
    });
  }

  bool _collectNestedAncestors(
    NestedNode node,
    int targetPostNumber,
    Set<int> ancestors,
  ) {
    if (node.post.postNumber == targetPostNumber) return true;
    for (final child in node.children) {
      if (_collectNestedAncestors(child, targetPostNumber, ancestors)) {
        ancestors.add(node.post.postNumber);
        return true;
      }
    }
    return false;
  }

  Future<int?> _resolvePostNumberForJump(
    int postId, {
    required int fallbackPostNumber,
  }) async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    if (detail == null) return null;

    final posts = detail.postStream.posts;
    final postIndex = posts.indexWhere((p) => p.id == postId);

    if (postIndex != -1) {
      return posts[postIndex].postNumber;
    }

    debugPrint(
      '[TopicDetail] Post ID $postId not in loaded posts, fetching post info...',
    );

    try {
      final service = DiscourseService();
      final postStream = await service.getPosts(widget.topicId, [postId]);

      if (postStream.posts.isEmpty) {
        debugPrint('[TopicDetail] Failed to fetch post $postId');
        return fallbackPostNumber;
      }

      final targetPost = postStream.posts.first;
      final realPostNumber = targetPost.postNumber;
      debugPrint(
        '[TopicDetail] Got real post_number: $realPostNumber for post ID $postId',
      );
      return realPostNumber;
    } catch (e) {
      debugPrint('[TopicDetail] Error fetching post $postId: $e');
      return fallbackPostNumber;
    }
  }

  void _scrollToInitialPosition(List<Post> posts, int? dividerPostIndex) {
    _doInitialScroll(posts, dividerPostIndex, retryCount: 0);
  }

  void _doInitialScroll(
    List<Post> posts,
    int? dividerPostIndex, {
    required int retryCount,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (retryCount == 0) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (!mounted) return;

      if (!_controller.scrollController.hasClients) {
        if (retryCount < 5) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (mounted) {
            _doInitialScroll(
              posts,
              dividerPostIndex,
              retryCount: retryCount + 1,
            );
          }
          return;
        } else {
          if (mounted && !_controller.isPositioned) {
            _controller.markPositioned();
          }
          return;
        }
      }

      try {
        int? targetPostIndex;
        bool shouldHighlight = false;
        final hasFirstPost = posts.isNotEmpty && posts.first.postNumber == 1;
        final jumpTarget = _controller.jumpTargetPostNumber;
        final currentPostNumber = _controller.currentPostNumber;

        if (jumpTarget != null) {
          for (int i = 0; i < posts.length; i++) {
            if (posts[i].postNumber >= jumpTarget) {
              targetPostIndex = i;
              shouldHighlight = !_controller.skipNextJumpHighlight;
              break;
            }
          }
        } else if (dividerPostIndex != null &&
            dividerPostIndex < posts.length) {
          targetPostIndex = dividerPostIndex;
          shouldHighlight = true;
        } else if (currentPostNumber != null && currentPostNumber > 0) {
          for (int i = 0; i < posts.length; i++) {
            if (posts[i].postNumber >= currentPostNumber) {
              targetPostIndex = i;
              shouldHighlight = true;
              break;
            }
          }
        }

        if (targetPostIndex != null) {
          if (hasFirstPost && targetPostIndex == 0) {
            await _controller.scrollController.animateTo(
              _controller.scrollController.position.minScrollExtent,
              duration: const Duration(milliseconds: 1),
              curve: Curves.linear,
            );
          } else {
            await _controller.scrollController.scrollToIndex(
              _controller.scrollIndexForPostIndex(targetPostIndex),
              preferPosition: AutoScrollPosition.middle,
              duration: const Duration(milliseconds: 1),
            );
          }

          _controller.clearJumpTarget();
          _controller.skipNextJumpHighlight = false;

          if (shouldHighlight) {
            _controller.pendingHighlightPostNumber =
                posts[targetPostIndex].postNumber;
          }
        }
      } catch (e, stack) {
        debugPrint('[TopicDetail] Scroll error: $e\n$stack');
      } finally {
        if (mounted && !_controller.isPositioned) {
          _controller.markPositioned();
          if (_controller.pendingHighlightPostNumber != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _controller.consumePendingHighlight();
              }
            });
          }
        }
      }
    });
  }
}

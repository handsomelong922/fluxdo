part of '../topic_detail_page.dart';

// ignore_for_file: invalid_use_of_protected_member

/// 用户操作相关方法
extension _UserActions on _TopicDetailPageState {
  void _handleProgressGestureAction(
    ProgressGestureAction action,
    TopicDetail detail,
    TopicDetailNotifier notifier,
  ) {
    switch (action) {
      case ProgressGestureAction.none:
        return;
      case ProgressGestureAction.openTimeline:
        _showTimelineSheet(detail);
        return;
      case ProgressGestureAction.scrollToTop:
        unawaited(_scrollToTop());
        return;
      case ProgressGestureAction.jumpToUnread:
        final nextUnreadPostNumber = detail.lastReadPostNumber == null
            ? null
            : detail.lastReadPostNumber! + 1;
        if (nextUnreadPostNumber != null) {
          unawaited(_scrollToPost(nextUnreadPostNumber));
        } else {
          _showTimelineSheet(detail);
        }
        return;
      case ProgressGestureAction.nextPost:
        _scrollToNextPost();
        return;
      case ProgressGestureAction.previousPost:
        _scrollToPreviousPost();
        return;
      case ProgressGestureAction.reply:
        unawaited(_handleReply(null));
        return;
      case ProgressGestureAction.share:
        _shareTopic();
        return;
      case ProgressGestureAction.shareImage:
        _shareAsImage();
        return;
      case ProgressGestureAction.exportArticle:
        _showExportSheet();
        return;
      case ProgressGestureAction.openInBrowser:
        unawaited(_openInBrowser());
        return;
      case ProgressGestureAction.bookmark:
        unawaited(_handleBookmarkOptions(notifier));
        return;
      case ProgressGestureAction.readLater:
        _handleReadLater();
        return;
      case ProgressGestureAction.notification:
        showNotificationLevelSheet(
          context,
          detail.notificationLevel,
          (level) => _handleNotificationLevelChanged(notifier, level),
        );
        return;
      case ProgressGestureAction.filter:
        unawaited(_handleShowTopReplies());
        return;
      case ProgressGestureAction.toggleNestedView:
        unawaited(_setNestedView(!_isNestedView));
        return;
      case ProgressGestureAction.aiAssistant:
        _showAiAssistantSheet(detail);
        return;
      case ProgressGestureAction.readingSettings:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReadingSettingsPage()),
        );
        return;
      case ProgressGestureAction.search:
        _showTopicSearch();
        return;
      case ProgressGestureAction.refresh:
        unawaited(_handleRefresh());
        return;
    }
  }

  Future<void> _handleRefresh() async {
    final params = _params;
    final detailAsync = ref.read(topicDetailProvider(params));
    if (detailAsync.isLoading) return;

    final detail = ref.read(topicDetailProvider(params)).value;
    final notifier = ref.read(topicDetailProvider(params).notifier);
    final anchorPostNumber = _controller.getRefreshAnchorPostNumber(
      detail?.postStream.posts.firstOrNull?.postNumber ??
          _controller.currentPostNumber,
    );

    setState(() => _isRefreshing = true);
    await notifier.refreshWithPostNumber(anchorPostNumber);

    if (!mounted) return;
    setState(() => _isRefreshing = false);

    final updatedDetail = ref.read(topicDetailProvider(params)).value;
    if (updatedDetail == null) return;

    final isFiltered =
        notifier.isSummaryMode ||
        notifier.isAuthorOnlyMode ||
        notifier.isTopLevelMode;
    final hasAnchor = updatedDetail.postStream.posts.any(
      (p) => p.postNumber == anchorPostNumber,
    );
    if (!isFiltered || hasAnchor) {
      _controller.prepareRefresh(anchorPostNumber, skipHighlight: true);
    } else {
      _controller.clearJumpTarget();
    }
  }

  Future<void> _handleReply(Post? replyToPost, {String? initialContent}) async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;

    // 预加载草稿：在点击回复时就发起请求，利用 BottomSheet 动画时间并行加载
    final draftKey = Draft.replyKey(
      widget.topicId,
      replyToPostNumber: replyToPost?.postNumber,
    );
    final preloadedDraftFuture = DiscourseService().getDraft(draftKey);

    final newPost = await showReplySheet(
      context: context,
      topicId: widget.topicId,
      categoryId: detail?.categoryId,
      replyToPost: replyToPost,
      initialContent: initialContent,
      preloadedDraftFuture: preloadedDraftFuture,
      isPrivateMessageTopic: detail?.isPrivateMessage ?? false,
      isPmWithNonHumanUser: detail?.pmWithNonHumanUser ?? false,
    );

    if (newPost != null && mounted) {
      _updateNestedViewAfterReply(newPost);

      final addedToView = ref
          .read(topicDetailProvider(params).notifier)
          .addPost(newPost);

      if (addedToView) {
        // 回复面板关闭后键盘收起动画约 700ms，期间 viewport 高度持续增大、
        // maxScrollExtent 持续减小。若此时滚动，位置很快会超出 maxScrollExtent，
        // BouncingScrollPhysics 触发弹回，表现为底部弹跳。
        // 等待键盘完全收起（viewInsets.bottom == 0）后再滚动。
        _scrollAfterKeyboardDismiss(newPost.postNumber);
      } else {
        if (mounted) {
          ToastService.show(
            S.current.post_replySent,
            type: ToastType.success,
            actionLabel: S.current.post_replySentAction,
            onAction: () => _scrollToPost(newPost.postNumber),
          );
        }
      }
    }
  }

  /// 等待键盘完全收起后再滚动到指定帖子
  void _scrollAfterKeyboardDismiss(int postNumber) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).viewInsets.bottom > 0) {
        // 键盘仍在收起中，等下一帧再检查
        _scrollAfterKeyboardDismiss(postNumber);
      } else {
        _scrollToPost(postNumber);
      }
    });
  }

  Future<void> _handleEdit(Post post) async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;

    final updatedPost = await showEditSheet(
      context: context,
      topicId: widget.topicId,
      post: post,
      categoryId: detail?.categoryId,
      isPrivateMessageTopic: detail?.isPrivateMessage ?? false,
      isPmWithNonHumanUser: detail?.pmWithNonHumanUser ?? false,
    );

    if (updatedPost != null && mounted) {
      ref.read(topicDetailProvider(params).notifier).updatePost(updatedPost);
    }
  }

  Future<void> _handleEditTopic() async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    if (detail == null) return;

    final firstPost = detail.postStream.posts
        .where((p) => p.postNumber == 1)
        .firstOrNull;
    final firstPostId = detail.postStream.stream.isNotEmpty
        ? detail.postStream.stream.first
        : null;

    final result = await Navigator.of(context).push<EditTopicResult>(
      MaterialPageRoute(
        builder: (context) => EditTopicPage(
          topicDetail: detail,
          firstPost: firstPost,
          firstPostId: firstPostId,
        ),
      ),
    );

    if (result != null && mounted) {
      ref
          .read(topicDetailProvider(params).notifier)
          .updateTopicInfo(
            title: result.title,
            categoryId: result.categoryId,
            tags: result.tags,
            firstPost: result.updatedFirstPost,
          );
    }
  }

  Future<void> _quickAddTopicBookmark(TopicDetailNotifier notifier) async {
    final detail = ref.read(topicDetailProvider(_params)).value;
    if (detail == null || detail.bookmarked || _isTopicBookmarking) return;

    _isTopicBookmarking = true;
    try {
      await notifier.addTopicBookmark();
      unawaited(
        NotionBookmarkAutoSync.tryTriggerTopic(
          ref: ref,
          topicId: widget.topicId,
        ),
      );
    } catch (_) {
      // 快速收藏按用户要求保持静默，不打断阅读。
    } finally {
      _isTopicBookmarking = false;
    }
  }

  Future<void> _handleBookmarkOptions(TopicDetailNotifier notifier) async {
    final detail = ref.read(topicDetailProvider(_params)).value;
    if (detail == null) return;

    if (detail.bookmarked) {
      // 已书签 → 弹出编辑 BottomSheet
      final bookmarkId = detail.bookmarkId;
      if (bookmarkId == null) return;

      final result = await BookmarkEditSheet.show(
        context,
        bookmarkId: bookmarkId,
        initialName: detail.bookmarkName,
        initialReminderAt: detail.bookmarkReminderAt,
      );
      if (result == null || !mounted) return;

      if (result.deleted) {
        // BookmarkEditSheet 已调用 API 删除，刷新元数据同步本地状态
        notifier.reloadTopicMetadata();
      } else {
        notifier.updateTopicBookmarkMeta(
          name: result.name,
          reminderAt: result.reminderAt,
        );
      }
    } else {
      // 未书签 → 创建书签，然后弹出编辑 BottomSheet
      try {
        final newBookmarkId = await notifier.addTopicBookmark();
        if (!mounted) return;
        ToastService.showSuccess(S.current.common_bookmarkAdded);
        unawaited(
          NotionBookmarkAutoSync.tryTriggerTopic(
            ref: ref,
            topicId: widget.topicId,
          ),
        );

        // 弹出编辑 BottomSheet
        final result = await BookmarkEditSheet.show(
          context,
          bookmarkId: newBookmarkId,
        );
        if (result == null || !mounted) return;

        if (result.deleted) {
          // BookmarkEditSheet 已调用 API 删除，刷新元数据同步本地状态
          notifier.reloadTopicMetadata();
        } else {
          notifier.updateTopicBookmarkMeta(
            name: result.name,
            reminderAt: result.reminderAt,
          );
        }
      } on DioException catch (e) {
        debugPrint('[TopicDetail] 添加书签失败: $e');
      } catch (e, s) {
        AppErrorHandler.handleUnexpected(e, s);
      }
    }
  }

  void _handleReadLater() {
    final notifier = ref.read(readLaterProvider.notifier);
    final detail = ref.read(topicDetailProvider(_params)).value;

    if (notifier.contains(widget.topicId)) {
      // 已在列表中 → 移除
      notifier.remove(widget.topicId);
      ToastService.showSuccess(
        S.current.topicDetail_removeFromReadLaterSuccess,
      );
    } else {
      // 不在列表中 → 添加
      final item = ReadLaterItem(
        topicId: widget.topicId,
        title: detail?.title ?? widget.initialTitle ?? '',
        scrollToPostNumber: _controller.currentPostNumber,
        addedAt: DateTime.now(),
      );
      final success = notifier.add(item);
      if (success) {
        ToastService.showSuccess(S.current.topicDetail_addToReadLaterSuccess);
      } else {
        ToastService.showError(
          S.current.topicDetail_readLaterFull(maxReadLaterItems),
        );
      }
    }
  }

  void _handleVoteChanged(int newVoteCount, bool userVoted) {
    final params = _params;
    ref
        .read(topicDetailProvider(params).notifier)
        .updateTopicVote(newVoteCount, userVoted);
  }

  void _handleSharedIssueChanged(int newCount, bool userCreated) {
    final params = _params;
    ref
        .read(topicDetailProvider(params).notifier)
        .updateSharedIssue(newCount, userCreated: userCreated);
  }

  void _handleSolutionChanged(int postId, bool accepted) {
    final params = _params;
    ref
        .read(topicDetailProvider(params).notifier)
        .updatePostSolution(postId, accepted);
  }

  void _handleRefreshPost(int postId) {
    final params = _params;
    ref.read(topicDetailProvider(params).notifier).refreshPost(postId);
  }

  void _handleNotificationLevelChanged(
    TopicDetailNotifier notifier,
    TopicNotificationLevel level,
  ) async {
    try {
      await notifier.updateNotificationLevel(level);
      if (mounted) {
        ToastService.showSuccess(S.current.topicDetail_setToLevel(level.label));
      }
    } on DioException catch (e) {
      // 网络错误已由 ErrorInterceptor 处理
      debugPrint('[TopicDetail] 更新订阅级别失败: $e');
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
    }
  }

  void _shareTopic() {
    final user = ref.read(currentUserProvider).value;
    final username = user?.username ?? '';
    final prefs = ref.read(preferencesProvider);
    final url = ShareUtils.buildShareUrl(
      path: '/t/topic/${widget.topicId}',
      username: username,
      anonymousShare: prefs.anonymousShare,
    );
    SharePlus.instance.share(ShareParams(text: url));
  }

  Future<void> _openInBrowser() async {
    final user = ref.read(currentUserProvider).value;
    final username = user?.username ?? '';
    final prefs = ref.read(preferencesProvider);
    final url = ShareUtils.buildShareUrl(
      path: '/t/topic/${widget.topicId}',
      username: username,
      anonymousShare: prefs.anonymousShare,
    );

    final success = await launchInExternalBrowser(
      url,
      preferredBrowserPackageName: prefs.externalBrowserPackageName,
    );
    if (!success && mounted) {
      ToastService.showError(S.current.topicDetail_cannotOpenBrowser);
    }
  }

  void _shareAsImage() {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    if (detail == null) return;

    // 尝试获取已加载的主帖，如果没有则传 null，ShareImagePreview 会自动获取
    final firstPost = detail.postStream.posts
        .where((p) => p.postNumber == 1)
        .firstOrNull;
    ShareImagePreview.show(context, detail, post: firstPost);
  }

  void _sharePostAsImage(Post post) {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    if (detail == null) return;

    ShareImagePreview.show(context, detail, post: post);
  }

  void _showExportSheet() {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    if (detail == null) return;

    ExportSheet.show(context, detail);
  }

  /// 处理划词引用
  Future<void> _handleQuoteSelection(String selectedText, Post post) async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;
    final codePayload = CodeSelectionContextTracker.instance.decodePayload(
      selectedText,
    );
    final plainSelectedText = codePayload?.text ?? selectedText;

    // 尝试从 HTML 提取对应片段并转为 Markdown
    String markdown;
    final htmlFragment = HtmlTextMapper.extractHtml(
      post.cooked,
      plainSelectedText,
    );
    if (htmlFragment != null) {
      markdown = HtmlToMarkdown.convert(htmlFragment);
      // 转换失败时降级为纯文本
      if (markdown.trim().isEmpty) {
        markdown = codePayload != null
            ? CodeSelectionContextTracker.instance.toMarkdown(
                plainSelectedText,
                context: codePayload.context,
              )
            : plainSelectedText;
      }
    } else if (codePayload != null) {
      markdown = CodeSelectionContextTracker.instance.toMarkdown(
        plainSelectedText,
        context: codePayload.context,
      );
    } else {
      // 映射失败，使用纯文本
      markdown = plainSelectedText;
    }

    // 构建引用格式
    final quote = QuoteBuilder.build(
      markdown: markdown,
      username: post.username,
      postNumber: post.postNumber,
      topicId: widget.topicId,
    );

    // 预加载草稿
    final draftKey = Draft.replyKey(
      widget.topicId,
      replyToPostNumber: post.postNumber,
    );
    final preloadedDraftFuture = DiscourseService().getDraft(draftKey);

    // 打开回复框，预填引用内容（回复给被引用的帖子）
    final newPost = await showReplySheet(
      context: context,
      topicId: widget.topicId,
      categoryId: detail?.categoryId,
      replyToPost: post,
      initialContent: quote,
      preloadedDraftFuture: preloadedDraftFuture,
      isPrivateMessageTopic: detail?.isPrivateMessage ?? false,
      isPmWithNonHumanUser: detail?.pmWithNonHumanUser ?? false,
    );

    if (newPost != null && mounted) {
      _updateNestedViewAfterReply(newPost);

      final addedToView = ref
          .read(topicDetailProvider(params).notifier)
          .addPost(newPost);

      if (addedToView) {
        _scrollAfterKeyboardDismiss(newPost.postNumber);
      } else {
        if (mounted) {
          ToastService.show(
            S.current.post_replySent,
            type: ToastType.success,
            actionLabel: S.current.post_replySentAction,
            onAction: () => _scrollToPost(newPost.postNumber),
          );
        }
      }
    }
  }

  /// 处理图片引用（quote 已在 ImageContextMenu 中构建好）
  Future<void> _handleImageQuote(String quote, Post post) async {
    final params = _params;
    final detail = ref.read(topicDetailProvider(params)).value;

    // 预加载草稿
    final draftKey = Draft.replyKey(
      widget.topicId,
      replyToPostNumber: post.postNumber,
    );
    final preloadedDraftFuture = DiscourseService().getDraft(draftKey);

    // 打开回复框，预填引用内容
    final newPost = await showReplySheet(
      context: context,
      topicId: widget.topicId,
      categoryId: detail?.categoryId,
      replyToPost: post,
      initialContent: quote,
      preloadedDraftFuture: preloadedDraftFuture,
      isPrivateMessageTopic: detail?.isPrivateMessage ?? false,
      isPmWithNonHumanUser: detail?.pmWithNonHumanUser ?? false,
    );

    if (newPost != null && mounted) {
      _updateNestedViewAfterReply(newPost);

      final addedToView = ref
          .read(topicDetailProvider(params).notifier)
          .addPost(newPost);

      if (addedToView) {
        _scrollAfterKeyboardDismiss(newPost.postNumber);
      } else {
        if (mounted) {
          ToastService.show(
            S.current.post_replySent,
            type: ToastType.success,
            actionLabel: S.current.post_replySentAction,
            onAction: () => _scrollToPost(newPost.postNumber),
          );
        }
      }
    }
  }

  /// 回复成功后同步更新树形视图。
  void _updateNestedViewAfterReply(Post newPost) {
    if (!_isNestedView) return;
    ref
        .read(
          nestedTopicProvider(
            NestedTopicParams(topicId: widget.topicId),
          ).notifier,
        )
        .addNewPost(newPost, isOwnPost: true);
  }

  /// MessageBus created 事件只给 postId，这里后台拉完整帖子再交给树形视图去重。
  Future<void> _handleNestedCreated(int postId, int? userId) async {
    if (!_isNestedView) return;

    final nestedParams = NestedTopicParams(topicId: widget.topicId);
    final nestedAsync = ref.read(nestedTopicProvider(nestedParams));
    if (!nestedAsync.hasValue) return;

    try {
      final post = await DiscourseService().getPost(postId);
      if (!mounted) return;

      final currentUser = ref.read(currentUserProvider).value;
      final isOwnPost = userId != null && userId == currentUser?.id;
      ref
          .read(nestedTopicProvider(nestedParams).notifier)
          .addNewPost(post, isOwnPost: isOwnPost);
    } catch (e) {
      debugPrint('[TopicDetail] 树形视图加载新回复失败: $e');
    }
  }

  /// 处理帖子级别的 MessageBus 更新
  void _handlePostUpdate(TopicDetailNotifier notifier, PostUpdate update) {
    switch (update.type) {
      case TopicMessageType.created:
        notifier.onNewPostCreated(update.postId);
        if (_isNestedView) {
          unawaited(_handleNestedCreated(update.postId, update.userId));
        }
        break;
      case TopicMessageType.revised:
      case TopicMessageType.rebaked:
        notifier.refreshPost(update.postId, updatedAt: update.updatedAt);
        break;
      case TopicMessageType.acted:
        // 对齐 Discourse 官方 triggerChangedPost：acted 也传 updatedAt 做去重
        notifier.refreshPost(
          update.postId,
          preserveCooked: true,
          updatedAt: update.updatedAt,
        );
        break;
      case TopicMessageType.deleted:
        notifier.markPostDeleted(update.postId);
        break;
      case TopicMessageType.destroyed:
        notifier.removePost(update.postId);
        break;
      case TopicMessageType.recovered:
        notifier.markPostRecovered(update.postId);
        break;
      case TopicMessageType.liked:
      case TopicMessageType.unliked:
        notifier.updatePostLikes(update.postId, likesCount: update.likesCount);
        break;
      case TopicMessageType.boostAdded:
        if (update.boostData != null) {
          notifier.addBoostToPost(update.postId, update.boostData!);
        }
        break;
      case TopicMessageType.boostRemoved:
        if (update.boostId != null) {
          notifier.removeBoostFromPost(update.postId, update.boostId!);
        }
        break;
      case TopicMessageType.policyChanged:
        // policy 接受/撤销不改 post 内容，用 preserveCooked 避免重新跑 cook。
        // 不传 updatedAt：policy_change 服务端不会更新 post.updated_at。
        notifier.refreshPost(update.postId, preserveCooked: true);
        break;
      default:
        break;
    }
  }

  /// 处理 reload_topic 消息
  void _handleReloadTopic(TopicDetailNotifier notifier, bool refreshStream) {
    final anchor = _controller.getRefreshAnchorPostNumber(
      widget.scrollToPostNumber,
    );
    if (refreshStream) {
      notifier.refreshWithPostNumber(anchor);
    } else {
      notifier.reloadTopicMetadata();
    }
  }

  /// 切换树形视图，并同步为后续进入帖子的默认阅读布局。
  Future<void> _setNestedView(bool enabled) async {
    if (_isNestedView == enabled) return;
    await ref
        .read(preferencesProvider.notifier)
        .setDefaultNestedTopicView(enabled);
    if (!mounted) return;
    _nestedPostNumberToScrollIndex = const {};
    setState(() => _isNestedView = enabled);
    final postNumber = _controller.currentPostNumber;
    if (postNumber != null && postNumber > 0) {
      unawaited(
        ref
            .read(topicReadingStateServiceProvider)
            .saveState(
              topicId: widget.topicId,
              postNumber: postNumber,
              nestedView: enabled,
            ),
      );
    }
  }

  Future<void> _continueAiSummary(TopicSummary summary) async {
    final detail = ref.read(topicDetailProvider(_params)).value;
    if (detail == null) return;

    await ref
        .read(topicAiChatProvider(widget.topicId).notifier)
        .continueFromSummary(detail.title, summary.summarizedText);
    if (!mounted) return;

    final swipeMode = ref.read(preferencesProvider).aiSwipeEntry;
    if (swipeMode) {
      await _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _showAiAssistantSheet(detail);
    }
  }
}

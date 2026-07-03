part of '../post_footer_section.dart';

extension _PostFooterReplyActions on _PostFooterSectionState {
  Future<void> _loadInitialReplies() async {
    if (_replies.isNotEmpty) return;
    await _loadReplies();
  }

  Future<void> _loadReplies() async {
    if (_isLoadingRepliesNotifier.value) return;
    if (_repliesUnavailable) return;

    _isLoadingRepliesNotifier.value = true;
    try {
      final after = _replies.isNotEmpty ? _replies.last.postNumber : 1;
      final replies = await _service.getPostReplies(
        widget.post.id,
        after: after,
      );
      if (mounted) {
        _replies.addAll(replies);
        _isLoadingRepliesNotifier.value = false;
        _emitInlineRepliesState();
      }
    } on DioException catch (e) {
      // 网络错误已由 ErrorInterceptor 处理
      if (mounted) {
        if (e.response?.statusCode == 404) {
          _repliesUnavailable = true;
          _showRepliesNotifier.value = false;
          _emitInlineRepliesState();
        }
        _isLoadingRepliesNotifier.value = false;
      }
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
      if (mounted) {
        _isLoadingRepliesNotifier.value = false;
      }
    }
  }

  Future<void> _toggleReplies() async {
    // 过滤模式：打开弹框展示递归回复
    if (widget.useReplyDialog) {
      showPostRepliesSheet(
        context: context,
        post: widget.post,
        topicId: widget.topicId,
        onJumpToPost: widget.onJumpToPost,
      );
      return;
    }

    // 普通模式：内联展开直接回复
    if (_showRepliesNotifier.value) {
      _showRepliesNotifier.value = false;
      _emitInlineRepliesState();
      return;
    }

    if (_replies.isNotEmpty) {
      _showRepliesNotifier.value = true;
      _emitInlineRepliesState();
      return;
    }

    if (_repliesUnavailable) {
      return;
    }

    if (_isLoadingRepliesNotifier.value) return;

    _isLoadingRepliesNotifier.value = true;
    try {
      final replies = await _service.getPostReplies(widget.post.id, after: 1);
      if (mounted) {
        _replies.addAll(replies);
        _isLoadingRepliesNotifier.value = false;
        _showRepliesNotifier.value = true;
        _emitInlineRepliesState();
      }
    } on DioException catch (e) {
      // 网络错误已由 ErrorInterceptor 处理
      if (mounted) {
        if (e.response?.statusCode == 404) {
          _repliesUnavailable = true;
          _emitInlineRepliesState();
        }
        _isLoadingRepliesNotifier.value = false;
      }
    } catch (e, s) {
      AppErrorHandler.handleUnexpected(e, s);
      if (mounted) {
        _isLoadingRepliesNotifier.value = false;
      }
    }
  }
}

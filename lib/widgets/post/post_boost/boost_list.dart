import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/s.dart';
import '../../../models/topic.dart';
import '../../../providers/discourse_providers.dart';
import '../../../services/discourse/discourse_service.dart';
import '../../../services/toast_service.dart';
import 'boost_bubble.dart';
import 'boost_input.dart';

/// Boost 气泡列表
class BoostList extends ConsumerStatefulWidget {
  final Post post;
  final void Function(Post updatedPost)? onPostUpdated;

  const BoostList({
    super.key,
    required this.post,
    this.onPostUpdated,
  });

  @override
  ConsumerState<BoostList> createState() => _BoostListState();
}

class _BoostListState extends ConsumerState<BoostList> {
  final DiscourseService _service = DiscourseService();
  late List<Boost> _boosts;
  late bool _canBoost;

  @override
  void initState() {
    super.initState();
    _boosts = List.from(widget.post.boosts ?? []);
    _canBoost = widget.post.canBoost;
  }

  @override
  void didUpdateWidget(BoostList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      _boosts = List.from(widget.post.boosts ?? []);
      _canBoost = widget.post.canBoost;
    }
  }

  Future<void> _openInput() async {
    final raw = await showBoostInputSheet(context);
    if (raw == null || raw.isEmpty || !mounted) return;
    await _createBoost(raw);
  }

  Future<void> _createBoost(String raw) async {
    try {
      final boost = await _service.createBoost(widget.post.id, raw);
      if (!mounted) return;
      setState(() {
        _boosts.add(boost);
        _canBoost = false;
      });
      _notifyUpdate();
      ToastService.showSuccess(S.current.boost_created);
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(S.current.boost_failed);
    }
  }

  Future<void> _deleteBoost(Boost boost) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(S.current.boost_deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.current.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.current.common_delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteBoost(boost.id);
      if (!mounted) return;
      setState(() {
        _boosts.removeWhere((b) => b.id == boost.id);
        // 删除自己的 boost 后恢复 canBoost
        final currentUser = ref.read(currentUserProvider).value;
        if (currentUser != null && boost.user.username == currentUser.username) {
          _canBoost = true;
        }
      });
      _notifyUpdate();
      ToastService.showSuccess(S.current.boost_deleted);
    } catch (_) {
      if (!mounted) return;
      ToastService.showError(S.current.boost_deleteFailed);
    }
  }

  void _showBoostActions(Boost boost) {
    final currentUser = ref.read(currentUserProvider).value;
    final isOwn = currentUser != null && boost.user.username == currentUser.username;

    if (!isOwn && !boost.canDelete) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(S.current.common_delete),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteBoost(boost);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(S.current.common_cancel),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  void _notifyUpdate() {
    widget.onPostUpdated?.call(widget.post.copyWith(
      boosts: List.from(_boosts),
      canBoost: _canBoost,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBoosts = _boosts.isNotEmpty;

    if (!hasBoosts && !_canBoost) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 现有 Boost 气泡
          for (final boost in _boosts)
            BoostBubble(
              boost: boost,
              onTap: () => _showBoostActions(boost),
              onLongPress: () => _showBoostActions(boost),
            ),

          // 添加按钮
          if (_canBoost)
            Tooltip(
              message: 'Boost',
              child: GestureDetector(
                onTap: _openInput,
                child: Container(
                  height: 30,
                  width: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.rocket_launch_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/personal_navigation_preferences_provider.dart';
import 'morphing_dialog_anchor.dart';

/// 只分流卡片原有的点击回调，不额外参加手势竞技场。
/// 子按钮、链接、滚动获胜时，卡片 onTap 不执行，也就不会误开预览。
class TopicPreviewGestures extends ConsumerStatefulWidget {
  const TopicPreviewGestures({
    super.key,
    required this.onTap,
    required this.onPreview,
    required this.enableLongPress,
    required this.builder,
    this.bottomGap = 8,
  });

  final VoidCallback? onTap;
  final ValueChanged<BuildContext>? onPreview;
  final bool enableLongPress;
  final double bottomGap;
  final Widget Function(BuildContext, VoidCallback?, VoidCallback?) builder;

  @override
  ConsumerState<TopicPreviewGestures> createState() => _TopicPreviewGesturesState();
}

class _TopicPreviewGesturesState extends ConsumerState<TopicPreviewGestures> {
  bool _rightEdgeTap = false;
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    final rightEdgeEnabled = ref.watch(personalNavigationPreferencesProvider
        .select((value) => value.rightEdgeTapPreview));
    return MorphingDialogAnchor(
      enabled: widget.onPreview != null && (widget.enableLongPress || rightEdgeEnabled),
      bottomGap: widget.bottomGap,
      builder: (cardContext) => Listener(
        onPointerDown: (event) {
          // 多指及非主键不能沿用先前落点；键盘/辅助技术点击也正常打开。
          _rightEdgeTap = false;
          if (_pointer != null || event.buttons != kPrimaryButton) return;
          _pointer = event.pointer;
          final box = cardContext.findRenderObject();
          if (box is! RenderBox || !box.hasSize) return;
          final point = box.globalToLocal(event.position);
          _rightEdgeTap = rightEdgeEnabled &&
              point.dx >= box.size.width * .75 &&
              point.dx < box.size.width &&
              point.dy >= 0 && point.dy < box.size.height - widget.bottomGap;
        },
        onPointerUp: (event) {
          if (_pointer != event.pointer) return;
          _pointer = null;
          // TapRecognizer 在本次指针分发内完成回调，之后清理语义点击状态。
          scheduleMicrotask(() => _rightEdgeTap = false);
        },
        onPointerCancel: (_) {
          _pointer = null;
          _rightEdgeTap = false;
        },
        child: widget.builder(
          cardContext,
          widget.onTap == null ? null : () {
            final preview = _rightEdgeTap && widget.onPreview != null;
            _rightEdgeTap = false;
            if (preview) {
              widget.onPreview!(cardContext);
            } else {
              widget.onTap!();
            }
          },
          widget.enableLongPress && widget.onPreview != null
              ? () => widget.onPreview!(cardContext)
              : null,
        ),
      ),
    );
  }
}

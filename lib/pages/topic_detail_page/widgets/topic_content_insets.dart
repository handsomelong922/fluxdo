import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

const double kTopicBottomBarHeight = 48;
const double kTopicBottomBarLift = 8;

/// 中间楼层直接锚定时，让目标首行落在浮动工具栏下方。
double topicContentAnchor({
  required double viewportAnchor,
  required double topPadding,
  required double viewportHeight,
}) => viewportHeight > 0
    ? math.max(viewportAnchor, (topPadding / viewportHeight).clamp(0.0, 1.0))
    : viewportAnchor;

/// 保留原有目标对齐比例，但目标首行不能进入浮动按钮区域。
double topicContentRevealOffset({
  required RenderAbstractViewport viewport,
  required RenderObject target,
  required double topPadding,
  double alignment = 0,
}) => math.min(
  viewport.getOffsetToReveal(target, alignment).offset,
  viewport.getOffsetToReveal(target, 0).offset - topPadding,
);

/// 回复按钮在操作栏上方，不与居中的功能按钮重叠。
double topicReplyBottom(double bottomPadding, bool showBottomBar) =>
    bottomPadding +
    kTopicBottomBarLift +
    (showBottomBar ? kTopicBottomBarHeight + 8 : 16);

/// 只在滚动内容末尾留出真实控件的避让距离，不缩小正文视口。
double topicBottomContentPadding({
  required double bottomPadding,
  required bool hasReply,
  required bool hasProgress,
}) {
  final replyExtent = hasReply ? topicReplyBottom(0, true) + 56 : 0.0;
  final progressExtent = hasProgress
      ? kTopicBottomBarLift + kTopicBottomBarHeight + 16 + 40
      : 0.0;
  return bottomPadding +
      math.max(
        kTopicBottomBarLift + kTopicBottomBarHeight,
        math.max(replyExtent, progressExtent),
      );
}

/// 顶底浮动控件的避让随内容滚走，不再占据固定的空白栏。
class TopicContentInsets extends InheritedWidget {
  final EdgeInsets padding;

  const TopicContentInsets({
    super.key,
    required this.padding,
    required super.child,
  });

  static EdgeInsets paddingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TopicContentInsets>()
          ?.padding ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(TopicContentInsets oldWidget) =>
      padding != oldWidget.padding;
}

/// Scaffold 叠放顶栏时会把整条工具栏计入 MediaQuery.padding.top。
/// 这里仅保留系统安全区，工具栏避让交由列表自己的首部滚动空间处理。
class TopicContentBody extends StatelessWidget {
  final bool floatingAppBar;
  final double systemTopPadding;
  final bool hasReply;
  final bool hasProgress;
  final Widget child;

  const TopicContentBody({
    super.key,
    required this.floatingAppBar,
    required this.systemTopPadding,
    required this.hasReply,
    required this.hasProgress,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(top: floatingAppBar ? systemTopPadding : 0),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: SafeArea(
          top: false,
          bottom: false,
          child: TopicContentInsets(
            padding: EdgeInsets.only(
              top: floatingAppBar ? kToolbarHeight : 0,
              bottom: topicBottomContentPadding(
                bottomPadding: bottomPadding,
                hasReply: hasReply,
                hasProgress: hasProgress,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

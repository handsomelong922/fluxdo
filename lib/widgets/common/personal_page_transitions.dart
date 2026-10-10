import 'package:common_ui/common_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import '../../providers/personal_navigation_preferences_provider.dart';
import 'fullscreen_swipe_back.dart';

/// 默认保持原来的无整页淡化转场。自选动画只作用于当前页，不对前页
/// 叠加第二层透明度，也不截取会冻结正文加载状态的路由快照。
PageTransitionsTheme personalPageTransitionsTheme({
  required PageTransitionStyle style,
  required bool fullscreenSwipeBack,
}) {
  PageTransitionsBuilder builder(TargetPlatform platform) {
    final PageTransitionsBuilder original = platform == TargetPlatform.android
        ? const PredictiveBackCupertinoPageTransitionsBuilder()
        : const CupertinoPageTransitionsBuilder();
    PageTransitionsBuilder result = style == PageTransitionStyle.cupertino
        ? original
        : PersonalPageTransitionsBuilder(style: style, original: original);
    if (fullscreenSwipeBack &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS)) {
      result = FullscreenSwipeBackTransitionsBuilder(result);
    }
    return result;
  }

  return PageTransitionsTheme(builders: {
    for (final platform in TargetPlatform.values) platform: builder(platform),
  });
}

class PersonalPageTransitionsBuilder extends PageTransitionsBuilder {
  const PersonalPageTransitionsBuilder({required this.style, required this.original});

  final PageTransitionStyle style;
  final PageTransitionsBuilder original;

  // 无动画立即切页；手势仍可直接驱动路由控制器进度。
  @override
  Duration get transitionDuration => style == PageTransitionStyle.none
      ? Duration.zero : original.transitionDuration;
  @override
  Duration get reverseTransitionDuration => style == PageTransitionStyle.none
      ? Duration.zero : original.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // 对话框保持原竖向转场；全屏/边缘/系统返回保留既有控制器和探测器。
    if (route.fullscreenDialog || style == PageTransitionStyle.cupertino) {
      return original.buildTransitions(route, context, animation, secondaryAnimation, child);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: route.navigator!.userGestureInProgressNotifier,
      child: RepaintBoundary(child: child),
      builder: (context, gesture, page) {
        final custom = !gesture && !MediaQuery.disableAnimationsOf(context);
        // 整棵页面/探测器树始终保持相同类型，手势开始、取消、提交时
        // 只切换动画输入，不能重挂载正文或触发空白帧。
        final opacity = custom && style == PageTransitionStyle.fade
            ? animation.drive(CurveTween(curve: Curves.easeInOut))
            : const AlwaysStoppedAnimation<double>(1);
        final scale = custom && style == PageTransitionStyle.scale
            ? animation.drive(Tween<double>(begin: .94, end: 1)
                .chain(CurveTween(curve: Curves.easeOutCubic)))
            : const AlwaysStoppedAnimation<double>(1);
        return original.buildTransitions(
          route,
          context,
          gesture ? animation : const AlwaysStoppedAnimation<double>(1),
          gesture ? secondaryAnimation : const AlwaysStoppedAnimation<double>(0),
          FadeTransition(opacity: opacity, child: ScaleTransition(scale: scale, child: page)),
        );
      },
    );
  }
}

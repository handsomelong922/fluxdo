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
    if (style != PageTransitionStyle.cupertino) {
      return PersonalPageTransitionsBuilder(
        style: style,
        original: original,
        fullscreenSwipeBack: fullscreenSwipeBack &&
            (platform == TargetPlatform.android || platform == TargetPlatform.iOS),
      );
    }
    PageTransitionsBuilder result = original;
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
  const PersonalPageTransitionsBuilder({
    required this.style,
    required this.original,
    this.fullscreenSwipeBack = false,
  });

  final PageTransitionStyle style;
  final PageTransitionsBuilder original;
  final bool fullscreenSwipeBack;

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
    if (style == PageTransitionStyle.cupertino) {
      return original.buildTransitions(route, context, animation, secondaryAnimation, child);
    }
    final transition = ValueListenableBuilder<bool>(
      valueListenable: route.navigator!.userGestureInProgressNotifier,
      child: RepaintBoundary(child: child),
      builder: (context, gesture, page) {
        final enabled = !MediaQuery.disableAnimationsOf(context);
        // 手势直接使用线性进度，自动导航使用缓动。仅替换动画输入，
        // 整棵正文树在开始、取消、提交时都保持挂载，不叠加滑动转场。
        final opacity = enabled && style == PageTransitionStyle.fade
            ? (gesture ? animation : animation.drive(CurveTween(curve: Curves.easeInOut)))
            : const AlwaysStoppedAnimation<double>(1);
        final scale = enabled && style == PageTransitionStyle.scale
            ? (gesture ? animation : animation.drive(CurveTween(curve: Curves.easeOutCubic)))
                .drive(Tween<double>(begin: .94, end: 1))
            : const AlwaysStoppedAnimation<double>(1);
        return FadeTransition(
          opacity: opacity,
          child: ScaleTransition(scale: scale, child: page),
        );
      },
    );
    // common_ui 公开扩展点只接预测手势、不生成视觉，保留其取消/提交
    // 收尾及防重放逻辑。触摸侧滑同样只驱动 route 的唯一控制器。
    return wrapPredictiveBackForModalRoute(
      route: route,
      child: wrapSwipeBackForPageRoute(
        route: route,
        fullscreen: fullscreenSwipeBack,
        child: transition,
      ),
    );
  }
}

/// 普通页面的自定义路由也遵循全局选择；默认样式保留其 Hero 等专属
/// 转场。菜单、弹层和交互式媒体查看器不使用此入口。
PageRouteBuilder<T> personalPageRoute<T>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  required RouteTransitionsBuilder defaultTransitionsBuilder,
  Duration transitionDuration = const Duration(milliseconds: 300),
  Duration reverseTransitionDuration = const Duration(milliseconds: 300),
}) {
  final theme = Theme.of(context);
  final configured = theme.pageTransitionsTheme.builders[theme.platform];
  final selected = configured is PersonalPageTransitionsBuilder ? configured : null;
  late final PageRouteBuilder<T> route;
  route = PageRouteBuilder<T>(
    pageBuilder: pageBuilder,
    transitionDuration: selected?.transitionDuration ?? transitionDuration,
    reverseTransitionDuration: selected?.reverseTransitionDuration ?? reverseTransitionDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => selected == null
        ? defaultTransitionsBuilder(context, animation, secondaryAnimation, child)
        : selected.buildTransitions(route, context, animation, secondaryAnimation, child),
  );
  return route;
}

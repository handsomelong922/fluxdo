import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

enum AppPageTransition {
  platform('platform'),
  noSnapshot('no_snapshot'),
  fade('fade'),
  slide('slide'),
  scale('scale'),
  flip('flip'),
  none('none');

  const AppPageTransition(this.storageKey);

  final String storageKey;

  static AppPageTransition fromStorageKey(String? value) {
    for (final transition in values) {
      if (transition.storageKey == value) return transition;
    }
    return AppPageTransition.platform;
  }
}

@visibleForTesting
AppPageTransition effectiveAppPageTransition({
  required AppPageTransition transition,
  required bool reduceLoadingAnimations,
}) {
  if (reduceLoadingAnimations && transition == AppPageTransition.platform) {
    return AppPageTransition.noSnapshot;
  }
  return transition;
}

PageTransitionsTheme buildAppPageTransitionsTheme({
  required AppPageTransition transition,
  required bool reduceLoadingAnimations,
}) {
  final effectiveTransition = effectiveAppPageTransition(
    transition: transition,
    reduceLoadingAnimations: reduceLoadingAnimations,
  );
  final builder = switch (effectiveTransition) {
    AppPageTransition.platform => null,
    AppPageTransition.noSnapshot =>
      const _NoSnapshotZoomPageTransitionsBuilder(),
    AppPageTransition.fade => const _FadePageTransitionsBuilder(),
    AppPageTransition.slide => const _SlidePageTransitionsBuilder(),
    AppPageTransition.scale => const _ScalePageTransitionsBuilder(),
    AppPageTransition.flip => const _FlipPageTransitionsBuilder(),
    AppPageTransition.none => const _NoPageTransitionsBuilder(),
  };

  if (builder == null) {
    return const PageTransitionsTheme();
  }

  if (effectiveTransition == AppPageTransition.noSnapshot) {
    return const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoSnapshotZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: _NoSnapshotZoomPageTransitionsBuilder(),
        TargetPlatform.windows: _NoSnapshotZoomPageTransitionsBuilder(),
        TargetPlatform.linux: _NoSnapshotZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: _PopPassthroughCupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: _PopPassthroughCupertinoPageTransitionsBuilder(),
      },
    );
  }

  return PageTransitionsTheme(
    builders: {for (final platform in TargetPlatform.values) platform: builder},
  );
}

class _NoSnapshotZoomPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoSnapshotZoomPageTransitionsBuilder();

  static const _zoom = ZoomPageTransitionsBuilder(
    allowSnapshotting: false,
    allowEnterRouteSnapshotting: false,
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _PopGesturePassthrough(
      animation: animation,
      child: _zoom.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      ),
    );
  }
}

class _PopPassthroughCupertinoPageTransitionsBuilder
    extends CupertinoPageTransitionsBuilder {
  const _PopPassthroughCupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _PopGesturePassthrough(
      animation: animation,
      child: super.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      ),
    );
  }
}

class _FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return _PopGesturePassthrough(
      animation: animation,
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}

class _SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _SlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final textDirection = Directionality.of(context);
    final begin = textDirection == TextDirection.rtl
        ? const Offset(-1, 0)
        : const Offset(1, 0);
    return _PopGesturePassthrough(
      animation: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

class _ScalePageTransitionsBuilder extends PageTransitionsBuilder {
  const _ScalePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return _PopGesturePassthrough(
      animation: animation,
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

class _FlipPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FlipPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return _PopGesturePassthrough(
      animation: animation,
      child: AnimatedBuilder(
        animation: curved,
        child: child,
        builder: (context, child) {
          final angle = (1 - curved.value) * math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: Opacity(opacity: curved.value.clamp(0.0, 1.0), child: child),
          );
        },
      ),
    );
  }
}

class _NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _PopGesturePassthrough(animation: animation, child: child);
  }
}

class PopGesturePassthrough extends SingleChildRenderObjectWidget {
  const PopGesturePassthrough({
    super.key,
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderPopGesturePassthrough(animation);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPopGesturePassthrough renderObject,
  ) {
    renderObject.animation = animation;
  }
}

class _PopGesturePassthrough extends PopGesturePassthrough {
  const _PopGesturePassthrough({
    required super.animation,
    required super.child,
  });
}

class RenderPopGesturePassthrough extends RenderProxyBox {
  RenderPopGesturePassthrough(Animation<double> animation)
    : _animation = animation {
    _animation.addStatusListener(_handleStatusChanged);
  }

  Animation<double> _animation;

  Animation<double> get animation => _animation;

  set animation(Animation<double> value) {
    if (value == _animation) return;
    _animation.removeStatusListener(_handleStatusChanged);
    _animation = value;
    _animation.addStatusListener(_handleStatusChanged);
    markNeedsSemanticsUpdate();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_animation.status == AnimationStatus.reverse) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  void _handleStatusChanged(AnimationStatus status) {
    markNeedsSemanticsUpdate();
  }

  @override
  void dispose() {
    _animation.removeStatusListener(_handleStatusChanged);
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// 保留 Material 过渡动画，但在 route 退出动画期间放行底层手势。
class PopPassthroughMaterialPageRoute<T> extends MaterialPageRoute<T> {
  PopPassthroughMaterialPageRoute({
    required super.builder,
    super.settings,
    super.requestFocus,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
    super.barrierDismissible,
    super.traversalEdgeBehavior,
    super.directionalTraversalEdgeBehavior,
  });

  final ValueNotifier<bool> _ignorePointersAfterPop = ValueNotifier(false);

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) {
      _ignorePointersAfterPop.value = true;
    }
    return popped;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final transition = super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );

    return _PopPassthroughPointerGate(
      animation: animation,
      ignorePointersAfterPop: _ignorePointersAfterPop,
      child: transition,
    );
  }

  @override
  Widget buildModalBarrier() {
    final routeAnimation = animation;
    return _PopPassthroughPointerGate(
      animation: routeAnimation ?? const AlwaysStoppedAnimation(1),
      ignorePointersAfterPop: _ignorePointersAfterPop,
      child: super.buildModalBarrier(),
    );
  }

  @override
  void dispose() {
    _ignorePointersAfterPop.dispose();
    super.dispose();
  }
}

class _PopPassthroughPointerGate extends SingleChildRenderObjectWidget {
  const _PopPassthroughPointerGate({
    required this.animation,
    required this.ignorePointersAfterPop,
    required super.child,
  });

  final Animation<double> animation;
  final ValueListenable<bool> ignorePointersAfterPop;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPopPassthroughPointerGate(animation, ignorePointersAfterPop);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPopPassthroughPointerGate renderObject,
  ) {
    renderObject
      ..animation = animation
      ..ignorePointersAfterPop = ignorePointersAfterPop;
  }
}

class _RenderPopPassthroughPointerGate extends RenderProxyBox {
  _RenderPopPassthroughPointerGate(
    Animation<double> animation,
    ValueListenable<bool> ignorePointersAfterPop,
  ) : _animation = animation,
      _ignorePointersAfterPop = ignorePointersAfterPop {
    _animation.addStatusListener(_handleStatusChanged);
    _ignorePointersAfterPop.addListener(_handlePointerGateChanged);
  }

  Animation<double> _animation;
  ValueListenable<bool> _ignorePointersAfterPop;

  Animation<double> get animation => _animation;

  set animation(Animation<double> value) {
    if (value == _animation) return;

    _animation.removeStatusListener(_handleStatusChanged);
    _animation = value;
    _animation.addStatusListener(_handleStatusChanged);
    markNeedsSemanticsUpdate();
  }

  ValueListenable<bool> get ignorePointersAfterPop => _ignorePointersAfterPop;

  set ignorePointersAfterPop(ValueListenable<bool> value) {
    if (value == _ignorePointersAfterPop) return;

    _ignorePointersAfterPop.removeListener(_handlePointerGateChanged);
    _ignorePointersAfterPop = value;
    _ignorePointersAfterPop.addListener(_handlePointerGateChanged);
    markNeedsSemanticsUpdate();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_ignorePointersAfterPop.value ||
        _animation.status == AnimationStatus.reverse) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  void _handleStatusChanged(AnimationStatus status) {
    markNeedsSemanticsUpdate();
  }

  void _handlePointerGateChanged() {
    markNeedsSemanticsUpdate();
  }

  @override
  void dispose() {
    _animation.removeStatusListener(_handleStatusChanged);
    _ignorePointersAfterPop.removeListener(_handlePointerGateChanged);
    super.dispose();
  }
}

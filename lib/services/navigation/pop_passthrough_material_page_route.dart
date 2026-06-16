import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
    this.enableHorizontalPopGesture = false,
    this.horizontalPopGestureBlocker,
  });

  final bool enableHorizontalPopGesture;
  final ValueListenable<bool>? horizontalPopGestureBlocker;
  final ValueNotifier<bool> _ignorePointersAfterPop = ValueNotifier(false);
  final ValueNotifier<bool> _horizontalPopGestureActive = ValueNotifier(false);

  static ValueListenable<bool>? horizontalPopGestureActiveListenableOf(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<_HorizontalPopGestureScope>()
        ?.notifier;
  }

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) {
    if (enableHorizontalPopGesture) return false;
    return super.canTransitionFrom(previousRoute);
  }

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
    final transitionChild = enableHorizontalPopGesture
        ? _HorizontalPopGestureScope(
            notifier: _horizontalPopGestureActive,
            child: child,
          )
        : child;

    final transition = enableHorizontalPopGesture
        ? ValueListenableBuilder<bool>(
            valueListenable: _horizontalPopGestureActive,
            child: transitionChild,
            builder: (context, isHorizontalPopActive, child) {
              if (isHorizontalPopActive) {
                return _buildHorizontalPageTransition(
                  context,
                  animation,
                  child!,
                );
              }
              return super.buildTransitions(
                context,
                animation,
                secondaryAnimation,
                child!,
              );
            },
          )
        : super.buildTransitions(context, animation, secondaryAnimation, child);

    Widget result = _PopPassthroughPointerGate(
      animation: animation,
      ignorePointersAfterPop: _ignorePointersAfterPop,
      child: transition,
    );

    if (enableHorizontalPopGesture && !fullscreenDialog) {
      result = _HorizontalPopGestureDetector<T>(route: this, child: result);
    }

    return result;
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
    _horizontalPopGestureActive.dispose();
    super.dispose();
  }

  AnimationController? get _horizontalPopAnimationController => controller;

  Widget _buildHorizontalPageTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    if (isFirst) return child;

    final curved = popGestureInProgress
        ? animation
        : CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
    final textDirection = Directionality.of(context);
    final begin = textDirection == TextDirection.rtl
        ? const Offset(-1, 0)
        : const Offset(1, 0);
    return SlideTransition(
      position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
      child: child,
    );
  }
}

const double _horizontalPopMinDragDistance = 12.0;
const double _horizontalPopCommitThreshold = 0.68;
const double _horizontalPopMinFlingVelocity = 0.8;
const Duration _horizontalPopSettleDuration = Duration(milliseconds: 220);

class _HorizontalPopGestureDetector<T> extends StatefulWidget {
  const _HorizontalPopGestureDetector({
    required this.route,
    required this.child,
  });

  final PopPassthroughMaterialPageRoute<T> route;
  final Widget child;

  @override
  State<_HorizontalPopGestureDetector<T>> createState() =>
      _HorizontalPopGestureDetectorState<T>();
}

class _HorizontalPopGestureDetectorState<T>
    extends State<_HorizontalPopGestureDetector<T>> {
  final Map<int, VelocityTracker> _velocityTrackers = {};
  int? _pointer;
  Offset? _initialPosition;
  Offset? _lastPosition;
  bool _active = false;
  _HorizontalPopGestureController<T>? _popController;

  @override
  Widget build(BuildContext context) {
    final animation =
        widget.route.animation ?? const AlwaysStoppedAnimation<double>(1);
    return AnimatedBuilder(
      animation: Listenable.merge([
        animation,
        widget.route._ignorePointersAfterPop,
      ]),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: widget.child,
      ),
      builder: (context, child) {
        final ignorePointers =
            widget.route._ignorePointersAfterPop.value ||
            animation.status == AnimationStatus.reverse;
        return IgnorePointer(ignoring: ignorePointers, child: child);
      },
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.route.popGestureEnabled || _pointer != null) {
      return;
    }
    if (widget.route.horizontalPopGestureBlocker?.value == true) return;

    _pointer = event.pointer;
    _initialPosition = event.position;
    _lastPosition = event.position;
    _active = false;
    _velocityTrackers[event.pointer] = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;

    _velocityTrackers[event.pointer]?.addPosition(
      event.timeStamp,
      event.position,
    );

    if (widget.route.horizontalPopGestureBlocker?.value == true) {
      if (_active) {
        _popController?.cancel();
      }
      _resetPointer(event.pointer);
      return;
    }

    final initialPosition = _initialPosition;
    if (initialPosition == null) return;

    final offset = event.position - initialPosition;
    if (!_active) {
      if (_shouldReject(offset)) {
        _resetPointer(event.pointer);
        return;
      }

      if (!_shouldAccept(offset)) return;
      _active = true;
      _popController = _HorizontalPopGestureController<T>(route: widget.route);
    }

    final previousPosition = _lastPosition ?? event.position;
    _lastPosition = event.position;
    final width = _screenWidth;
    if (width <= 0) return;
    _popController?.dragUpdate(
      (event.position.dx - previousPosition.dx) / width,
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;

    if (_active) {
      final velocity =
          _velocityTrackers[event.pointer]?.getVelocity() ?? Velocity.zero;
      final width = _screenWidth;
      _popController?.dragEnd(
        width <= 0 ? 0.0 : velocity.pixelsPerSecond.dx / width,
      );
    }
    _resetPointer(event.pointer);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;

    if (_active) {
      _popController?.dragEnd(0.0);
    }
    _resetPointer(event.pointer);
  }

  bool _shouldReject(Offset offset) {
    final dx = offset.dx;
    final dy = offset.dy.abs();
    if (dx < 0 && dx.abs() > _horizontalPopMinDragDistance) return true;
    return dy > _horizontalPopMinDragDistance && dy > dx.abs();
  }

  bool _shouldAccept(Offset offset) {
    return offset.dx > _horizontalPopMinDragDistance &&
        offset.dx > offset.dy.abs();
  }

  double get _screenWidth {
    final initial = _initialPosition;
    final last = _lastPosition;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final width = view.physicalSize.width;
    final devicePixelRatio = view.devicePixelRatio;
    if (width > 0 && devicePixelRatio > 0) return width / devicePixelRatio;

    final distance = ((last ?? Offset.zero) - (initial ?? Offset.zero)).dx
        .abs();
    return distance > 0 ? distance : 1.0;
  }

  void _resetPointer(int pointer) {
    _velocityTrackers.remove(pointer);
    _pointer = null;
    _initialPosition = null;
    _lastPosition = null;
    _active = false;
    _popController = null;
  }
}

class _HorizontalPopGestureScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const _HorizontalPopGestureScope({
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);
}

class _HorizontalPopGestureController<T> {
  _HorizontalPopGestureController({required this.route}) {
    route._horizontalPopGestureActive.value = true;
    route.navigator!.didStartUserGesture();
  }

  final PopPassthroughMaterialPageRoute<T> route;

  AnimationController get _controller =>
      route._horizontalPopAnimationController!;
  NavigatorState get _navigator => route.navigator!;

  void dragUpdate(double delta) {
    _controller.value -= delta;
  }

  void dragEnd(double velocity) {
    const curve = Curves.fastEaseInToSlowEaseOut;
    final isCurrent = route.isCurrent;
    final bool shouldRestore;

    if (!isCurrent) {
      shouldRestore = route.isActive;
    } else if (velocity.abs() >= _horizontalPopMinFlingVelocity) {
      shouldRestore = velocity <= 0;
    } else {
      shouldRestore = _controller.value > _horizontalPopCommitThreshold;
    }

    if (shouldRestore) {
      _controller.animateTo(
        1.0,
        duration: _horizontalPopSettleDuration,
        curve: curve,
      );
    } else {
      if (isCurrent) {
        _navigator.pop();
      }

      if (_controller.isAnimating) {
        _controller.animateBack(
          0.0,
          duration: _horizontalPopSettleDuration,
          curve: curve,
        );
      }
    }

    if (_controller.isAnimating) {
      late AnimationStatusListener listener;
      listener = (status) {
        if (status.isAnimating) return;
        if (shouldRestore) {
          route._horizontalPopGestureActive.value = false;
        }
        _navigator.didStopUserGesture();
        _controller.removeStatusListener(listener);
      };
      _controller.addStatusListener(listener);
    } else {
      if (shouldRestore) {
        route._horizontalPopGestureActive.value = false;
      }
      _navigator.didStopUserGesture();
    }
  }

  void cancel() {
    const curve = Curves.fastEaseInToSlowEaseOut;
    _controller.animateTo(
      1.0,
      duration: _horizontalPopSettleDuration,
      curve: curve,
    );

    late AnimationStatusListener listener;
    listener = (status) {
      if (status.isAnimating) return;
      route._horizontalPopGestureActive.value = false;
      _navigator.didStopUserGesture();
      _controller.removeStatusListener(listener);
    };
    _controller.addStatusListener(listener);
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

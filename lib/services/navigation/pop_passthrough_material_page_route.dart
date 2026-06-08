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
  });

  final bool enableHorizontalPopGesture;
  final ValueNotifier<bool> _ignorePointersAfterPop = ValueNotifier(false);

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
    final transition = enableHorizontalPopGesture
        ? _buildHorizontalPageTransition(context, animation, child)
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

const double _horizontalPopMinDragDistance = 18.0;
const double _horizontalPopMinFlingVelocity = 1.0;
const Duration _horizontalPopSettleDuration = Duration(milliseconds: 280);

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
  late final _RightSwipePopGestureRecognizer _recognizer =
      _RightSwipePopGestureRecognizer(
        enabledCallback: () => widget.route.popGestureEnabled,
        onStartPopGesture: () =>
            _HorizontalPopGestureController<T>(route: widget.route),
      );

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation =
        widget.route.animation ?? const AlwaysStoppedAnimation<double>(1);
    return AnimatedBuilder(
      animation: Listenable.merge([
        animation,
        widget.route._ignorePointersAfterPop,
      ]),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
            ),
          ),
        ],
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
    _recognizer.addPointer(event);
  }
}

class _RightSwipePopGestureRecognizer extends OneSequenceGestureRecognizer {
  _RightSwipePopGestureRecognizer({
    required this.enabledCallback,
    required this.onStartPopGesture,
  });

  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_HorizontalPopGestureController<dynamic>> onStartPopGesture;

  final Map<int, VelocityTracker> _velocityTrackers = {};
  int? _pointer;
  Offset? _initialPosition;
  Offset? _lastPosition;
  bool _accepted = false;
  _HorizontalPopGestureController<dynamic>? _popController;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!enabledCallback() || _pointer != null) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
      return;
    }

    super.addAllowedPointer(event);
    _pointer = event.pointer;
    _initialPosition = event.position;
    _lastPosition = event.position;
    _accepted = false;
    _velocityTrackers[event.pointer] = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      _handleMove(event);
    } else if (event is PointerUpEvent) {
      _handlePointerUp(event);
    } else if (event is PointerCancelEvent) {
      _handlePointerCancel(event);
    }
  }

  void _handleMove(PointerMoveEvent event) {
    _velocityTrackers[event.pointer]?.addPosition(
      event.timeStamp,
      event.position,
    );
    final initialPosition = _initialPosition;
    if (initialPosition == null) return;

    final offset = event.position - initialPosition;
    if (!_accepted) {
      if (_shouldReject(offset)) {
        resolvePointer(event.pointer, GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }

      if (!_shouldAccept(offset)) return;
      resolvePointer(event.pointer, GestureDisposition.accepted);
    }

    final previousPosition = _lastPosition ?? event.position;
    _lastPosition = event.position;
    final width = _screenWidth;
    if (width <= 0) return;
    _popController?.dragUpdate(
      (event.position.dx - previousPosition.dx) / width,
    );
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

  void _handlePointerUp(PointerUpEvent event) {
    final velocity =
        _velocityTrackers[event.pointer]?.getVelocity() ?? Velocity.zero;
    final width = _screenWidth;
    _popController?.dragEnd(
      width <= 0 ? 0.0 : velocity.pixelsPerSecond.dx / width,
    );
    stopTrackingPointer(event.pointer);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _popController?.dragEnd(0.0);
    stopTrackingPointer(event.pointer);
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

  @override
  void acceptGesture(int pointer) {
    if (pointer != _pointer || _accepted) return;
    _accepted = true;
    _popController = onStartPopGesture();
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    _popController?.dragEnd(0.0);
    _popController = null;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _velocityTrackers.remove(pointer);
    _pointer = null;
    _initialPosition = null;
    _lastPosition = null;
    _accepted = false;
    _popController = null;
  }

  @override
  String get debugDescription => 'right swipe pop';
}

class _HorizontalPopGestureController<T> {
  _HorizontalPopGestureController({required this.route}) {
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
      shouldRestore = _controller.value > 0.5;
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
        _navigator.didStopUserGesture();
        _controller.removeStatusListener(listener);
      };
      _controller.addStatusListener(listener);
    } else {
      _navigator.didStopUserGesture();
    }
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

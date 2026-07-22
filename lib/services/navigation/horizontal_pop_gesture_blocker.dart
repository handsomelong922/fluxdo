import 'package:flutter/material.dart';

class HorizontalPopGestureBlocker {
  const HorizontalPopGestureBlocker._();

  static final ValueNotifier<bool> activeListenable = ValueNotifier(false);
  static final Map<Object, Set<int>> _pointersBySource = Map.identity();

  static void begin(Object source, int pointer) {
    _pointersBySource.putIfAbsent(source, () => <int>{}).add(pointer);
    _sync();
  }

  static void end(Object source, int pointer) {
    final pointers = _pointersBySource[source];
    pointers?.remove(pointer);
    if (pointers?.isEmpty ?? false) {
      _pointersBySource.remove(source);
    }
    _sync();
  }

  static void clear(Object source) {
    _pointersBySource.remove(source);
    _sync();
  }

  static void _sync() {
    activeListenable.value = _pointersBySource.isNotEmpty;
  }
}

class HorizontalPopGestureBlockerRegion extends StatefulWidget {
  const HorizontalPopGestureBlockerRegion({super.key, required this.child});

  final Widget child;

  @override
  State<HorizontalPopGestureBlockerRegion> createState() =>
      _HorizontalPopGestureBlockerRegionState();
}

class _HorizontalPopGestureBlockerRegionState
    extends State<HorizontalPopGestureBlockerRegion> {
  @override
  void dispose() {
    HorizontalPopGestureBlocker.clear(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        HorizontalPopGestureBlocker.begin(this, event.pointer);
      },
      onPointerUp: (event) {
        HorizontalPopGestureBlocker.end(this, event.pointer);
      },
      onPointerCancel: (event) {
        HorizontalPopGestureBlocker.end(this, event.pointer);
      },
      child: widget.child,
    );
  }
}

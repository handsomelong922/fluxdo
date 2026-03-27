import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/preferences_provider.dart';

/// 对话框背景模糊滤镜
final _blurFilter = ImageFilter.blur(
  sigmaX: 10,
  sigmaY: 10,
  tileMode: TileMode.mirror,
);

/// 根据用户偏好获取模糊滤镜
ImageFilter? _getBlurFilter(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final prefs = container.read(preferencesProvider);
  return prefs.dialogBlur ? _blurFilter : null;
}

/// 替代 [showDialog]，自动根据用户偏好添加背景高斯模糊。
///
/// API 与 [showDialog] 基本一致，额外支持 [blur] 参数控制是否启用模糊
/// （默认 true，即跟随用户设置；设为 false 则强制不模糊）。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  bool blur = true,
}) {
  final filter = blur ? _getBlurFilter(context) : null;

  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: useRootNavigator).context,
  );

  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _BlurRawDialogRoute<T>(
      pageBuilder: (buildContext, animation, secondaryAnimation) {
        final Widget pageChild = Builder(builder: builder);
        return themes.wrap(SafeArea(child: pageChild));
      },
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? Colors.black54,
      barrierLabel:
          barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: _buildMaterialDialogTransitions,
      settings: routeSettings,
      filter: filter,
    ),
  );
}

/// 替代 [showGeneralDialog]，自动根据用户偏好添加背景高斯模糊。
Future<T?> showAppGeneralDialog<T extends Object?>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  bool barrierDismissible = false,
  String? barrierLabel,
  Color barrierColor = const Color(0x80000000),
  Duration transitionDuration = const Duration(milliseconds: 200),
  RouteTransitionsBuilder? transitionBuilder,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  bool blur = true,
}) {
  final filter = blur ? _getBlurFilter(context) : null;

  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _BlurRawDialogRoute<T>(
      pageBuilder: pageBuilder,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor: barrierColor,
      transitionDuration: transitionDuration,
      transitionBuilder: transitionBuilder,
      settings: routeSettings,
      filter: filter,
    ),
  );
}

/// Material Design 标准对话框过渡动画
Widget _buildMaterialDialogTransitions(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
}

/// 替代 [showModalBottomSheet]，自动根据用户偏好添加背景高斯模糊。
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool blur = true,
}) {
  final blurFilter = blur ? _getBlurFilter(context) : null;
  final NavigatorState navigator =
      Navigator.of(context, rootNavigator: useRootNavigator);

  return navigator.push(
    _BlurModalBottomSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: isScrollControlled,
      barrierLabel:
          barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      modalBarrierColor:
          barrierColor ??
          Theme.of(context).bottomSheetTheme.modalBarrierColor,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      settings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      useSafeArea: useSafeArea,
      sheetAnimationStyle: sheetAnimationStyle,
      blurFilter: blurFilter,
    ),
  );
}

/// 支持 filter 的 ModalBottomSheetRoute 子类
class _BlurModalBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  final ImageFilter? blurFilter;

  _BlurModalBottomSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.constraints,
    super.modalBarrierColor,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    required super.isScrollControlled,
    super.settings,
    super.transitionAnimationController,
    super.anchorPoint,
    super.useSafeArea,
    super.sheetAnimationStyle,
    this.blurFilter,
  });

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    if (blurFilter != null) {
      return BackdropFilter(filter: blurFilter!, child: barrier);
    }
    return barrier;
  }
}

/// 支持 filter 的 RawDialogRoute 替代
class _BlurRawDialogRoute<T> extends PopupRoute<T> {
  final RoutePageBuilder pageBuilder;
  final bool _barrierDismissible;
  final String? _barrierLabel;
  final Color _barrierColor;
  final Duration _transitionDuration;
  final RouteTransitionsBuilder? _transitionBuilder;

  _BlurRawDialogRoute({
    required this.pageBuilder,
    required bool barrierDismissible,
    String? barrierLabel,
    required Color barrierColor,
    required Duration transitionDuration,
    RouteTransitionsBuilder? transitionBuilder,
    super.settings,
    super.filter,
  })  : _barrierDismissible = barrierDismissible,
        _barrierLabel = barrierLabel,
        _barrierColor = barrierColor,
        _transitionDuration = transitionDuration,
        _transitionBuilder = transitionBuilder;

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  String? get barrierLabel => _barrierLabel;

  @override
  Color get barrierColor => _barrierColor;

  @override
  Duration get transitionDuration => _transitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return pageBuilder(context, animation, secondaryAnimation);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_transitionBuilder != null) {
      return _transitionBuilder!(context, animation, secondaryAnimation, child);
    }
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.linear),
      child: child,
    );
  }
}

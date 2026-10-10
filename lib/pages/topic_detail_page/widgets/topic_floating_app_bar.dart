import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 普通话题页只有浮动操作按钮，空白处允许点击、拖动下方正文。
class TopicFloatingAppBar extends AppBar {
  TopicFloatingAppBar({
    super.key,
    required Brightness brightness,
    super.automaticallyImplyLeading,
    super.leading,
    super.actions,
  }) : super(
         elevation: 0,
         scrolledUnderElevation: 0,
         shadowColor: Colors.transparent,
         surfaceTintColor: Colors.transparent,
         backgroundColor: Colors.transparent,
         forceMaterialTransparency: true,
         systemOverlayStyle: SystemUiOverlayStyle(
           statusBarColor: Colors.transparent,
           statusBarIconBrightness: brightness == Brightness.dark
               ? Brightness.light
               : Brightness.dark,
           statusBarBrightness: brightness,
           systemStatusBarContrastEnforced: false,
           systemNavigationBarColor: Colors.transparent,
           // 与应用全局样式一致，兼容 Android 28 的分隔线颜色限制。
           systemNavigationBarDividerColor: Colors.transparent.withAlpha(1),
           systemNavigationBarIconBrightness: brightness == Brightness.dark
               ? Brightness.light
               : Brightness.dark,
           systemNavigationBarContrastEnforced: false,
         ),
       );
}

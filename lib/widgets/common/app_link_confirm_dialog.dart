import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/local_notification_service.dart';

/// 已知应用 scheme 的友好名称
const _knownApps = {
  'twitter': 'Twitter',
  'x': 'X (Twitter)',
  'telegram': 'Telegram',
  'tg': 'Telegram',
  'whatsapp': 'WhatsApp',
  'weixin': '微信',
  'wechat': '微信',
  'alipay': '支付宝',
  'alipays': '支付宝',
  'taobao': '淘宝',
  'zhihu': '知乎',
  'bilibili': 'Bilibili',
  'snssdk1128': '抖音',
  'snssdk1233': 'TikTok',
  'mailto': '邮件',
  'tel': '电话',
  'sms': '短信',
  'market': 'Play 商店',
  'geo': '地图',
  'googlechrome': 'Chrome',
  'firefox': 'Firefox',
  'line': 'LINE',
  'kakaolink': 'KakaoTalk',
  'fb': 'Facebook',
  'instagram': 'Instagram',
  'youtube': 'YouTube',
  'spotify': 'Spotify',
  'discord': 'Discord',
  'bdnetdisk': '百度网盘',
  'baidunetdisk': '百度网盘',
  'baiduyun': '百度网盘',
  'baiduboxapp': '百度',
  'qqmap': '腾讯地图',
  'iosamap': '高德地图',
  'amapuri': '高德地图',
  'androidamap': '高德地图',
  'waze': 'Waze',
  'mqqapi': 'QQ',
  'mqq': 'QQ',
  'tim': 'TIM',
  'weibo': '微博',
  'sinaweibo': '微博',
  'dingtalk': '钉钉',
  'pinduoduo': '拼多多',
  'jdmobile': '京东',
  'openapp.jdmobile': '京东',
  'suning': '苏宁',
  'eleme': '饿了么',
  'meituanwaimai': '美团外卖',
  'imeituan': '美团',
  'dianping': '大众点评',
  'ctrip': '携程',
  'taobaotravel': '飞猪',
  'xhsdiscover': '小红书',
  'douyinopensdk': '抖音',
  'kwai': '快手',
  'snssdk32': '今日头条',
  'vnd.youtube': 'YouTube',
  'com.douban.frodo': '豆瓣',
};

// ==================== 横幅状态管理 ====================

OverlayEntry? _currentEntry;
Timer? _dismissTimer;
AnimationController? _currentController;
Completer<bool?>? _currentCompleter;

/// 显示应用链接确认横幅（Chrome 风格，顶部 Overlay）
///
/// 自动 8 秒后消失，支持上滑关闭。
/// 返回 `true` = 用户点击「继续」，`false`/`null` = 取消/超时。
Future<bool?> showAppLinkConfirmDialog(
  BuildContext context,
  String url, {
  String? appName,
  Uint8List? appIcon,
}) {
  // 移除上一个横幅
  _dismiss(animate: false);

  final completer = Completer<bool?>();
  _currentCompleter = completer;

  final overlay = navigatorKey.currentState?.overlay;
  if (overlay == null) {
    completer.complete(null);
    return completer.future;
  }

  final displayName = appName ?? _guessAppName(url);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AppLinkBanner(
      displayName: displayName,
      appIcon: appIcon,
      onControllerCreated: (c) {
        _currentController = c;
        c.forward();
      },
      onConfirm: () => _complete(true),
      onDismiss: () => _complete(false),
    ),
  );

  _currentEntry = entry;
  overlay.insert(entry);

  // 8 秒后自动消失
  _dismissTimer = Timer(const Duration(seconds: 8), () {
    _complete(null);
  });

  return completer.future;
}

void _complete(bool? value) {
  _dismissTimer?.cancel();
  _dismissTimer = null;

  final completer = _currentCompleter;
  _currentCompleter = null;

  final controller = _currentController;
  final entry = _currentEntry;
  _currentEntry = null;
  _currentController = null;

  if (controller != null && entry != null) {
    controller.reverse().then((_) {
      entry.remove();
      controller.dispose();
    });
  }

  if (completer != null && !completer.isCompleted) {
    completer.complete(value);
  }
}

void _dismiss({required bool animate}) {
  _dismissTimer?.cancel();
  _dismissTimer = null;

  final completer = _currentCompleter;
  _currentCompleter = null;

  if (animate && _currentController != null) {
    final controller = _currentController!;
    final entry = _currentEntry;
    _currentEntry = null;
    _currentController = null;
    controller.reverse().then((_) {
      entry?.remove();
      controller.dispose();
    });
  } else {
    _currentController?.dispose();
    _currentController = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }

  if (completer != null && !completer.isCompleted) {
    completer.complete(null);
  }
}

// ==================== 横幅 Widget ====================

class _AppLinkBanner extends StatefulWidget {
  final String displayName;
  final Uint8List? appIcon;
  final void Function(AnimationController) onControllerCreated;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _AppLinkBanner({
    required this.displayName,
    this.appIcon,
    required this.onControllerCreated,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  State<_AppLinkBanner> createState() => _AppLinkBannerState();
}

class _AppLinkBannerState extends State<_AppLinkBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  double _dragOffset = 0;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    widget.onControllerCreated(_controller);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(-double.infinity, 0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dismissing) return;
    if (_dragOffset < -40 || details.velocity.pixelsPerSecond.dy < -200) {
      _dismissing = true;
      widget.onDismiss();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    return Positioned(
      top: mediaQuery.padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Opacity(
              opacity: _dragOffset < 0
                  ? (1.0 + _dragOffset / 120).clamp(0.0, 1.0)
                  : 1.0,
              child: GestureDetector(
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(16),
                  color: colorScheme.surface,
                  surfaceTintColor: colorScheme.surfaceTint,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: Row(
                      children: [
                        // 应用图标
                        _buildIcon(colorScheme),
                        const SizedBox(width: 12),
                        // 文字
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '继续访问${widget.displayName}？',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '此网站想打开${widget.displayName}应用',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 继续按钮
                        FilledButton(
                          onPressed: widget.onConfirm,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text('继续'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ColorScheme colorScheme) {
    if (widget.appIcon != null && widget.appIcon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          widget.appIcon!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.open_in_new_rounded,
        color: colorScheme.onPrimaryContainer,
        size: 20,
      ),
    );
  }
}

// ==================== 工具函数 ====================

/// 根据 URL 猜测应用名称
String _guessAppName(String url) {
  if (url.startsWith('intent://')) {
    final fragmentIndex = url.indexOf('#Intent;');
    if (fragmentIndex != -1) {
      final params = url.substring(fragmentIndex + 8);
      for (final param in params.split(';')) {
        if (param.startsWith('package=')) {
          return param.substring(8);
        }
        if (param.startsWith('scheme=')) {
          final scheme = param.substring(7);
          if (_knownApps.containsKey(scheme)) {
            return _knownApps[scheme]!;
          }
        }
      }
    }
    return '外部应用';
  }

  final uri = Uri.tryParse(url);
  if (uri != null) {
    return _knownApps[uri.scheme] ?? uri.scheme;
  }

  return '外部应用';
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/time_utils.dart';

class _RelativeTimeRefreshTicker {
  _RelativeTimeRefreshTicker._();

  static final _RelativeTimeRefreshTicker instance =
      _RelativeTimeRefreshTicker._();

  static const Duration _refreshInterval = Duration(minutes: 1);

  final ValueNotifier<int> tick = ValueNotifier<int>(0);
  Timer? _timer;
  int _listenerCount = 0;

  void attach() {
    _listenerCount += 1;
    _timer ??= Timer.periodic(_refreshInterval, (_) {
      tick.value += 1;
    });
  }

  void detach() {
    if (_listenerCount > 0) {
      _listenerCount -= 1;
    }
    if (_listenerCount == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

/// 时间显示样式
enum TimeDisplayStyle {
  /// 纯相对时间："3小时前"
  relative,

  /// 前缀模式："创建于 3小时前"
  prefixed,

  /// 后缀模式："3小时前 获得"
  suffixed,
}

/// 可自动刷新的相对时间 Widget
///
/// 特性：
/// - 长按 Tooltip 显示精确时间
/// - 使用全局共享时钟，避免列表中每个条目各自持有 Timer
/// - 页面不可见时跳过无意义的重建
class RelativeTimeText extends StatefulWidget {
  const RelativeTimeText({
    super.key,
    required this.dateTime,
    this.style,
    this.displayStyle = TimeDisplayStyle.relative,
    this.prefix,
    this.suffix,
  });

  /// 要显示的时间
  final DateTime? dateTime;

  /// 文本样式
  final TextStyle? style;

  /// 显示样式
  final TimeDisplayStyle displayStyle;

  /// 前缀文本，displayStyle 为 prefixed 时使用
  final String? prefix;

  /// 后缀文本，displayStyle 为 suffixed 时使用
  final String? suffix;

  @override
  State<RelativeTimeText> createState() => _RelativeTimeTextState();
}

class _RelativeTimeTextState extends State<RelativeTimeText> {
  bool _tickerModeEnabled = true;

  @override
  void initState() {
    super.initState();
    _RelativeTimeRefreshTicker.instance.attach();
    _RelativeTimeRefreshTicker.instance.tick.addListener(_handleGlobalTick);
  }

  @override
  void didUpdateWidget(RelativeTimeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateTime != widget.dateTime && mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerModeEnabled = TickerMode.of(context);
  }

  void _handleGlobalTick() {
    if (!mounted) return;
    if (!_tickerModeEnabled) return;
    setState(() {});
  }

  @override
  void dispose() {
    _RelativeTimeRefreshTicker.instance.tick.removeListener(_handleGlobalTick);
    _RelativeTimeRefreshTicker.instance.detach();
    super.dispose();
  }

  String _buildDisplayText() {
    final relativeText = TimeUtils.formatRelativeTime(widget.dateTime);

    switch (widget.displayStyle) {
      case TimeDisplayStyle.relative:
        return relativeText;
      case TimeDisplayStyle.prefixed:
        return '${widget.prefix ?? ''}$relativeText';
      case TimeDisplayStyle.suffixed:
        return '$relativeText${widget.suffix ?? ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    _tickerModeEnabled = TickerMode.of(context);

    final displayText = _buildDisplayText();
    final tooltipText = TimeUtils.formatTooltipTime(widget.dateTime);

    if (tooltipText.isEmpty) {
      return Text(displayText, style: widget.style);
    }

    return Tooltip(
      message: tooltipText,
      preferBelow: true,
      child: Text(displayText, style: widget.style),
    );
  }
}

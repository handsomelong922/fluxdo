import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/definitions/preferences_defs.dart';
import '../../utils/topic_regex_filter_controller.dart';

/// 未完成的标题不展示，已验证的旧页仍可浏览；错误提示不受隐藏计数设置影响。
class TopicRegexFilterStatus extends ConsumerWidget {
  const TopicRegexFilterStatus({
    super.key,
    required this.controller,
    required this.child,
  });
  final TopicRegexFilterController controller;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showStatus =
        controller.active &&
        (controller.showPendingIndicator || controller.error != null);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final error = controller.error;
    final text = error == null
        ? (zh
              ? '正在后台匹配正则，新标题验证后显示…'
              : 'Checking regex filters; new titles stay hidden until checked…')
        : error.message == 'timeout'
        ? (zh
              ? '正则匹配超时，请编辑规则。未验证标题保持隐藏。'
              : 'Regex matching timed out. Edit your rules. Unchecked titles remain hidden.')
        : (zh
              ? '正则过滤失败（${error.message}），请编辑规则。未验证标题保持隐藏。'
              : 'Regex filtering failed (${error.message}). Edit your rules. Unchecked titles remain hidden.');
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (showStatus)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      if (error == null)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (error == null) const SizedBox(width: 8),
                      Expanded(child: Text(text)),
                      if (error != null)
                        TextButton(
                          onPressed: controller.retry,
                          child: Text(zh ? '重试' : 'Retry'),
                        ),
                      TextButton(
                        onPressed: () =>
                            showTopicFilterKeywordsDialog(context, ref),
                        child: Text(zh ? '编辑规则' : 'Edit rules'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

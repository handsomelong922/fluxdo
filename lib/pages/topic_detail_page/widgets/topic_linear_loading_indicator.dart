import 'package:flutter/material.dart';
import '../../../utils/responsive.dart';

class TopicLinearLoadingIndicator extends StatelessWidget {
  const TopicLinearLoadingIndicator({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final indicator = Responsive.isMobile(context)
        ? Container(
            height: 2,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.42,
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          )
        : const LinearProgressIndicator(minHeight: 2);
    return Padding(padding: padding, child: indicator);
  }
}

import 'package:flutter/material.dart';

class TopicLinearLoadingIndicator extends StatelessWidget {
  const TopicLinearLoadingIndicator({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: const LinearProgressIndicator(minHeight: 2),
    );
  }
}

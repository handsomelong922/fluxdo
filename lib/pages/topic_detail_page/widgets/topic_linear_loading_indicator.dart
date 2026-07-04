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
    final indicator = Responsive.isMobile(context)
        ? const _AnimatedTopicLoadingBar()
        : const LinearProgressIndicator(minHeight: 2);
    return Padding(padding: padding, child: indicator);
  }
}

class _AnimatedTopicLoadingBar extends StatefulWidget {
  const _AnimatedTopicLoadingBar();

  @override
  State<_AnimatedTopicLoadingBar> createState() =>
      _AnimatedTopicLoadingBarState();
}

class _AnimatedTopicLoadingBarState extends State<_AnimatedTopicLoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: ColoredBox(
          color: colorScheme.surfaceContainerHighest,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = (constraints.maxWidth * 0.34).clamp(56.0, 180.0);
              final travel = constraints.maxWidth + barWidth;
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final dx = travel * _controller.value - barWidth;
                  return Stack(
                    children: [
                      Positioned(
                        left: dx,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: barWidth,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

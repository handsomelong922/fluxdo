import 'package:flutter/material.dart';

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.icon,
    this.child,
    this.onLongPress,
    this.selected = false,
    this.size = 44,
    this.iconSize = 20,
    this.borderRadius = 15,
  }) : assert(
         icon != null || child != null,
         'Either icon or child must be provided.',
       );

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final bool selected;
  final double size;
  final double iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: enabled,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: onPressed,
            onLongPress: onLongPress,
            child: GlassIconButtonSurface(
              icon: icon,
              tooltip: tooltip,
              selected: selected,
              enabled: enabled,
              size: size,
              iconSize: iconSize,
              borderRadius: borderRadius,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class GlassIconButtonSurface extends StatelessWidget {
  const GlassIconButtonSurface({
    super.key,
    required this.tooltip,
    this.icon,
    this.child,
    this.selected = false,
    this.enabled = true,
    this.size = 44,
    this.iconSize = 20,
    this.borderRadius = 15,
  }) : assert(
         icon != null || child != null,
         'Either icon or child must be provided.',
       );

  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final bool selected;
  final bool enabled;
  final double size;
  final double iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = !enabled
        ? colorScheme.outline
        : selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primaryContainer.withValues(alpha: 0.78),
                    colorScheme.primary.withValues(alpha: 0.18),
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    colorScheme.surface.withValues(alpha: 0.18),
                  ],
                ),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.24)
                : colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
        child: Center(
          child: IconTheme(
            data: IconThemeData(size: iconSize, color: foreground),
            child: icon == null
                ? child!
                : Icon(icon, size: iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}

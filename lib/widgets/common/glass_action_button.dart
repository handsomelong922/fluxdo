import 'dart:ui';

import 'package:flutter/material.dart';

class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 56,
    this.iconSize = 24,
    this.isExpanded = false,
    this.heroTag,
    this.accentColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final double iconSize;
  final bool isExpanded;
  final Object? heroTag;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final child = Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: onPressed != null,
        child: _GlassActionButtonSurface(
          icon: icon,
          onPressed: onPressed,
          tooltip: tooltip,
          size: size,
          iconSize: iconSize,
          isExpanded: isExpanded,
          accentColor: accentColor,
        ),
      ),
    );

    if (heroTag == null) return child;
    return Hero(tag: heroTag!, child: child);
  }
}

class _GlassActionButtonSurface extends StatelessWidget {
  const _GlassActionButtonSurface({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.size,
    required this.iconSize,
    required this.isExpanded,
    required this.accentColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final double iconSize;
  final bool isExpanded;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onPressed != null;
    final accent = accentColor ?? colorScheme.primary;
    final foreground = enabled ? colorScheme.onPrimary : colorScheme.outline;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: enabled ? 0.26 : 0.08),
                blurRadius: enabled ? 24 : 12,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.30 : 0.12,
                ),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: enabled ? 0.92 : 0.38),
                      Color.lerp(
                        accent,
                        colorScheme.secondary,
                        0.36,
                      )!.withValues(alpha: enabled ? 0.78 : 0.28),
                    ],
                  ),
                  border: Border.all(
                    color: colorScheme.onPrimary.withValues(alpha: 0.30),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 7,
                      left: 11,
                      right: 11,
                      height: size * 0.28,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(size),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.34),
                                Colors.white.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: AnimatedRotation(
                        turns: isExpanded ? 0.125 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: Icon(icon, size: iconSize, color: foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

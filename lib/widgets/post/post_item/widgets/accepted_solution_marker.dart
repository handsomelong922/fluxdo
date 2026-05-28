import 'package:flutter/material.dart';

import '../../../../l10n/s.dart';

class AcceptedSolutionMarker extends StatelessWidget {
  const AcceptedSolutionMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.tertiary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            size: 18,
            color: colors.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.post_solutionAccepted,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onTertiaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

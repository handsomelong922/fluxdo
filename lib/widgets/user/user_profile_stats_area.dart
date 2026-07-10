import 'package:flutter/material.dart';

@immutable
class UserProfileStatData {
  final String value;
  final String label;
  final int? rawValue;
  final VoidCallback? onTap;

  const UserProfileStatData({
    required this.value,
    required this.label,
    this.rawValue,
    this.onTap,
  });
}

/// 用户主页展开头部的固定统计区。
///
/// summary 晚到时仍保持两行固定高度，避免底部锚定的个人信息整体位移。
class UserProfileStatsArea extends StatelessWidget {
  static const double height = 50;
  static const double _rowHeight = 21;
  static const double _rowGap = 8;

  final List<UserProfileStatData> primaryStats;
  final List<UserProfileStatData>? secondaryStats;
  final bool isSummaryLoading;

  const UserProfileStatsArea({
    super.key,
    required this.primaryStats,
    required this.secondaryStats,
    this.isSummaryLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedSecondaryStats = secondaryStats;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileStatsRow(stats: primaryStats),
          const SizedBox(height: UserProfileStatsArea._rowGap),
          if (resolvedSecondaryStats != null)
            _ProfileStatsRow(stats: resolvedSecondaryStats)
          else if (isSummaryLoading)
            const _ProfileStatsLoadingRow(key: Key('profile-stats-loading'))
          else
            const SizedBox(height: UserProfileStatsArea._rowHeight),
        ],
      ),
    );
  }
}

class _ProfileStatsRow extends StatelessWidget {
  final List<UserProfileStatData> stats;

  const _ProfileStatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: UserProfileStatsArea._rowHeight,
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int index = 0; index < stats.length; index++) ...[
                if (index > 0) const SizedBox(width: 16),
                _ProfileStatSlot(data: stats[index]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileStatSlot extends StatelessWidget {
  final UserProfileStatData data;

  const _ProfileStatSlot({required this.data});

  @override
  Widget build(BuildContext context) {
    Widget child = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          data.value,
          softWrap: false,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          data.label,
          softWrap: false,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );

    if (data.onTap != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: data.onTap,
        child: child,
      );
    }
    if (data.rawValue != null) {
      child = Tooltip(message: '${data.rawValue}', child: child);
    }
    return child;
  }
}

class _ProfileStatsLoadingRow extends StatelessWidget {
  const _ProfileStatsLoadingRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: UserProfileStatsArea._rowHeight,
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: List.generate(4, (index) {
              return Padding(
                padding: EdgeInsets.only(right: index == 3 ? 0 : 16),
                child: Container(
                  width: index == 0 ? 48 : 42,
                  height: 17,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

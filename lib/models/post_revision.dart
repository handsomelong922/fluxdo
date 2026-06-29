import '../utils/time_utils.dart';

class PostRevisionChange<T> {
  final T? previous;
  final T? current;

  const PostRevisionChange({this.previous, this.current});

  static PostRevisionChange<T>? parse<T>(
    dynamic json,
    T? Function(dynamic value) parse,
  ) {
    if (json == null) return null;
    if (json is List) {
      final previous = json.isNotEmpty ? parse(json[0]) : null;
      final current = json.length > 1 ? parse(json[1]) : null;
      if (previous == null && current == null) return null;
      return PostRevisionChange<T>(previous: previous, current: current);
    }
    if (json is Map<String, dynamic>) {
      final previous = parse(json['previous']);
      final current = parse(json['current']);
      if (previous == null && current == null) return null;
      return PostRevisionChange<T>(previous: previous, current: current);
    }
    return null;
  }
}

class PostRevisionBodyChanges {
  final String? inline;
  final String? sideBySide;
  final String? sideBySideMarkdown;

  const PostRevisionBodyChanges({
    this.inline,
    this.sideBySide,
    this.sideBySideMarkdown,
  });

  bool get isEmpty =>
      (inline == null || inline!.isEmpty) &&
      (sideBySide == null || sideBySide!.isEmpty) &&
      (sideBySideMarkdown == null || sideBySideMarkdown!.isEmpty);

  static PostRevisionBodyChanges? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return PostRevisionBodyChanges(
      inline: json['inline'] as String?,
      sideBySide: json['side_by_side'] as String?,
      sideBySideMarkdown: json['side_by_side_markdown'] as String?,
    );
  }
}

class PostRevision {
  final int previousRevision;
  final int currentRevision;
  final int? nextRevision;
  final int lastRevision;
  final int versionCount;
  final String username;
  final String? displayUsername;
  final DateTime createdAt;
  final String? editReason;
  final bool previousHidden;
  final bool currentHidden;
  final bool diffError;
  final PostRevisionBodyChanges? bodyChanges;
  final PostRevisionChange<String>? titleChanges;

  const PostRevision({
    required this.previousRevision,
    required this.currentRevision,
    required this.nextRevision,
    required this.lastRevision,
    required this.versionCount,
    required this.username,
    required this.displayUsername,
    required this.createdAt,
    required this.editReason,
    required this.previousHidden,
    required this.currentHidden,
    required this.diffError,
    required this.bodyChanges,
    required this.titleChanges,
  });

  factory PostRevision.fromJson(Map<String, dynamic> json) {
    final currentRevision = json['current_revision'] as int? ?? 1;
    return PostRevision(
      previousRevision: json['previous_revision'] as int? ?? currentRevision,
      currentRevision: currentRevision,
      nextRevision: json['next_revision'] as int?,
      lastRevision: json['last_revision'] as int? ?? currentRevision,
      versionCount: json['version_count'] as int? ?? 1,
      username: json['username'] as String? ?? '',
      displayUsername: json['display_username'] as String?,
      createdAt:
          TimeUtils.parseUtcTime(json['created_at'] as String?) ??
          DateTime.now(),
      editReason: (json['edit_reason'] as String?)?.isNotEmpty == true
          ? json['edit_reason'] as String
          : null,
      previousHidden: json['previous_hidden'] as bool? ?? false,
      currentHidden: json['current_hidden'] as bool? ?? false,
      diffError: json['diff_error'] as bool? ?? false,
      bodyChanges: PostRevisionBodyChanges.fromJson(json['body_changes']),
      titleChanges: PostRevisionChange.parse<String>(
        json['title_changes'],
        (value) => value?.toString(),
      ),
    );
  }
}

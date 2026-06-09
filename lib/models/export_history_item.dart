import '../utils/export_utils.dart';
import '../utils/share_utils.dart';

class ExportHistoryItem {
  const ExportHistoryItem({
    required this.id,
    required this.topicId,
    required this.topicTitle,
    required this.topicSlug,
    required this.format,
    required this.scope,
    required this.postCount,
    required this.byteSize,
    required this.destination,
    required this.createdAtMillis,
    this.filePath,
  });

  final String id;
  final int topicId;
  final String topicTitle;
  final String topicSlug;
  final ExportFormat format;
  final ExportScope scope;
  final int postCount;
  final int byteSize;
  final ShareOutcomeType destination;
  final int createdAtMillis;
  final String? filePath;

  factory ExportHistoryItem.fromResult(ExportResult result) {
    return ExportHistoryItem(
      id: '${result.createdAt.millisecondsSinceEpoch}-${result.topicId}',
      topicId: result.topicId,
      topicTitle: result.topicTitle,
      topicSlug: result.topicSlug,
      format: result.format,
      scope: result.scope,
      postCount: result.postCount,
      byteSize: result.byteSize,
      destination: result.shareOutcome.type,
      createdAtMillis: result.createdAt.millisecondsSinceEpoch,
      filePath: result.shareOutcome.path,
    );
  }

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMillis);

  Map<String, dynamic> toJson() => {
        'id': id,
        'topicId': topicId,
        'topicTitle': topicTitle,
        'topicSlug': topicSlug,
        'format': format.name,
        'scope': scope.name,
        'postCount': postCount,
        'byteSize': byteSize,
        'destination': destination.name,
        'createdAtMillis': createdAtMillis,
        'filePath': filePath,
      };

  factory ExportHistoryItem.fromJson(Map<String, dynamic> json) {
    return ExportHistoryItem(
      id: json['id']?.toString() ?? '',
      topicId: json['topicId'] as int? ?? 0,
      topicTitle: json['topicTitle']?.toString() ?? '',
      topicSlug: json['topicSlug']?.toString() ?? '',
      format: ExportFormat.values.firstWhere(
        (value) => value.name == json['format'],
        orElse: () => ExportFormat.markdown,
      ),
      scope: ExportScope.values.firstWhere(
        (value) => value.name == json['scope'],
        orElse: () => ExportScope.firstPostOnly,
      ),
      postCount: json['postCount'] as int? ?? 0,
      byteSize: json['byteSize'] as int? ?? 0,
      destination: ShareOutcomeType.values.firstWhere(
        (value) => value.name == json['destination'],
        orElse: () => ShareOutcomeType.shared,
      ),
      createdAtMillis: json['createdAtMillis'] as int? ?? 0,
      filePath: json['filePath']?.toString(),
    );
  }
}

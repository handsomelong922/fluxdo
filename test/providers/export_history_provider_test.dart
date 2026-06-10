import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluxdo/models/export_history_item.dart';
import 'package:fluxdo/providers/export_history_provider.dart';
import 'package:fluxdo/utils/export_utils.dart';
import 'package:fluxdo/utils/share_utils.dart';

ExportHistoryItem _item(String id, {String title = 'Sample'}) {
  return ExportHistoryItem(
    id: id,
    topicId: 1,
    topicTitle: title,
    topicSlug: 'sample',
    format: ExportFormat.markdown,
    scope: ExportScope.firstPostOnly,
    postCount: 1,
    byteSize: 128,
    destination: ShareOutcomeType.shared,
    createdAtMillis: 1700000000000,
  );
}

Future<ExportHistoryNotifier> _notifier() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ExportHistoryNotifier(prefs, 'export_history_test');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('add 将新记录放在最前面', () async {
    final notifier = await _notifier();

    notifier.add(_item('a'));
    notifier.add(_item('b'));

    expect(notifier.state.map((item) => item.id), ['b', 'a']);
  });

  test('同 id 记录会覆盖旧记录', () async {
    final notifier = await _notifier();

    notifier.add(_item('a', title: 'old'));
    notifier.add(_item('a', title: 'new'));

    expect(notifier.state, hasLength(1));
    expect(notifier.state.single.topicTitle, 'new');
  });

  test('remove 和 clearAll 会持久化状态', () async {
    final notifier = await _notifier();

    notifier.add(_item('a'));
    notifier.add(_item('b'));
    notifier.remove('a');
    expect(notifier.state.map((item) => item.id), ['b']);

    notifier.clearAll();
    expect(notifier.state, isEmpty);
  });
}

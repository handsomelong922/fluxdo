import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/topic_list/filter_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NewSubsetNotifier', () {
    test('maps subset values to Discourse API query values', () {
      expect(NewSubset.all.apiValue, isNull);
      expect(NewSubset.topics.apiValue, 'topics');
      expect(NewSubset.replies.apiValue, 'replies');
    });

    test('uses all by default and persists selected subset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NewSubsetNotifier(prefs);

      expect(notifier.state, NewSubset.all);

      notifier.setSubset(NewSubset.replies);

      expect(notifier.state, NewSubset.replies);
      expect(prefs.getString('topic_new_subset'), 'replies');
      expect(NewSubsetNotifier(prefs).state, NewSubset.replies);
    });
  });
}

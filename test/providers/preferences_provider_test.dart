import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/avatar_url_policy.dart';
import 'package:fluxdo/navigation/page_transition_preferences.dart';
import 'package:fluxdo/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    AvatarUrlPolicy.setPreferStaticAvatars(false);
  });

  group('PreferencesNotifier settings', () {
    test('AvatarUrlPolicy does not return animated gif in static mode', () {
      AvatarUrlPolicy.setPreferStaticAvatars(true);

      final url = AvatarUrlPolicy.resolve(
        avatarTemplate: '',
        animatedAvatar: '/user_avatar/linux.do/test/120/1_2.gif',
        size: 120,
      );

      expect(url, isNot(contains('.gif')));
      expect(url, contains('1_2.png'));
    });

    test('AvatarUrlPolicy staticizes direct avatar gif urls', () {
      AvatarUrlPolicy.setPreferStaticAvatars(true);

      final url = AvatarUrlPolicy.resolveDirectAvatarUrl(
        'https://linux.do/user_avatar/linux.do/test/120/1_2.gif?foo=bar',
      );

      expect(url, contains('1_2.png?foo=bar'));
    });

    test('AvatarUrlPolicy staticizes additional animated avatar formats', () {
      AvatarUrlPolicy.setPreferStaticAvatars(true);

      final webpUrl = AvatarUrlPolicy.resolveDirectAvatarUrl(
        'https://linux.do/user_avatar/linux.do/test/120/1_2.webp?foo=bar',
      );
      final avifUrl = AvatarUrlPolicy.resolveDirectAvatarUrl(
        'https://linux.do/user_avatar/linux.do/test/120/1_2.avif',
      );

      expect(webpUrl, contains('1_2.png?foo=bar'));
      expect(avifUrl, contains('1_2.png'));
    });

    test('AvatarUrlPolicy does not rewrite non-avatar webp images', () {
      AvatarUrlPolicy.setPreferStaticAvatars(true);

      final url = AvatarUrlPolicy.resolveDirectAvatarUrl(
        'https://linux.do/uploads/default/original/3X/image.webp',
      );

      expect(url, contains('image.webp'));
    });

    test('uses safe defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      expect(notifier.state.autoSummarizeTopicOnEnter, isFalse);
      expect(notifier.state.autoSummarizeMinReplies, 20);
      expect(notifier.state.defaultNestedTopicView, isTrue);
      expect(notifier.state.showSignatures, isTrue);
      expect(notifier.state.preferStaticAvatars, isFalse);
      expect(notifier.state.hideTopicListAvatars, isFalse);
      expect(notifier.state.reduceLoadingAnimations, isTrue);
      expect(notifier.state.pageTransition, AppPageTransition.platform);
      expect(notifier.state.clipboardTopicLinkDetection, isFalse);
      expect(AvatarUrlPolicy.preferStaticAvatars, isFalse);
    });

    test('persists switch and clamps minimum replies', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      await notifier.setAutoSummarizeTopicOnEnter(true);
      await notifier.setAutoSummarizeMinReplies(500);

      expect(notifier.state.autoSummarizeTopicOnEnter, isTrue);
      expect(notifier.state.autoSummarizeMinReplies, 200);
      expect(prefs.getBool('pref_auto_summarize_topic_on_enter'), isTrue);
      expect(prefs.getInt('pref_auto_summarize_min_replies'), 200);
    });

    test('persists default nested topic view preference', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      await notifier.setDefaultNestedTopicView(false);

      expect(notifier.state.defaultNestedTopicView, isFalse);
      expect(prefs.getBool('pref_default_nested_topic_view'), isFalse);

      await notifier.setDefaultNestedTopicView(true);

      expect(notifier.state.defaultNestedTopicView, isTrue);
      expect(prefs.getBool('pref_default_nested_topic_view'), isTrue);
    });

    test('persists clipboard topic link detection preference', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      await notifier.setClipboardTopicLinkDetection(true);

      expect(notifier.state.clipboardTopicLinkDetection, isTrue);
      expect(prefs.getBool('pref_clipboard_topic_link_detection'), isTrue);

      await notifier.setClipboardTopicLinkDetection(false);

      expect(notifier.state.clipboardTopicLinkDetection, isFalse);
      expect(prefs.getBool('pref_clipboard_topic_link_detection'), isFalse);
    });

    test('persists user signature display preference', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      await notifier.setShowSignatures(false);

      expect(notifier.state.showSignatures, isFalse);
      expect(prefs.getBool('pref_show_signatures'), isFalse);

      await notifier.setShowSignatures(true);

      expect(notifier.state.showSignatures, isTrue);
      expect(prefs.getBool('pref_show_signatures'), isTrue);
    });

    test('persists reduced loading animations preference', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      await notifier.setReduceLoadingAnimations(true);

      expect(notifier.state.reduceLoadingAnimations, isTrue);
      expect(prefs.getBool('pref_reduce_loading_animations'), isTrue);

      await notifier.setReduceLoadingAnimations(false);

      expect(notifier.state.reduceLoadingAnimations, isFalse);
      expect(prefs.getBool('pref_reduce_loading_animations'), isFalse);
    });

    test('persists page transition preference', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      await notifier.setPageTransition(AppPageTransition.fade);

      expect(notifier.state.pageTransition, AppPageTransition.fade);
      expect(prefs.getString('pref_page_transition'), 'fade');

      final reloaded = PreferencesNotifier(prefs);

      expect(reloaded.state.pageTransition, AppPageTransition.fade);
    });

    test('persists avatar performance preferences and syncs policy', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = PreferencesNotifier(prefs);

      await notifier.setPreferStaticAvatars(true);
      await notifier.setHideTopicListAvatars(true);

      expect(notifier.state.preferStaticAvatars, isTrue);
      expect(notifier.state.hideTopicListAvatars, isTrue);
      expect(AvatarUrlPolicy.preferStaticAvatars, isTrue);
      expect(prefs.getBool('pref_prefer_static_avatars'), isTrue);
      expect(prefs.getBool('pref_hide_topic_list_avatars'), isTrue);

      await notifier.setPreferStaticAvatars(false);

      expect(notifier.state.preferStaticAvatars, isFalse);
      expect(AvatarUrlPolicy.preferStaticAvatars, isFalse);
      expect(prefs.getBool('pref_prefer_static_avatars'), isFalse);
    });
  });
}

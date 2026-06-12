import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/data_management/data_backup_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'FluxDO',
      packageName: 'com.example.fluxdo',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
      installerStore: null,
    );
  });

  test('exports user settings and excludes generated cache data', () async {
    SharedPreferences.setMockInitialValues({
      'pref_home_detailed_topic_list': true,
      'custom_keyword_filter_patterns': <String>['flutter'],
      'custom_ai_prompt_search_assistant': 'search prompt',
      'notion_config_default': jsonEncode({'token': 'notion-token'}),
      'rhttp_enabled': true,
      'webview_adapter_enabled': true,
      'hcaptcha_accessibility_cookie': 'hc-cookie',
      'ai_providers': jsonEncode([
        {'id': 'provider-1', 'name': 'Custom AI'},
      ]),
      'ai_default_model': 'provider-1:gpt-4.1',
      'ai_apikey_provider-1': 'sk-temp',
      'topic_new_subset': 'replies',
      'auto_check_update': false,
      'developer_mode': true,
      'sticker_market_base_url': 'https://stickers.example.com',
      'sticker_subscribed_groups': <String>['daily'],
      'web_bookmarks': '[]',
      'search_ai_chat_messages_session-1': '[]',
      'ai_chat_session_messages_session-1': '[]',
      'home_topic_excerpt_cache_v1': '{}',
      'update_cache': '{}',
      'sticker_market_page_1': '{}',
      'topic_reading_state_42': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    final backup = await DataBackupService.exportData(prefs);
    final data = backup['data'] as Map<String, dynamic>;

    expect(
      data.keys,
      containsAll([
        'pref_home_detailed_topic_list',
        'custom_keyword_filter_patterns',
        'custom_ai_prompt_search_assistant',
        'notion_config_default',
        'rhttp_enabled',
        'webview_adapter_enabled',
        'hcaptcha_accessibility_cookie',
        'ai_providers',
        'ai_default_model',
        'topic_new_subset',
        'auto_check_update',
        'developer_mode',
        'sticker_market_base_url',
        'sticker_subscribed_groups',
        'web_bookmarks',
      ]),
    );
    expect(data.keys, isNot(contains('ai_apikey_provider-1')));
    expect(data.keys, isNot(contains('search_ai_chat_messages_session-1')));
    expect(data.keys, isNot(contains('ai_chat_session_messages_session-1')));
    expect(data.keys, isNot(contains('home_topic_excerpt_cache_v1')));
    expect(data.keys, isNot(contains('update_cache')));
    expect(data.keys, isNot(contains('sticker_market_page_1')));
    expect(data.keys, isNot(contains('topic_reading_state_42')));

    expect(backup['apiKeys'], {'provider-1': 'sk-temp'});
  });

  test('imports exported settings', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await DataBackupService.importData(prefs, {
      'version': 1,
      'data': {
        'custom_ai_prompt_search_assistant': {
          'type': 'String',
          'value': 'restored prompt',
        },
        'sticker_subscribed_groups': {
          'type': 'StringList',
          'value': ['daily'],
        },
      },
    });

    expect(
      prefs.getString('custom_ai_prompt_search_assistant'),
      'restored prompt',
    );
    expect(prefs.getStringList('sticker_subscribed_groups'), ['daily']);
  });
}

// CUSTOM: AI Prompt Settings
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/theme_provider.dart';

String defaultSummaryAllRepliesPrompt() => '请总结这个话题中全部回帖的主要观点、分歧和结论，输出精炼的中文摘要。';

String defaultGenerateReplyPrompt() =>
    '请基于当前话题内容生成一条适合直接发布的中文回复，语气自然、观点明确，并尽量给出有价值的信息。';

class AiPromptSettingsState {
  final String summaryTopicPrompt;
  final String summaryAllRepliesPrompt;
  final String generateReplyPrompt;
  final String generateTitlePrompt;

  const AiPromptSettingsState({
    this.summaryTopicPrompt = '',
    this.summaryAllRepliesPrompt = '',
    this.generateReplyPrompt = '',
    this.generateTitlePrompt = '',
  });

  AiPromptSettingsState copyWith({
    String? summaryTopicPrompt,
    String? summaryAllRepliesPrompt,
    String? generateReplyPrompt,
    String? generateTitlePrompt,
  }) {
    return AiPromptSettingsState(
      summaryTopicPrompt: summaryTopicPrompt ?? this.summaryTopicPrompt,
      summaryAllRepliesPrompt:
          summaryAllRepliesPrompt ?? this.summaryAllRepliesPrompt,
      generateReplyPrompt: generateReplyPrompt ?? this.generateReplyPrompt,
      generateTitlePrompt: generateTitlePrompt ?? this.generateTitlePrompt,
    );
  }
}

class AiPromptSettingsNotifier extends StateNotifier<AiPromptSettingsState> {
  // CUSTOM: AI Prompt Settings
  static const String summaryTopicKey = 'custom_ai_prompt_summary_topic';
  static const String summaryAllRepliesKey =
      'custom_ai_prompt_summary_all_replies';
  static const String generateReplyKey = 'custom_ai_prompt_generate_reply';
  static const String generateTitleKey = 'custom_ai_prompt_generate_title';

  final SharedPreferences _prefs;

  AiPromptSettingsNotifier(this._prefs) : super(_load(_prefs));

  static AiPromptSettingsState _load(SharedPreferences prefs) {
    return AiPromptSettingsState(
      summaryTopicPrompt: prefs.getString(summaryTopicKey) ?? '',
      summaryAllRepliesPrompt: prefs.getString(summaryAllRepliesKey) ?? '',
      generateReplyPrompt: prefs.getString(generateReplyKey) ?? '',
      generateTitlePrompt: prefs.getString(generateTitleKey) ?? '',
    );
  }

  void setSummaryTopicPrompt(String value) {
    final normalized = value.trim();
    _setString(
      key: summaryTopicKey,
      value: normalized,
      update: () => state = state.copyWith(summaryTopicPrompt: normalized),
    );
  }

  void setSummaryAllRepliesPrompt(String value) {
    final normalized = value.trim();
    _setString(
      key: summaryAllRepliesKey,
      value: normalized,
      update: () => state = state.copyWith(summaryAllRepliesPrompt: normalized),
    );
  }

  void setGenerateReplyPrompt(String value) {
    final normalized = value.trim();
    _setString(
      key: generateReplyKey,
      value: normalized,
      update: () => state = state.copyWith(generateReplyPrompt: normalized),
    );
  }

  void setGenerateTitlePrompt(String value) {
    final normalized = value.trim();
    _setString(
      key: generateTitleKey,
      value: normalized,
      update: () => state = state.copyWith(generateTitlePrompt: normalized),
    );
  }

  void _setString({
    required String key,
    required String value,
    required void Function() update,
  }) {
    update();
    if (value.isEmpty) {
      _prefs.remove(key);
    } else {
      _prefs.setString(key, value);
    }
  }
}

final aiPromptSettingsProvider =
    StateNotifierProvider<AiPromptSettingsNotifier, AiPromptSettingsState>((
      ref,
    ) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return AiPromptSettingsNotifier(prefs);
    });

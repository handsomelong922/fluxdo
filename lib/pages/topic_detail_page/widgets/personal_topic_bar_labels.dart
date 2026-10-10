import 'package:flutter/material.dart';

import '../../../l10n/s.dart';
import '../../../providers/personal_topic_bar_preferences_provider.dart';

/// 个人功能文案集中管理，减少对生成本地化文件的改动。
class PersonalTopicBarLabels {
  PersonalTopicBarLabels(BuildContext context)
    : _locale = Localizations.localeOf(context);

  final Locale _locale;
  bool get _chinese => _locale.languageCode == 'zh';
  bool get _traditional =>
      _locale.scriptCode == 'Hant' ||
      _locale.countryCode == 'TW' ||
      _locale.countryCode == 'HK';

  String get title => !_chinese
      ? 'Topic toolbar order'
      : _traditional
      ? '話題底欄按鈕排序'
      : '话题底栏按钮排序';
  String get description => !_chinese
      ? 'Drag the handles to reorder the four buttons.'
      : _traditional
      ? '拖動右側手柄，調整四個按鈕的順序。'
      : '拖动右侧手柄，调整四个按钮的顺序。';
  String get bookmarked => !_chinese ? 'Bookmarked' : '已收藏';
}

String topicBarActionLabel(BuildContext context, TopicBarAction action) =>
    switch (action) {
      TopicBarAction.scrollToTop => context.l10n.topicDetail_scrollToTop,
      TopicBarAction.filter => context.l10n.topicDetail_filter,
      TopicBarAction.share => context.l10n.common_share,
      TopicBarAction.bookmark => context.l10n.common_addBookmark,
    };

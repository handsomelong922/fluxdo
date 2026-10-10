import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../utils/topic_keyword_filter.dart';

/// 展示固定快照，不重复过滤、不请求更多话题或头像。
/// 选择话题后交回源页面，复用其现有导航逻辑。
class FilteredTopicsPage extends StatelessWidget {
  FilteredTopicsPage({super.key, required List<FilteredTopic> topics})
    : topics = List.unmodifiable(topics);

  final List<FilteredTopic> topics;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          zh ? '已忽略的话题（${topics.length}）' : 'Ignored topics (${topics.length})',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              zh ? '仅显示打开此页时已加载、确认被过滤的话题。待验证的标题不计入；点击话题可主动查看。' : 'Snapshot of loaded topics confirmed hidden when this page opened. Unchecked titles are excluded. Tap a topic to open it.',
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: topics.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = topics[index];
                final topic = entry.topic;
                final author = topic.posters.isEmpty
                    ? null
                    : topic.posters.first.user;
                final authorText = author == null || author.username.isEmpty
                    ? (zh ? '作者未知' : 'Unknown author')
                    : '@${author.username}';
                final reason = switch (entry.reason) {
                  TopicFilterReason.blockedUser => zh ? '屏蔽用户' : 'Blocked user',
                  TopicFilterReason.keyword =>
                    zh ? '关键词：${entry.keyword}' : 'Keyword: ${entry.keyword}',
                  TopicFilterReason.regex => zh ? '正则规则命中' : 'Regex match',
                };
                return ListTile(
                  key: ValueKey('filtered-topic-${topic.id}'),
                  title: Text(topic.title),
                  subtitle: Text('$authorText · $reason'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop<Topic>(topic),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

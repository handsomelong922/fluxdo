import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/s.dart';
import '../../../providers/personal_topic_bar_preferences_provider.dart';
import '../../../settings/settings_model.dart';
import 'personal_topic_bar_labels.dart';

CustomModel buildPersonalTopicBarOrderSetting(BuildContext context) =>
    CustomModel(
      id: 'personalTopicBarOrder',
      title: PersonalTopicBarLabels(context).title,
      builder: (context, ref) {
        final order = ref.watch(personalTopicBarPreferencesProvider);
        return ListTile(
          leading: Icon(
            Symbols.swap_horiz_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(PersonalTopicBarLabels(context).title),
          subtitle: Text(
            order
                .map((action) => topicBarActionLabel(context, action))
                .join(' · '),
          ),
          trailing: const Icon(Symbols.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PersonalTopicBarSettingsPage(),
            ),
          ),
        );
      },
    );

class PersonalTopicBarSettingsPage extends ConsumerWidget {
  const PersonalTopicBarSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(personalTopicBarPreferencesProvider);
    final labels = PersonalTopicBarLabels(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(labels.title),
        actions: [
          TextButton(
            key: const ValueKey('topic-bar-order-reset'),
            onPressed: () =>
                ref.read(personalTopicBarPreferencesProvider.notifier).reset(),
            child: Text(context.l10n.progressGesture_resetDefault),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        header: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(labels.description),
        ),
        buildDefaultDragHandles: false,
        itemCount: order.length,
        onReorder: (oldIndex, newIndex) {
          final updated = [...order];
          if (newIndex > oldIndex) newIndex--;
          updated.insert(newIndex, updated.removeAt(oldIndex));
          ref
              .read(personalTopicBarPreferencesProvider.notifier)
              .setOrder(updated);
        },
        itemBuilder: (context, index) {
          final action = order[index];
          return ListTile(
            key: ValueKey('topic-bar-order-${action.name}'),
            leading: Icon(switch (action) {
              TopicBarAction.scrollToTop => Symbols.vertical_align_top_rounded,
              TopicBarAction.filter => Symbols.filter_list_rounded,
              TopicBarAction.share => Symbols.share_rounded,
              TopicBarAction.bookmark => Symbols.bookmark_rounded,
            }),
            title: Text(topicBarActionLabel(context, action)),
            trailing: ReorderableDragStartListener(
              key: ValueKey('topic-bar-drag-${action.name}'),
              index: index,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Symbols.drag_handle_rounded),
              ),
            ),
          );
        },
      ),
    );
  }
}

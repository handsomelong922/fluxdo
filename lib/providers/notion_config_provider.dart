// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notion/notion_config.dart';
import 'core_providers.dart';
import 'theme_provider.dart';

final notionConfigRepositoryProvider = Provider<NotionConfigRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return NotionConfigRepository(prefs);
});

final notionConfigProvider =
    StateNotifierProvider<NotionConfigNotifier, NotionConfig>((ref) {
      final repository = ref.watch(notionConfigRepositoryProvider);
      final notifier = NotionConfigNotifier(
        repository: repository,
        accountIdResolver: () async {
          final cached = ref.read(currentUserProvider).value?.username;
          if (cached != null && cached.isNotEmpty) return cached;
          return (await ref.read(currentUserProvider.future))?.username;
        },
      );
      ref.listen(currentUserProvider, (_, next) {
        final username = next.value?.username;
        if (username != null && username.isNotEmpty) {
          notifier.onAccountIdResolved(username);
        }
      }, fireImmediately: true);
      return notifier;
    });

class NotionConfigNotifier extends StateNotifier<NotionConfig> {
  NotionConfigNotifier({
    required NotionConfigRepository repository,
    required Future<String?> Function() accountIdResolver,
  }) : _repository = repository,
       _resolveAccountId = accountIdResolver,
       super(const NotionConfig());

  final NotionConfigRepository _repository;
  final Future<String?> Function() _resolveAccountId;
  String? _accountId;

  void onAccountIdResolved(String accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    if (mounted) state = _repository.read(accountId);
  }

  Future<void> ensureLoaded() async {
    await _ensureAccountId();
  }

  Future<void> update(NotionConfig config) async {
    final accountId = await _ensureAccountId();
    if (accountId == null) return;
    await _repository.write(accountId, config);
    if (mounted) state = config;
  }

  Future<void> clear() async {
    final accountId = await _ensureAccountId();
    if (accountId == null) return;
    await _repository.clear(accountId);
    if (mounted) state = const NotionConfig();
  }

  Future<String?> _ensureAccountId() async {
    if (_accountId != null && _accountId!.isNotEmpty) return _accountId;
    final accountId = await _resolveAccountId();
    if (accountId != null && accountId.isNotEmpty) {
      onAccountIdResolved(accountId);
    }
    return _accountId;
  }
}

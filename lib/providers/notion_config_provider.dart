import 'dart:async';

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
       super(repository.readFallback());

  final NotionConfigRepository _repository;
  final Future<String?> Function() _resolveAccountId;
  String? _accountId;

  void onAccountIdResolved(String accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    final accountConfig = _repository.read(accountId);
    if (accountConfig.hasStoredValues) {
      if (mounted) state = accountConfig;
      return;
    }
    final fallbackConfig = state.hasStoredValues
        ? state
        : _repository.readFallback();
    if (fallbackConfig.hasStoredValues) {
      if (mounted) state = fallbackConfig;
      unawaited(_repository.write(accountId, fallbackConfig));
      return;
    }
    if (mounted) state = const NotionConfig();
  }

  Future<void> ensureLoaded() async {
    final accountId = await _ensureAccountId();
    if (accountId == null && mounted) {
      state = _repository.readFallback();
    }
  }

  Future<void> update(NotionConfig config) async {
    final accountId = await _ensureWritableAccountId();
    await _repository.write(accountId, config);
    if (mounted) state = config;
  }

  Future<void> clear() async {
    final accountId = await _ensureWritableAccountId();
    if (accountId == NotionConfigRepository.fallbackAccountId) {
      await _repository.clearFallbackSources();
    } else {
      await _repository.clear(accountId);
      await _repository.clear(NotionConfigRepository.fallbackAccountId);
    }
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

  Future<String> _ensureWritableAccountId() async {
    final accountId = await _ensureAccountId();
    if (accountId != null && accountId.isNotEmpty) return accountId;
    return NotionConfigRepository.fallbackAccountId;
  }
}

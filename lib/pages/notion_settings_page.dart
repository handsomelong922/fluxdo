import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/s.dart';
import '../providers/notion_config_provider.dart';
import '../services/notion/notion_client.dart';
import '../services/notion/notion_config.dart';
import '../services/notion/notion_sync_service.dart';
import '../services/toast_service.dart';

class NotionSettingsPage extends ConsumerStatefulWidget {
  const NotionSettingsPage({super.key});

  @override
  ConsumerState<NotionSettingsPage> createState() => _NotionSettingsPageState();
}

class _NotionSettingsPageState extends ConsumerState<NotionSettingsPage> {
  final _tokenController = TextEditingController();
  final _databaseIdController = TextEditingController();
  bool _obscureToken = true;
  bool _busy = false;
  bool _editing = false;
  bool _initialized = false;
  bool? _needsUpgrade;
  bool _upgrading = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _databaseIdController.dispose();
    super.dispose();
  }

  void _syncControllers(NotionConfig config) {
    if (_tokenController.text.isEmpty &&
        (config.integrationToken ?? '').isNotEmpty) {
      _tokenController.text = config.integrationToken!;
    }
    if (_databaseIdController.text.isEmpty &&
        (config.databaseId ?? '').isNotEmpty) {
      _databaseIdController.text = config.databaseId!;
    }
    if (!_initialized && config.isComplete) {
      _initialized = true;
      _checkUpgrade(config);
    }
  }

  Future<void> _checkUpgrade(NotionConfig config) async {
    try {
      final service = NotionSyncService(config: config);
      final upToDate = await service.isDatabaseUpToDate();
      if (mounted) setState(() => _needsUpgrade = !upToDate);
    } catch (_) {
      if (mounted) setState(() => _needsUpgrade = false);
    }
  }

  Future<void> _upgradeDatabase(NotionConfig config) async {
    setState(() => _upgrading = true);
    try {
      await NotionSyncService(config: config).upgradeDatabase();
      if (mounted) {
        setState(() => _needsUpgrade = false);
        ToastService.showSuccess(S.current.notion_upgradeSucceed);
      }
    } on NotionApiException catch (error) {
      ToastService.showError(S.current.notion_upgradeFailed(error.message));
    } catch (error) {
      ToastService.showError(S.current.notion_upgradeFailed(error.toString()));
    } finally {
      if (mounted) setState(() => _upgrading = false);
    }
  }

  Future<void> _saveAndTest() async {
    final token = _tokenController.text.trim();
    final databaseId = _databaseIdController.text.trim();
    if (token.isEmpty || databaseId.isEmpty) {
      ToastService.showError(S.current.notion_fillTokenAndDb);
      return;
    }

    setState(() => _busy = true);
    try {
      final config = NotionConfig(
        integrationToken: token,
        databaseId: databaseId,
        autoSyncOnBookmark: ref.read(notionConfigProvider).autoSyncOnBookmark,
        syncScope: ref.read(notionConfigProvider).syncScope,
      );
      final title = await NotionSyncService(config: config).testConnection();
      await ref.read(notionConfigProvider.notifier).update(config);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _initialized = false;
      });
      ToastService.showSuccess(S.current.notion_testOk(title));
    } on NotionApiException catch (error) {
      ToastService.showError(S.current.notion_testFailed(error.message));
    } catch (error) {
      ToastService.showError(S.current.notion_testFailed(error.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await ref.read(notionConfigProvider.notifier).clear();
    if (!mounted) return;
    _tokenController.clear();
    _databaseIdController.clear();
    setState(() {
      _editing = true;
      _initialized = false;
      _needsUpgrade = null;
    });
    ToastService.show(S.current.notion_disconnected);
  }

  Future<void> _openIntegrationsPage() async {
    await launchUrl(
      Uri.parse('https://www.notion.so/my-integrations'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _createTemplateDatabase() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ToastService.showError(S.current.notion_tokenRequired);
      return;
    }
    final parentPageId = await _askParentPageId();
    if (parentPageId == null || parentPageId.isEmpty) return;

    setState(() => _busy = true);
    try {
      final client = NotionClient(token);
      final created = await client.createDatabaseForExport(
        parentPageId: parentPageId,
        title: 'FluxDO Export',
      );
      final databaseId = created['id']?.toString();
      if (databaseId == null || databaseId.isEmpty) {
        throw NotionApiException('No database id in response');
      }
      _databaseIdController.text = databaseId;
      ToastService.showSuccess(S.current.notion_databaseCreated);
    } on NotionApiException catch (error) {
      ToastService.showError(S.current.notion_dbCreateFailed(error.message));
    } catch (error) {
      ToastService.showError(S.current.notion_dbCreateFailed(error.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askParentPageId() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.current.notion_pickParentPage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.current.notion_pickParentPageHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Parent Page ID',
                hintText: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.current.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(S.current.common_confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(notionConfigProvider);
    _syncControllers(config);
    final showSetup = !config.isComplete || _editing;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.current.notion_title),
        actions: [
          if (config.isComplete)
            TextButton.icon(
              icon: const Icon(Icons.link_off_rounded, size: 16),
              onPressed: _busy ? null : _disconnect,
              label: Text(S.current.notion_disconnect),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Header(),
          const SizedBox(height: 16),
          if (config.isComplete && _needsUpgrade == true) ...[
            _UpgradeBanner(
              upgrading: _upgrading,
              onUpgrade: () => _upgradeDatabase(config),
            ),
            const SizedBox(height: 16),
          ],
          if (showSetup) ...[
            _StepCard(
              index: 1,
              title: S.current.notion_step1Title,
              body: S.current.notion_step1Body,
              done: (config.integrationToken ?? '').isNotEmpty,
              children: [
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  onPressed: _openIntegrationsPage,
                  label: Text(S.current.notion_openIntegrationsPage),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: S.current.notion_tokenSection,
                    hintText: 'secret_xxxxxxxxxxxxxxxx',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StepCard(
              index: 2,
              title: S.current.notion_step2Title,
              body: S.current.notion_step2Body,
              done: (config.databaseId ?? '').isNotEmpty,
              children: [
                const SizedBox(height: 12),
                TextField(
                  controller: _databaseIdController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: S.current.notion_databaseSection,
                    hintText: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: S.current.common_paste,
                      icon: const Icon(Icons.paste_rounded),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        final text = data?.text?.trim();
                        if (text != null && text.isNotEmpty) {
                          _databaseIdController.text = text;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  onPressed: _busy ? null : _createTemplateDatabase,
                  label: Text(S.current.notion_createTemplateDb),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                onPressed: _busy ? null : _saveAndTest,
                label: Text(S.current.notion_saveAndTest),
              ),
            ),
          ] else
            _ConfiguredBanner(onEdit: () => setState(() => _editing = true)),
          if (config.isComplete) ...[
            const SizedBox(height: 24),
            _SectionTitle(S.current.notion_syncOptions),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(S.current.notion_autoSyncOnBookmark),
                    subtitle: Text(S.current.notion_autoSyncDesc),
                    value: config.autoSyncOnBookmark,
                    onChanged: (value) {
                      ref
                          .read(notionConfigProvider.notifier)
                          .update(config.copyWith(autoSyncOnBookmark: value));
                    },
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.current.notion_syncScope,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<NotionSyncScope>(
                          segments: [
                            ButtonSegment(
                              value: NotionSyncScope.firstPostOnly,
                              label: Text(S.current.export_firstPostOnly),
                            ),
                            ButtonSegment(
                              value: NotionSyncScope.allPosts,
                              label: Text(S.current.common_all),
                            ),
                          ],
                          selected: {config.syncScope},
                          onSelectionChanged: (selected) {
                            ref
                                .read(notionConfigProvider.notifier)
                                .update(
                                  config.copyWith(syncScope: selected.first),
                                );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _SecurityNote(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_sync_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.current.notion_title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  S.current.notion_subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.body,
    required this.done,
    required this.children,
  });

  final int index;
  final String title;
  final String body;
  final bool done;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: done
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  child: done
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: theme.colorScheme.onPrimary,
                        )
                      : Text('$index', style: theme.textTheme.labelSmall),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _UpgradeBanner extends StatelessWidget {
  const _UpgradeBanner({required this.upgrading, required this.onUpgrade});

  final bool upgrading;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.current.notion_upgradeAvailable,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(S.current.notion_upgradeMessage),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: upgrading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upgrade_rounded),
                onPressed: upgrading ? null : onUpgrade,
                label: Text(S.current.notion_upgradeAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfiguredBanner extends StatelessWidget {
  const _ConfiguredBanner({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle_rounded),
        title: Text(S.current.notion_configured),
        trailing: TextButton.icon(
          icon: const Icon(Icons.edit_outlined, size: 16),
          onPressed: onEdit,
          label: Text(S.current.notion_editConfig),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.current.notion_tokenSecurityNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

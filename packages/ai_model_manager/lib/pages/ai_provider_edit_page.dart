import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/ai_l10n.dart';
import '../models/ai_provider.dart';
import '../providers/ai_provider_providers.dart';
import '../services/ai_provider_service.dart';
import '../services/toast_delegate.dart';
import '../utils/dialog_utils.dart';

/// AI 供应商添加/编辑页面
class AiProviderEditPage extends ConsumerStatefulWidget {
  /// 编辑模式传入现有供应商，添加模式传 null
  final AiProvider? provider;

  const AiProviderEditPage({super.key, this.provider});

  @override
  ConsumerState<AiProviderEditPage> createState() => _AiProviderEditPageState();
}

class _AiProviderEditPageState extends ConsumerState<AiProviderEditPage> {
  late TextEditingController _nameController;
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late AiProviderType _selectedType;
  late List<AiModel> _models;

  bool _obscureApiKey = true;
  bool _isCheckingConnectivity = false;
  bool _isFetchingModels = false;
  bool _isSaving = false;
  /// 连通性检查结果：null=未检查，true=成功，false=失败
  bool? _connectivitySuccess;
  /// 连通性检查失败时的错误信息
  String? _connectivityError;

  /// 正在测试的模型 ID
  String? _testingModelId;

  /// 模型测试结果（modelId -> null 表示成功，String 表示错误）
  final Map<String, String?> _modelTestResults = {};

  bool get _isEditing => widget.provider != null;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.provider?.type ?? AiProviderType.openai;
    _nameController =
        TextEditingController(text: widget.provider?.name ?? '');
    _baseUrlController =
        TextEditingController(text: widget.provider?.baseUrl ?? _selectedType.defaultBaseUrl);
    _apiKeyController = TextEditingController();
    _models = List.from(widget.provider?.models ?? []);

    if (_isEditing) {
      _loadApiKey();
    }
  }

  Future<void> _loadApiKey() async {
    final key =
        await AiProviderListNotifier.getApiKey(widget.provider!.id);
    if (mounted && key != null) {
      _apiKeyController.text = key;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _onTypeChanged(AiProviderType? type) {
    if (type == null) return;
    setState(() {
      // 如果 baseUrl 仍是某个类型的默认值，则自动更新为新类型的默认值
      if (_baseUrlController.text.isEmpty ||
          AiProviderType.values
              .any((t) => t.defaultBaseUrl == _baseUrlController.text)) {
        _baseUrlController.text = type.defaultBaseUrl;
      }
      _selectedType = type;
    });
  }

  Future<void> _checkConnectivity() async {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) {
      AiToastDelegate.showInfo(AiL10n.current.pleaseEnterBaseUrlAndApiKey);
      return;
    }

    setState(() {
      _isCheckingConnectivity = true;
      _connectivitySuccess = null;
      _connectivityError = null;
    });

    try {
      final service = ref.read(aiProviderApiServiceProvider);
      final ok =
          await service.checkConnectivity(_selectedType, baseUrl, apiKey);
      if (mounted) {
        setState(() {
          _connectivitySuccess = ok;
          _connectivityError = ok ? null : '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectivitySuccess = false;
          _connectivityError = AiProviderApiService.friendlyError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingConnectivity = false;
        });
      }
    }
  }

  Future<void> _fetchModels() async {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) {
      AiToastDelegate.showInfo(AiL10n.current.pleaseEnterBaseUrlAndApiKey);
      return;
    }

    setState(() {
      _isFetchingModels = true;
    });

    try {
      final service = ref.read(aiProviderApiServiceProvider);
      final fetched =
          await service.fetchModels(_selectedType, baseUrl, apiKey);

      if (mounted) {
        // 保留已有模型的 enabled 状态
        final existingMap = {for (final m in _models) m.id: m};
        final merged = fetched.map((m) {
          final existing = existingMap[m.id];
          return existing != null ? m.copyWith(enabled: existing.enabled) : m;
        }).toList();

        setState(() {
          _models = merged;
        });
        AiToastDelegate.showSuccess(AiL10n.current.fetchedModelsCount(fetched.length));
      }
    } catch (e) {
      if (mounted) {
        AiToastDelegate.showError(AiL10n.current.fetchModelsFailed(AiProviderApiService.friendlyError(e)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
        });
      }
    }
  }

  void _addModelManually() {
    final controller = TextEditingController();
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AiL10n.current.addModelManually),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: AiL10n.current.modelId,
            hintText: AiL10n.current.modelIdHint,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AiL10n.current.cancel),
          ),
          FilledButton(
            onPressed: () {
              final id = controller.text.trim();
              if (id.isNotEmpty) {
                setState(() {
                  _models.add(AiModel(id: id));
                });
              }
              Navigator.pop(ctx);
            },
            child: Text(AiL10n.current.add),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (name.isEmpty) {
      AiToastDelegate.showInfo(AiL10n.current.pleaseEnterProviderName);
      return;
    }
    if (baseUrl.isEmpty) {
      AiToastDelegate.showInfo(AiL10n.current.pleaseEnterBaseUrl);
      return;
    }
    if (apiKey.isEmpty) {
      AiToastDelegate.showInfo(AiL10n.current.pleaseEnterApiKey);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(aiProviderListProvider.notifier);
      if (_isEditing) {
        await notifier.updateProvider(
          id: widget.provider!.id,
          name: name,
          type: _selectedType,
          baseUrl: baseUrl,
          apiKey: apiKey,
          models: _models,
        );
      } else {
        await notifier.addProvider(
          name: name,
          type: _selectedType,
          baseUrl: baseUrl,
          apiKey: apiKey,
          models: _models,
        );
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AiToastDelegate.showError(AiL10n.current.saveFailed(AiProviderApiService.friendlyError(e)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _setDefaultModel(
      WidgetRef ref, String providerId, String modelId, bool isDefault) {
    if (isDefault) {
      clearDefaultAiModel(ref);
      AiToastDelegate.showInfo(AiL10n.current.defaultModelCleared);
    } else {
      setDefaultAiModel(ref, providerId, modelId);
      AiToastDelegate.showSuccess(AiL10n.current.setAsDefaultModel);
    }
  }

  Future<void> _testModel(String modelId) async {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) {
      AiToastDelegate.showInfo(AiL10n.current.pleaseEnterBaseUrlAndApiKeyFirst);
      return;
    }

    setState(() {
      _testingModelId = modelId;
      _modelTestResults.remove(modelId);
    });

    try {
      final service = ref.read(aiProviderApiServiceProvider);
      final error =
          await service.testModel(_selectedType, baseUrl, apiKey, modelId);
      if (mounted) {
        setState(() {
          _modelTestResults[modelId] = error;
          _testingModelId = null;
        });
        if (error == null) {
          AiToastDelegate.showSuccess(AiL10n.current.modelAvailable(modelId));
        } else {
          AiToastDelegate.showError(AiL10n.current.modelUnavailable(modelId, error));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _modelTestResults[modelId] = AiProviderApiService.friendlyError(e);
          _testingModelId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? AiL10n.current.editProvider : AiL10n.current.addProvider),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(AiL10n.current.save),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBasicConfigCard(theme),
          const SizedBox(height: 16),
          _buildModelsCard(theme),
        ],
      ),
    );
  }

  Widget _buildBasicConfigCard(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AiL10n.current.basicConfig,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // 名称
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: AiL10n.current.name,
                hintText: AiL10n.current.nameHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // 类型
            DropdownButtonFormField<AiProviderType>(
              initialValue: _selectedType,
              decoration: InputDecoration(
                labelText: AiL10n.current.providerType,
                border: const OutlineInputBorder(),
              ),
              items: AiProviderType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.label),
                      ))
                  .toList(),
              onChanged: _onTypeChanged,
            ),
            const SizedBox(height: 12),
            // Base URL
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // API Key
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureApiKey
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _obscureApiKey = !_obscureApiKey;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 连通性检查
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _isCheckingConnectivity ? null : _checkConnectivity,
                  icon: _isCheckingConnectivity
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(AiL10n.current.connectivityCheck),
                ),
                if (_connectivitySuccess != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _connectivitySuccess!
                            ? Icons.check_circle
                            : Icons.error,
                        size: 18,
                        color: _connectivitySuccess!
                            ? Colors.green
                            : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _connectivitySuccess!
                              ? AiL10n.current.connectionSuccess
                              : (_connectivityError != null && _connectivityError!.isNotEmpty
                                  ? AiL10n.current.connectionFailedWithError(_connectivityError!)
                                  : AiL10n.current.connectionFailed),
                          style: TextStyle(
                            fontSize: 13,
                            color: _connectivitySuccess!
                                ? Colors.green
                                : theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelsCard(ThemeData theme) {
    final enabledCount = _models.where((m) => m.enabled).length;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(AiL10n.current.modelManagement,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (_models.isNotEmpty)
                  Text('$enabledCount/${_models.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isFetchingModels ? null : _fetchModels,
                  icon: _isFetchingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 18),
                  label: Text(AiL10n.current.fetchModels),
                ),
                OutlinedButton.icon(
                  onPressed: _addModelManually,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(AiL10n.current.manuallyAdd),
                ),
              ],
            ),
            if (_models.isNotEmpty) ...[
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final defaultKey = ref.watch(defaultAiModelKeyProvider);
                  final providerId = widget.provider?.id;

                  return Column(
                    children: _models.asMap().entries.map((entry) {
                      final index = entry.key;
                      final model = entry.value;
                      final isTesting = _testingModelId == model.id;
                      final testResult = _modelTestResults[model.id];
                      final hasTestResult =
                          _modelTestResults.containsKey(model.id);
                      final isDefault = providerId != null &&
                          defaultKey == '$providerId:${model.id}';

                      return _buildModelItem(
                        theme: theme,
                        ref: ref,
                        model: model,
                        index: index,
                        providerId: providerId,
                        isDefault: isDefault,
                        isTesting: isTesting,
                        testResult: testResult,
                        hasTestResult: hasTestResult,
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelItem({
    required ThemeData theme,
    required WidgetRef ref,
    required AiModel model,
    required int index,
    required String? providerId,
    required bool isDefault,
    required bool isTesting,
    required String? testResult,
    required bool hasTestResult,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 主行：模型名称 + 启用开关
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name ?? model.id,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (model.name != null)
                        Text(
                          model.id,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: model.enabled,
                    onChanged: (val) {
                      setState(() {
                        _models[index] = model.copyWith(enabled: val);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          // 底部操作栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                _ModelActionChip(
                  icon: isTesting
                      ? null
                      : hasTestResult
                          ? (testResult == null
                              ? Icons.check_circle
                              : Icons.error_outline)
                          : Icons.play_arrow_rounded,
                  label: AiL10n.current.test,
                  isLoading: isTesting,
                  highlightColor: hasTestResult && !isTesting
                      ? (testResult == null ? Colors.green : theme.colorScheme.error)
                      : null,
                  onTap: isTesting ? null : () => _testModel(model.id),
                ),
                if (_isEditing) ...[
                  const SizedBox(width: 8),
                  _ModelActionChip(
                    icon: isDefault ? Icons.star_rounded : Icons.star_outline_rounded,
                    label: isDefault ? AiL10n.current.cancelDefault : AiL10n.current.setAsDefault,
                    highlightColor: isDefault ? Colors.amber[700] : null,
                    onTap: () => _setDefaultModel(
                        ref, providerId!, model.id, isDefault),
                  ),
                ],
                const Spacer(),
                _ModelActionChip(
                  icon: Icons.delete_outline,
                  label: AiL10n.current.remove,
                  isDestructive: true,
                  onTap: () {
                    setState(() {
                      _models.removeAt(index);
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 模型操作小按钮
class _ModelActionChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isLoading;

  final Color? highlightColor;

  const _ModelActionChip({
    this.icon,
    required this.label,
    this.onTap,
    this.isDestructive = false,
    this.isLoading = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlightColor ??
        (isDestructive
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: isLoading
                  ? CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: color,
                    )
                  : icon != null
                      ? Icon(icon, size: 14, color: color)
                      : const SizedBox.shrink(),
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_provider.dart';
import '../providers/ai_provider_providers.dart';
import '../services/ai_provider_service.dart';
import '../services/toast_delegate.dart';

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
  String? _connectivityResult;

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
      AiToastDelegate.showInfo('请填写 Base URL 和 API Key');
      return;
    }

    setState(() {
      _isCheckingConnectivity = true;
      _connectivityResult = null;
    });

    try {
      final service = ref.read(aiProviderApiServiceProvider);
      final ok =
          await service.checkConnectivity(_selectedType, baseUrl, apiKey);
      if (mounted) {
        setState(() {
          _connectivityResult = ok ? '连接成功' : '连接失败';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectivityResult = '连接失败: ${AiProviderApiService.friendlyError(e)}';
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
      AiToastDelegate.showInfo('请填写 Base URL 和 API Key');
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
        AiToastDelegate.showSuccess('获取到 ${fetched.length} 个模型');
      }
    } catch (e) {
      if (mounted) {
        AiToastDelegate.showError('获取模型失败: ${AiProviderApiService.friendlyError(e)}');
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动添加模型'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '模型 ID',
            hintText: '例如: gpt-4o',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
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
            child: const Text('添加'),
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
      AiToastDelegate.showInfo('请输入供应商名称');
      return;
    }
    if (baseUrl.isEmpty) {
      AiToastDelegate.showInfo('请输入 Base URL');
      return;
    }
    if (apiKey.isEmpty) {
      AiToastDelegate.showInfo('请输入 API Key');
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
        AiToastDelegate.showError('保存失败: ${AiProviderApiService.friendlyError(e)}');
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
      AiToastDelegate.showInfo('已取消默认模型');
    } else {
      setDefaultAiModel(ref, providerId, modelId);
      AiToastDelegate.showSuccess('已设为默认模型');
    }
  }

  Future<void> _testModel(String modelId) async {
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) {
      AiToastDelegate.showInfo('请先填写 Base URL 和 API Key');
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
          AiToastDelegate.showSuccess('模型 $modelId 可用');
        } else {
          AiToastDelegate.showError('模型 $modelId 不可用: $error');
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
        title: Text(_isEditing ? '编辑供应商' : '添加供应商'),
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
                  : const Text('保存'),
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
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('基础配置',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // 名称
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如: 我的 OpenAI',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // 类型
            DropdownButtonFormField<AiProviderType>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: '供应商类型',
                border: OutlineInputBorder(),
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
                  label: const Text('连通性检查'),
                ),
                if (_connectivityResult != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _connectivityResult == '连接成功'
                            ? Icons.check_circle
                            : Icons.error,
                        size: 18,
                        color: _connectivityResult == '连接成功'
                            ? Colors.green
                            : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _connectivityResult!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _connectivityResult == '连接成功'
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
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('模型管理',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text('${_models.where((m) => m.enabled).length}/${_models.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            // 操作按钮
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
                  label: const Text('获取模型'),
                ),
                OutlinedButton.icon(
                  onPressed: _addModelManually,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('手动添加'),
                ),
              ],
            ),
            if (_models.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              // 用 Consumer 获取默认模型信息
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

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onLongPress: _isEditing
                            ? () => _setDefaultModel(
                                ref, providerId!, model.id, isDefault)
                            : null,
                        title: Row(
                          children: [
                            if (isDefault)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(Icons.star_rounded,
                                    size: 16, color: Colors.amber[700]),
                              ),
                            Expanded(
                              child: Text(model.name ?? model.id,
                                  style: const TextStyle(fontSize: 14)),
                            ),
                            if (hasTestResult)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  testResult == null
                                      ? Icons.check_circle
                                      : Icons.error_outline,
                                  size: 16,
                                  color: testResult == null
                                      ? Colors.green
                                      : theme.colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                        subtitle: model.name != null
                            ? Text(model.id,
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        theme.colorScheme.onSurfaceVariant))
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 测试按钮
                            IconButton(
                              icon: isTesting
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : Icon(Icons.play_circle_outline,
                                      size: 20,
                                      color: theme.colorScheme.primary),
                              tooltip: '测试模型',
                              onPressed: isTesting
                                  ? null
                                  : () => _testModel(model.id),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: model.enabled,
                              onChanged: (val) {
                                setState(() {
                                  _models[index] =
                                      model.copyWith(enabled: val);
                                });
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.close,
                                  size: 18,
                                  color: theme.colorScheme.error),
                              onPressed: () {
                                setState(() {
                                  _models.removeAt(index);
                                });
                              },
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
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
}

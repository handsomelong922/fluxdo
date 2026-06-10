import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/ai_provider.dart';
import '../services/ai_chat_storage_service.dart';
import '../services/ai_provider_service.dart';

/// 需要主应用在 ProviderScope.overrides 中注入
final aiSharedPreferencesProvider = Provider<SharedPreferences>((_) {
  throw UnimplementedError(
      'aiSharedPreferencesProvider 必须在 ProviderScope.overrides 中注入');
});

/// 可选的 HttpClientAdapter 工厂，由主应用在 ProviderScope.overrides 中注入
/// 用于让 AI 请求复用应用的网络配置（代理等）
final aiDioAdapterFactoryProvider =
    Provider<HttpClientAdapter Function()?>((_) => null);

/// 是否跟随应用网络配置
final aiUseAppNetworkProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(aiSharedPreferencesProvider);
  return prefs.getBool('ai_use_app_network') ?? false;
});

/// AI 聊天存储服务
final aiChatStorageServiceProvider = Provider<AiChatStorageService>((ref) {
  final prefs = ref.watch(aiSharedPreferencesProvider);
  return AiChatStorageService(prefs);
});

/// 供应商列表状态管理
final aiProviderListProvider =
    StateNotifierProvider<AiProviderListNotifier, List<AiProvider>>((ref) {
  final prefs = ref.watch(aiSharedPreferencesProvider);
  return AiProviderListNotifier(prefs);
});

/// API 服务
final aiProviderApiServiceProvider = Provider((ref) {
  final useAppNetwork = ref.watch(aiUseAppNetworkProvider);
  final adapterFactory = ref.watch(aiDioAdapterFactoryProvider);
  return AiProviderApiService(
    adapterFactory: useAppNetwork ? adapterFactory : null,
  );
});

/// 默认 AI 模型 key（providerId:modelId）
final defaultAiModelKeyProvider = StateProvider<String?>((ref) {
  final prefs = ref.watch(aiSharedPreferencesProvider);
  return prefs.getString('ai_default_model');
});

/// 设置默认模型
Future<void> setDefaultAiModel(
    WidgetRef ref, String providerId, String modelId) async {
  final prefs = ref.read(aiSharedPreferencesProvider);
  final key = '$providerId:$modelId';
  await prefs.setString('ai_default_model', key);
  ref.read(defaultAiModelKeyProvider.notifier).state = key;
}

/// 清除默认模型
Future<void> clearDefaultAiModel(WidgetRef ref) async {
  final prefs = ref.read(aiSharedPreferencesProvider);
  await prefs.remove('ai_default_model');
  ref.read(defaultAiModelKeyProvider.notifier).state = null;
}

/// 供应商列表 Notifier
class AiProviderListNotifier extends StateNotifier<List<AiProvider>> {
  static const String _storageKey = 'ai_providers';
  static const String _kApiKeyPrefix = 'ai_apikey_';
  static const String _kLegacyKeychainPrefix = 'ai_provider_key_';
  static const String _kLegacyFallbackPrefix =
      '__secure_fallback__ai_provider_key_';
  static const _uuid = Uuid();

  /// 仅作为旧版本 Keychain 数据迁移源；新写入统一走 SharedPreferences。
  static const FlutterSecureStorage _legacyKeychain = FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  final SharedPreferences _prefs;

  AiProviderListNotifier(this._prefs) : super([]) {
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      state = list
          .map((e) => AiProvider.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 数据损坏时忽略
    }
  }

  Future<void> _save() async {
    final json = state.map((p) => p.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(json));
  }

  /// 添加供应商，返回新供应商 id
  Future<String> addProvider({
    required String name,
    required AiProviderType type,
    required String baseUrl,
    required String apiKey,
    List<AiModel> models = const [],
  }) async {
    final id = _uuid.v4();
    final provider = AiProvider(
      id: id,
      name: name,
      type: type,
      baseUrl: baseUrl,
      models: models,
    );
    state = [...state, provider];
    await _save();
    await _saveApiKey(id, apiKey);
    return id;
  }

  /// 更新供应商
  Future<void> updateProvider({
    required String id,
    String? name,
    AiProviderType? type,
    String? baseUrl,
    String? apiKey,
    List<AiModel>? models,
  }) async {
    state = state.map((p) {
      if (p.id != id) return p;
      return p.copyWith(
        name: name,
        type: type,
        baseUrl: baseUrl,
        models: models,
      );
    }).toList();
    await _save();
    if (apiKey != null) {
      await _saveApiKey(id, apiKey);
    }
  }

  /// 删除供应商
  Future<void> removeProvider(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _save();
    await _deleteApiKey(id);
  }

  /// 更新模型列表
  Future<void> updateModels(String id, List<AiModel> models) async {
    state = state.map((p) {
      if (p.id != id) return p;
      return p.copyWith(models: models);
    }).toList();
    await _save();
  }

  /// 获取 API Key
  static Future<String?> getApiKey(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    final plain = prefs.getString('$_kApiKeyPrefix$providerId');
    if (plain != null && plain.trim().isNotEmpty) {
      return plain.trim();
    }
    return _migrateLegacyApiKey(providerId, prefs);
  }

  static Future<String?> _migrateLegacyApiKey(
    String providerId,
    SharedPreferences prefs,
  ) async {
    String? value;
    try {
      final fromKeychain = await _legacyKeychain.read(
        key: '$_kLegacyKeychainPrefix$providerId',
      );
      if (fromKeychain != null && fromKeychain.trim().isNotEmpty) {
        value = fromKeychain.trim();
      }
    } catch (_) {
      // 自签 / 未签名 / 无 keyring 等场景下 Keychain 读取可能失败，继续看旧 fallback。
    }

    value ??= prefs.getString('$_kLegacyFallbackPrefix$providerId')?.trim();
    if (value == null || value.isEmpty) return null;

    await prefs.setString('$_kApiKeyPrefix$providerId', value);
    await prefs.remove('$_kLegacyFallbackPrefix$providerId');
    try {
      await _legacyKeychain.delete(key: '$_kLegacyKeychainPrefix$providerId');
    } catch (_) {}
    return value;
  }

  static Future<void> _saveApiKey(String providerId, String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await _deleteApiKey(providerId);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kApiKeyPrefix$providerId', trimmed);
    await prefs.remove('$_kLegacyFallbackPrefix$providerId');
    try {
      await _legacyKeychain.delete(key: '$_kLegacyKeychainPrefix$providerId');
    } catch (_) {}
  }

  static Future<void> _deleteApiKey(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kApiKeyPrefix$providerId');
    await prefs.remove('$_kLegacyFallbackPrefix$providerId');
    try {
      await _legacyKeychain.delete(key: '$_kLegacyKeychainPrefix$providerId');
    } catch (_) {}
  }
}

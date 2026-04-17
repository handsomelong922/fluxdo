import 'dart:ui';

import 'ai_l10n_en.dart';
import 'ai_l10n_zh_hk.dart';
import 'ai_l10n_zh_tw.dart';

/// AI 模型管理包的本地化代理
/// 由主项目在启动时通过 configureLocale 配置语言
class AiL10n {
  static AiL10n? _instance;

  static AiL10n get current => _instance ?? _defaultInstance;

  /// 根据 Locale 配置语言
  static void configureLocale(Locale locale) {
    if (locale.languageCode == 'en') {
      _instance = AiL10nEn();
    } else if (locale.languageCode == 'zh') {
      switch (locale.countryCode) {
        case 'TW':
          _instance = AiL10nZhTW();
        case 'HK':
          _instance = AiL10nZhHK();
        default:
          _instance = _defaultInstance;
      }
    } else {
      _instance = _defaultInstance;
    }
  }

  /// 直接注入自定义实例
  static void configure(AiL10n instance) {
    _instance = instance;
  }

  // 默认中文实例
  static final _defaultInstance = AiL10n();

  // ---- 通用 ----
  String get cancel => '取消';
  String get delete => '删除';
  String get save => '保存';
  String get add => '添加';
  String get edit => '编辑';
  String get remove => '移除';
  String get test => '测试';
  String get notSet => '未设置';
  String get name => '名称';
  String get import_ => '导入';

  // ---- AI 模型服务页 ----
  String get aiModelService => 'AI 模型服务';
  String get addProvider => '添加供应商';
  String get editProvider => '编辑供应商';
  String get noProviderConfigured => '还没有配置 AI 供应商';
  String get addProviderHint => '添加供应商后可以使用 AI 助手功能';
  String get confirmDelete => '确认删除';
  String confirmDeleteProvider(String name) => '确定要删除供应商「$name」吗？';
  String modelCount(int enabled, int total) => '$enabled/$total 个模型';
  String get chatHistory => '聊天记录';
  String get titleGenerationModel => '标题生成模型';
  String get autoGenerateTitleSubtitle => '自动为新会话生成标题';
  String get noAutoGenerateTitle => '不自动生成标题';
  String get maxSessionCount => '最大会话记录数';
  String get autoDeleteOldestSession => '超出上限时自动删除最旧的会话';
  String get sessionManagement => '会话记录管理';
  String totalSessionCount(int count) => '共 $count 条会话';

  // ---- 网络设置 ----
  String get useAppNetwork => '跟随应用网络配置';
  String get useAppNetworkSubtitle => '开启后 AI 请求将使用应用的代理等网络设置';

  // ---- 供应商编辑页 ----
  String get pleaseEnterBaseUrlAndApiKey => '请填写 Base URL 和 API Key';
  String get connectionSuccess => '连接成功';
  String get connectionFailed => '连接失败';
  String connectionFailedWithError(String error) => '连接失败: $error';
  String fetchedModelsCount(int count) => '获取到 $count 个模型';
  String fetchModelsFailed(String error) => '获取模型失败: $error';
  String get addModelManually => '手动添加模型';
  String get modelId => '模型 ID';
  String get modelIdHint => '例如: gpt-4o';
  String get pleaseEnterProviderName => '请输入供应商名称';
  String get pleaseEnterBaseUrl => '请输入 Base URL';
  String get pleaseEnterApiKey => '请输入 API Key';
  String get pleaseEnterBaseUrlAndApiKeyFirst => '请先填写 Base URL 和 API Key';
  String saveFailed(String error) => '保存失败: $error';
  String get defaultModelCleared => '已取消默认模型';
  String get setAsDefaultModel => '已设为默认模型';
  String modelAvailable(String id) => '模型 $id 可用';
  String modelUnavailable(String id, String error) => '模型 $id 不可用: $error';
  String get basicConfig => '基础配置';
  String get nameHint => '例如: 我的 OpenAI';
  String get providerType => '供应商类型';
  String get connectivityCheck => '连通性检查';
  String get modelManagement => '模型管理';
  String get fetchModels => '获取模型';
  String get manuallyAdd => '手动添加';
  String get cancelDefault => '取消默认';
  String get setAsDefault => '设为默认';

  // ---- 聊天历史页 ----
  String get sessionHistory => '会话记录';
  String get clearAllConversations => '清除所有对话';
  String get noSessionHistory => '暂无会话记录';
  String confirmDeleteAllSessions(int count) =>
      '确定要删除全部 $count 条会话记录吗？此操作不可恢复。';
  String get clearAll => '清除全部';
  String topicWithId(int id) => '话题 #$id';
  String sessionCount(int count) => '$count 条会话';
  String get deleteAllTopicSessions => '删除此话题所有会话';
  String get unnamedSession => '未命名会话';
  String get deleteTopicSessions => '删除话题会话';
  String confirmDeleteTopicSessions(String title) =>
      '确定要删除「$title」的所有会话记录吗？';
  String get justNow => '刚刚';
  String minutesAgo(int count) => '$count 分钟前';
  String hoursAgo(int count) => '$count 小时前';
  String daysAgo(int count) => '$count 天前';

  // ---- 上下文选项 ----
  String get firstPostOnly => '仅主帖';
  String get first5Posts => '前 5 楼';
  String get first10Posts => '前 10 楼';
  String get first20Posts => '前 20 楼';
  String get allPosts => '全部帖子';

  // ---- 网络错误 ----
  String get connectionTimeoutError => '连接超时，请检查网络或 Base URL 是否正确';
  String get cannotConnectError => '无法连接到服务器，请检查 Base URL 是否正确';
  String get apiKeyNotFoundError => '无法读取 API Key，请重新配置供应商';
  String get apiKeyInvalidError => 'API Key 无效或已过期 (401)';
  String get noAccessPermissionError => '没有访问权限，请检查 API Key (403)';
  String get endpointNotFoundError => '接口地址不存在，请检查 Base URL (404)';
  String get tooManyRequestsError => '请求过于频繁，请稍后重试 (429)';
  String serverInternalError(int code) => '服务器内部错误 ($code)';
  String requestFailed(int code) => '请求失败 ($code)';
  String get requestCancelled => '请求已取消';
  String get sslCertificateError => 'SSL 证书验证失败';
  String get networkConnectionFailed => '网络连接失败，请检查网络设置';
  String get unknownNetworkError => '未知网络错误';
  String get emptyResponseError => '未收到 AI 回复，请检查网络设置或重试';

  // ---- System Prompts（影响 AI 回复语言） ----
  String get systemPromptIntro =>
      '你是一个有帮助的 AI 助手，正在帮助用户理解和讨论一个论坛话题。';
  String systemPromptTopicTitle(String title) => '话题标题：$title';
  String get systemPromptContextHint =>
      '用户可能会就话题内容向你提问，请基于提供的上下文回答。';
  String get systemPromptMarkdown => '请用 Markdown 格式回复。';
  String contextContentPrefix(String text) => '以下是话题内容：\n$text';
  String get contextReadyResponse => '好的，我已经阅读了话题内容。请问你有什么问题？';
  String get titleGenerationPrompt =>
      '请用不超过15个字概括用户这段话的主题，直接输出标题文字，不要加标点符号和引号。';
}

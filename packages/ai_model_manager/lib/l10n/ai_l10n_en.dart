import 'ai_l10n.dart';

/// 英文翻译
class AiL10nEn extends AiL10n {
  // ---- 通用 ----
  @override
  String get cancel => 'Cancel';
  @override
  String get delete => 'Delete';
  @override
  String get save => 'Save';
  @override
  String get add => 'Add';
  @override
  String get edit => 'Edit';
  @override
  String get remove => 'Remove';
  @override
  String get test => 'Test';
  @override
  String get notSet => 'Not set';
  @override
  String get name => 'Name';
  @override
  String get import_ => 'Import';

  // ---- AI 模型服务页 ----
  @override
  String get aiModelService => 'AI Model Service';
  @override
  String get addProvider => 'Add Provider';
  @override
  String get editProvider => 'Edit Provider';
  @override
  String get noProviderConfigured => 'No AI provider configured';
  @override
  String get addProviderHint =>
      'Add a provider to use the AI assistant feature';
  @override
  String get confirmDelete => 'Confirm Delete';
  @override
  String confirmDeleteProvider(String name) =>
      'Are you sure you want to delete provider "$name"?';
  @override
  String modelCount(int enabled, int total) => '$enabled/$total models';
  @override
  String get chatHistory => 'Chat History';
  @override
  String get titleGenerationModel => 'Title Generation Model';
  @override
  String get autoGenerateTitleSubtitle =>
      'Auto-generate titles for new sessions';
  @override
  String get noAutoGenerateTitle => 'Do not auto-generate titles';
  @override
  String get maxSessionCount => 'Max Session Count';
  @override
  String get autoDeleteOldestSession =>
      'Auto-delete oldest session when limit is exceeded';
  @override
  String get sessionManagement => 'Session Management';
  @override
  String totalSessionCount(int count) => '$count sessions total';

  // ---- 网络设置 ----
  @override
  String get useAppNetwork => 'Follow App Network Config';
  @override
  String get useAppNetworkSubtitle =>
      'AI requests will use the app\'s proxy and network settings when enabled';

  // ---- 供应商编辑页 ----
  @override
  String get pleaseEnterBaseUrlAndApiKey =>
      'Please enter Base URL and API Key';
  @override
  String get connectionSuccess => 'Connection successful';
  @override
  String get connectionFailed => 'Connection failed';
  @override
  String connectionFailedWithError(String error) =>
      'Connection failed: $error';
  @override
  String fetchedModelsCount(int count) => 'Fetched $count models';
  @override
  String fetchModelsFailed(String error) => 'Failed to fetch models: $error';
  @override
  String get addModelManually => 'Add Model Manually';
  @override
  String get modelId => 'Model ID';
  @override
  String get modelIdHint => 'e.g. gpt-4o';
  @override
  String get pleaseEnterProviderName => 'Please enter provider name';
  @override
  String get pleaseEnterBaseUrl => 'Please enter Base URL';
  @override
  String get pleaseEnterApiKey => 'Please enter API Key';
  @override
  String get pleaseEnterBaseUrlAndApiKeyFirst =>
      'Please enter Base URL and API Key first';
  @override
  String saveFailed(String error) => 'Save failed: $error';
  @override
  String get defaultModelCleared => 'Default model cleared';
  @override
  String get setAsDefaultModel => 'Set as default model';
  @override
  String modelAvailable(String id) => 'Model $id is available';
  @override
  String modelUnavailable(String id, String error) =>
      'Model $id unavailable: $error';
  @override
  String get basicConfig => 'Basic Configuration';
  @override
  String get nameHint => 'e.g. My OpenAI';
  @override
  String get providerType => 'Provider Type';
  @override
  String get connectivityCheck => 'Connectivity Check';
  @override
  String get modelManagement => 'Model Management';
  @override
  String get fetchModels => 'Fetch Models';
  @override
  String get manuallyAdd => 'Add Manually';
  @override
  String get cancelDefault => 'Unset Default';
  @override
  String get setAsDefault => 'Set Default';

  // ---- 聊天历史页 ----
  @override
  String get sessionHistory => 'Session History';
  @override
  String get clearAllConversations => 'Clear all conversations';
  @override
  String get noSessionHistory => 'No session history';
  @override
  String confirmDeleteAllSessions(int count) =>
      'Are you sure you want to delete all $count sessions? This action cannot be undone.';
  @override
  String get clearAll => 'Clear All';
  @override
  String topicWithId(int id) => 'Topic #$id';
  @override
  String sessionCount(int count) => '$count sessions';
  @override
  String get deleteAllTopicSessions => 'Delete all sessions for this topic';
  @override
  String get unnamedSession => 'Unnamed session';
  @override
  String get deleteTopicSessions => 'Delete Topic Sessions';
  @override
  String confirmDeleteTopicSessions(String title) =>
      'Are you sure you want to delete all sessions for "$title"?';
  @override
  String get justNow => 'Just now';
  @override
  String minutesAgo(int count) => '$count min ago';
  @override
  String hoursAgo(int count) => '$count hr ago';
  @override
  String daysAgo(int count) => '$count days ago';

  // ---- 上下文选项 ----
  @override
  String get firstPostOnly => 'First post only';
  @override
  String get first5Posts => 'First 5 posts';
  @override
  String get first10Posts => 'First 10 posts';
  @override
  String get first20Posts => 'First 20 posts';
  @override
  String get allPosts => 'All posts';

  // ---- 网络错误 ----
  @override
  String get connectionTimeoutError =>
      'Connection timed out. Please check your network or Base URL';
  @override
  String get cannotConnectError =>
      'Cannot connect to server. Please check your Base URL';
  @override
  @override
  String get apiKeyNotFoundError =>
      'Unable to read API Key. Please reconfigure the provider';
  @override
  String get apiKeyInvalidError => 'API Key is invalid or expired (401)';
  @override
  String get noAccessPermissionError =>
      'No access permission. Please check your API Key (403)';
  @override
  String get endpointNotFoundError =>
      'Endpoint not found. Please check your Base URL (404)';
  @override
  String get tooManyRequestsError =>
      'Too many requests. Please try again later (429)';
  @override
  String serverInternalError(int code) => 'Server internal error ($code)';
  @override
  String requestFailed(int code) => 'Request failed ($code)';
  @override
  String get requestCancelled => 'Request cancelled';
  @override
  String get sslCertificateError => 'SSL certificate verification failed';
  @override
  String get networkConnectionFailed =>
      'Network connection failed. Please check your network settings';
  @override
  String get unknownNetworkError => 'Unknown network error';
  @override
  String get emptyResponseError =>
      'No response received from AI. Please check network settings or retry';

  // ---- System Prompts ----
  @override
  String get systemPromptIntro =>
      'You are a helpful AI assistant helping the user understand and discuss a forum topic.';
  @override
  String systemPromptTopicTitle(String title) => 'Topic title: $title';
  @override
  String get systemPromptContextHint =>
      'The user may ask you questions about the topic content. Please answer based on the provided context.';
  @override
  String get systemPromptMarkdown => 'Please respond in Markdown format.';
  @override
  String contextContentPrefix(String text) =>
      'Here is the topic content:\n$text';
  @override
  String get contextReadyResponse =>
      'OK, I have read the topic content. What questions do you have?';
  @override
  String get titleGenerationPrompt =>
      'Summarize the topic of this text in no more than 10 words. Output the title text directly without punctuation or quotes.';
}

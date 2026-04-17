import 'ai_l10n.dart';

/// 繁體中文（香港）翻譯
class AiL10nZhHK extends AiL10n {
  // ---- 通用 ----
  @override
  String get cancel => '取消';
  @override
  String get delete => '刪除';
  @override
  String get save => '保存';
  @override
  String get add => '添加';
  @override
  String get edit => '編輯';
  @override
  String get remove => '移除';
  @override
  String get test => '測試';
  @override
  String get notSet => '未設置';
  @override
  String get name => '名稱';
  @override
  String get import_ => '導入';

  // ---- AI 模型服務頁 ----
  @override
  String get aiModelService => 'AI 模型服務';
  @override
  String get addProvider => '添加供應商';
  @override
  String get editProvider => '編輯供應商';
  @override
  String get noProviderConfigured => '還沒有配置 AI 供應商';
  @override
  String get addProviderHint => '添加供應商後可以使用 AI 助手功能';
  @override
  String get confirmDelete => '確認刪除';
  @override
  String confirmDeleteProvider(String name) => '確定要刪除供應商「$name」嗎？';
  @override
  String modelCount(int enabled, int total) => '$enabled/$total 個模型';
  @override
  String get chatHistory => '聊天記錄';
  @override
  String get titleGenerationModel => '標題生成模型';
  @override
  String get autoGenerateTitleSubtitle => '自動為新會話生成標題';
  @override
  String get noAutoGenerateTitle => '不自動生成標題';
  @override
  String get maxSessionCount => '最大會話記錄數';
  @override
  String get autoDeleteOldestSession => '超出上限時自動刪除最舊的會話';
  @override
  String get sessionManagement => '會話記錄管理';
  @override
  String totalSessionCount(int count) => '共 $count 條會話';

  // ---- 網絡設置 ----
  @override
  String get useAppNetwork => '跟隨應用網絡配置';
  @override
  String get useAppNetworkSubtitle => '開啟後 AI 請求將使用應用的代理等網絡設置';

  // ---- 供應商編輯頁 ----
  @override
  String get pleaseEnterBaseUrlAndApiKey => '請填寫 Base URL 和 API Key';
  @override
  String get connectionSuccess => '連接成功';
  @override
  String get connectionFailed => '連接失敗';
  @override
  String connectionFailedWithError(String error) => '連接失敗: $error';
  @override
  String fetchedModelsCount(int count) => '獲取到 $count 個模型';
  @override
  String fetchModelsFailed(String error) => '獲取模型失敗: $error';
  @override
  String get addModelManually => '手動添加模型';
  @override
  String get modelId => '模型 ID';
  @override
  String get modelIdHint => '例如: gpt-4o';
  @override
  String get pleaseEnterProviderName => '請輸入供應商名稱';
  @override
  String get pleaseEnterBaseUrl => '請輸入 Base URL';
  @override
  String get pleaseEnterApiKey => '請輸入 API Key';
  @override
  String get pleaseEnterBaseUrlAndApiKeyFirst => '請先填寫 Base URL 和 API Key';
  @override
  String saveFailed(String error) => '保存失敗: $error';
  @override
  String get defaultModelCleared => '已取消預設模型';
  @override
  String get setAsDefaultModel => '已設為預設模型';
  @override
  String modelAvailable(String id) => '模型 $id 可用';
  @override
  String modelUnavailable(String id, String error) => '模型 $id 不可用: $error';
  @override
  String get basicConfig => '基礎配置';
  @override
  String get nameHint => '例如: 我的 OpenAI';
  @override
  String get providerType => '供應商類型';
  @override
  String get connectivityCheck => '連接檢查';
  @override
  String get modelManagement => '模型管理';
  @override
  String get fetchModels => '獲取模型';
  @override
  String get manuallyAdd => '手動添加';
  @override
  String get cancelDefault => '取消預設';
  @override
  String get setAsDefault => '設為預設';

  // ---- 聊天歷史頁 ----
  @override
  String get sessionHistory => '會話記錄';
  @override
  String get clearAllConversations => '清除所有對話';
  @override
  String get noSessionHistory => '暫無會話記錄';
  @override
  String confirmDeleteAllSessions(int count) =>
      '確定要刪除全部 $count 條會話記錄嗎？此操作不可恢復。';
  @override
  String get clearAll => '清除全部';
  @override
  String topicWithId(int id) => '話題 #$id';
  @override
  String sessionCount(int count) => '$count 條會話';
  @override
  String get deleteAllTopicSessions => '刪除此話題所有會話';
  @override
  String get unnamedSession => '未命名會話';
  @override
  String get deleteTopicSessions => '刪除話題會話';
  @override
  String confirmDeleteTopicSessions(String title) =>
      '確定要刪除「$title」的所有會話記錄嗎？';
  @override
  String get justNow => '剛剛';
  @override
  String minutesAgo(int count) => '$count 分鐘前';
  @override
  String hoursAgo(int count) => '$count 小時前';
  @override
  String daysAgo(int count) => '$count 天前';

  // ---- 上下文選項 ----
  @override
  String get firstPostOnly => '僅主帖';
  @override
  String get first5Posts => '前 5 樓';
  @override
  String get first10Posts => '前 10 樓';
  @override
  String get first20Posts => '前 20 樓';
  @override
  String get allPosts => '全部帖子';

  // ---- 網絡錯誤 ----
  @override
  String get connectionTimeoutError => '連接超時，請檢查網絡或 Base URL 是否正確';
  @override
  String get cannotConnectError => '無法連接到服務器，請檢查 Base URL 是否正確';
  @override
  @override
  String get apiKeyNotFoundError => '無法讀取 API Key，請重新配置供應商';
  @override
  String get apiKeyInvalidError => 'API Key 無效或已過期 (401)';
  @override
  String get noAccessPermissionError => '沒有訪問權限，請檢查 API Key (403)';
  @override
  String get endpointNotFoundError => '接口地址不存在，請檢查 Base URL (404)';
  @override
  String get tooManyRequestsError => '請求過於頻繁，請稍後重試 (429)';
  @override
  String serverInternalError(int code) => '服務器內部錯誤 ($code)';
  @override
  String requestFailed(int code) => '請求失敗 ($code)';
  @override
  String get requestCancelled => '請求已取消';
  @override
  String get sslCertificateError => 'SSL 證書驗證失敗';
  @override
  String get networkConnectionFailed => '網絡連接失敗，請檢查網絡設置';
  @override
  String get unknownNetworkError => '未知網絡錯誤';
  @override
  String get emptyResponseError => '未收到 AI 回覆，請檢查網絡設定或重試';

  // ---- System Prompts ----
  @override
  String get systemPromptIntro =>
      '你是一個有幫助的 AI 助手，正在幫助用戶理解和討論一個論壇話題。';
  @override
  String systemPromptTopicTitle(String title) => '話題標題：$title';
  @override
  String get systemPromptContextHint =>
      '用戶可能會就話題內容向你提問，請基於提供的上下文回答。';
  @override
  String get systemPromptMarkdown => '請用 Markdown 格式回覆。';
  @override
  String contextContentPrefix(String text) => '以下是話題內容：\n$text';
  @override
  String get contextReadyResponse => '好的，我已經閱讀了話題內容。請問你有什麼問題？';
  @override
  String get titleGenerationPrompt =>
      '請用不超過15個字概括用戶這段話的主題，直接輸出標題文字，不要加標點符號和引號。';
}

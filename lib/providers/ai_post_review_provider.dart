import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_post_review_service.dart';
import 'core_providers.dart';
import 'theme_provider.dart';

final aiPostReviewSelectedModelProvider =
    Provider<({AiProvider provider, AiModel model})?>((ref) {
      return ref.watch(defaultAiModelProvider);
    });

final aiPostReviewServiceProvider = Provider<AiPostReviewService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final chatService = ref.watch(aiChatServiceProvider);
  final discourseService = ref.watch(discourseServiceProvider);
  return AiPostReviewService(
    prefs: prefs,
    chatService: chatService,
    dio: discourseService.dio,
    apiKeyLoader: AiProviderListNotifier.getApiKey,
  );
});

// ignore_for_file: avoid_classes_with_only_static_members

// Desktop/Web stub for llm_llamacpp.
// On Windows/Linux/macOS the _queryNative path is never taken
// (guarded by Platform.isAndroid || Platform.isIOS in on_device_llm_service.dart),
// so these classes only need to compile — they are never instantiated.

class LlamaCppRepository {
  Future<void> loadModel(String path) async {}
  void dispose() {}
}

class LlamaCppChatRepository {
  LlamaCppChatRepository({
    int? contextSize,
    int? threads,
    int? nGpuLayers,
  });

  Future<LlamaCppResponse> chatResponse(
    String modelPath, {
    required List<LLMMessage> messages,
    LLMChatOptions? options,
  }) async {
    return LlamaCppResponse(content: null);
  }

  void dispose() {}
}

class LlamaCppResponse {
  final String? content;
  LlamaCppResponse({this.content});
}

enum LLMRole { system, user, assistant }

class LLMMessage {
  final LLMRole role;
  final String content;
  const LLMMessage({required this.role, required this.content});
}

class LLMChatOptions {
  final int? maxOutputTokens;
  final double? temperature;
  final double? topP;
  final Map<String, dynamic>? backendOptions;
  const LLMChatOptions({
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.backendOptions,
  });
}

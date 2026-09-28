/// Mobile implementation: calls the real llm_llamacpp package for in-process
/// Qwen3 inference on Android / iOS.
library;

import 'package:llm_llamacpp/llm_llamacpp.dart';

LlamaCppChatRepository? _mobileRepo;
String? _loadedModelPath;

/// Run a single-turn chat against the on-device model.
/// Manages model loading with a lazy singleton (loads once, reuses).
Future<String> nativeInfer({
  required String modelPath,
  required String systemPrompt,
  required String question,
}) async {
  if (_loadedModelPath != modelPath || _mobileRepo == null) {
    _mobileRepo?.dispose();
    // Use withModelPath: this delegates model loading directly to the background
    // inference isolate where llama.cpp's dynamic backends (libggml-cpu, etc.)
    // are correctly resolved from the Android native library directory.
    _mobileRepo = LlamaCppChatRepository.withModelPath(
      modelPath,
      contextSize: 1024, // ~400 MB KV-cache on mobile
      threads: null,     // auto-detect CPU cores
      nGpuLayers: 0,     // 0 ensures 100% stable CPU execution on all Android devices
    );
    _loadedModelPath = modelPath;
  }

  final response = await _mobileRepo!.chatResponse(
    modelPath,
    messages: [
      LLMMessage(role: LLMRole.system, content: systemPrompt),
      LLMMessage(role: LLMRole.user, content: question),
    ],
    options: const LLMChatOptions(
      maxOutputTokens: 350,
      temperature: 0.7,
      topP: 0.9,
      backendOptions: {'repeat_penalty': 1.1},
    ),
  );

  final content = response.content?.trim() ?? '';
  if (content.isEmpty) throw Exception('Empty response from Qwen3 model');
  return content;
}

/// Dispose the loaded model — called on error to force a reload on the next query.
void nativeDispose() {
  _mobileRepo?.dispose();
  _mobileRepo = null;
  _loadedModelPath = null;
}

/// Stub plugin class — no platform channel needed; all logic is pure Dart FFI.
/// The [registerWith] static method is required by Flutter's plugin registrant.
class LlmMobilePlugin {
  /// Called by Flutter's generated plugin registrant on Android/iOS.
  /// No-op: llm_llamacpp uses Dart FFI directly, no MethodChannel to register.
  static void registerWith() {}
}


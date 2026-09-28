/// Desktop/web stub for llm_native_mobile.dart
/// These functions are never called at runtime (guarded by Platform.isAndroid || Platform.isIOS),
/// but must exist so that Windows / Linux / macOS / web builds compile.
library;

Future<String> nativeInfer({
  required String modelPath,
  required String systemPrompt,
  required String question,
}) async {
  throw UnsupportedError('nativeInfer is only available on Android/iOS');
}

void nativeDispose() {}

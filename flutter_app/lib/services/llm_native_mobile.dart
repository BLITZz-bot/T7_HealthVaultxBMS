/// Mobile shim — re-exports nativeInfer / nativeDispose from the llm_mobile plugin.
/// Conditionally imported by on_device_llm_service.dart on Android/iOS only.
library;

export 'package:llm_mobile/llm_mobile.dart' show nativeInfer, nativeDispose;

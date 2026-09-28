/// Application-wide constants & clinical configuration
class AppConstants {
  // App Identity
  static const String appName = 'T7 HealthVault';
  static const String appVersion = '1.2.0';
  static const String buildNumber = '12';

  // AI & LLM Engine
  static const String llmModelFileName = 'Qwen3-1.7B-Q4_K_M.gguf';
  static const String llmModelDownloadUrl =
      'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf';
  static const int llmEstimatedSizeBytes = 1107409472; // ~1.05 GB (1,107,409,472 bytes)

  // Database
  static const String dbName = 'asha_records.db';
  static const int dbVersion = 3;

  // Clinical Thresholds (NEWS2 & Sepsis)
  static const int news2LowRiskMax = 4;
  static const int news2MediumRiskMax = 6;
  static const int news2HighRiskMin = 7;

  // Storage Keys
  static const String keyAppLanguage = 'selected_language';
  static const String keyAdminToken = 'admin_jwt_token';
  static const String keyLastSyncTimestamp = 'last_sync_time';
}

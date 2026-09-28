import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
// llm_llamacpp is a mobile-only native FFI package (Android/iOS).
// Two-file shim: Windows/Linux/macOS uses the no-op stub; Android/iOS uses the real implementation.
import 'llm_native_stub.dart'
    if (dart.library.io) 'llm_native_mobile.dart';

import 'language_service.dart';
import '../widgets/qwen_ai_chat_modal.dart';


/// On-Device LLM & Multilingual Clinical Intelligence Service for T7 Clinical AI
/// Supports 22 Scheduled Indian Languages + English with open-ended dynamic clinical reasoning.
class OnDeviceLLMService {
  // ── Model: Qwen3-1.7B Q4_K_M (unsloth, imatrix-calibrated, ~1.28 GB)
  static const String modelFileName = 'Qwen3-1.7B-Q4_K_M.gguf';
  static const String modelDownloadUrl =
      'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf';

  static const int estimatedSizeBytes = 1107409472; // ~1.05 GB exact

  static final ValueNotifier<bool> isModelDownloadedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isDownloadingNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isPausedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<double> downloadProgressNotifier = ValueNotifier<double>(0.0);
  static final ValueNotifier<String> downloadStatusNotifier = ValueNotifier<String>('');
  static final ValueNotifier<int> bytesDownloadedNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> totalBytesNotifier = ValueNotifier<int>(estimatedSizeBytes);

  static bool _initialized = false;
  static HttpClient? _activeHttpClient;
  static bool _isPausedRequested = false;
  static bool _isCancelledRequested = false;

  /// Check if model exists locally on startup, or if a resumable partial download exists
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final targetFile = await getModelFile();
      final tempFile = File('${targetFile.path}.tmp');

      if (await targetFile.exists()) {
        final length = await targetFile.length();
        if (length > 500 * 1024 * 1024) {
          isModelDownloadedNotifier.value = true;
          isDownloadingNotifier.value = false;
          isPausedNotifier.value = false;
          downloadProgressNotifier.value = 1.0;
          bytesDownloadedNotifier.value = length;
          totalBytesNotifier.value = length;
          final mb = (length / (1024 * 1024)).toStringAsFixed(1);
          downloadStatusNotifier.value = 'T7 Clinical AI Ready ($mb MB On-Device)';
          _initialized = true;
          return;
        }
      }

      // Check for resumable partial download from previous session
      if (await tempFile.exists()) {
        final partialBytes = await tempFile.length();
        if (partialBytes > 0) {
          isModelDownloadedNotifier.value = false;
          isDownloadingNotifier.value = false;
          isPausedNotifier.value = true;
          bytesDownloadedNotifier.value = partialBytes;
          totalBytesNotifier.value = estimatedSizeBytes;
          final progress = (partialBytes / estimatedSizeBytes).clamp(0.0, 1.0);
          downloadProgressNotifier.value = progress;
          final mb = (partialBytes / (1024 * 1024)).toStringAsFixed(1);
          final totalMb = (estimatedSizeBytes / (1024 * 1024)).toStringAsFixed(1);
          downloadStatusNotifier.value = 'Download Paused ($mb / $totalMb MB • ${(progress * 100).toStringAsFixed(1)}%) • Tap Resume to Continue';
          _initialized = true;
          return;
        }
      }

      isModelDownloadedNotifier.value = false;
      isDownloadingNotifier.value = false;
      isPausedNotifier.value = false;
      downloadProgressNotifier.value = 0.0;
      bytesDownloadedNotifier.value = 0;
      downloadStatusNotifier.value = 'Ready (Built-in Clinical AI Active) • Optional GGUF Model (~1.05 GB)';
    } catch (e) {
      isModelDownloadedNotifier.value = false;
      downloadStatusNotifier.value = 'Ready: Built-in Clinical Intelligence Active';
    }
    _initialized = true;
  }

  /// Get File handle for local GGUF model
  static Future<File> getModelFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${dir.path}/models');
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }
    return File('${modelsDir.path}/$modelFileName');
  }

  /// Check exact model size on disk
  static Future<int> getLocalModelSize() async {
    try {
      final file = await getModelFile();
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Pause an ongoing download (preserves all downloaded bytes for resuming)
  static void pauseDownload() {
    _isPausedRequested = true;
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    isDownloadingNotifier.value = false;
    isPausedNotifier.value = true;

    final downloaded = bytesDownloadedNotifier.value;
    final total = totalBytesNotifier.value > 0 ? totalBytesNotifier.value : estimatedSizeBytes;
    final mb = (downloaded / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
    final pct = (downloaded / total * 100).clamp(0.0, 100.0).toStringAsFixed(1);
    downloadStatusNotifier.value = 'Download Paused ($mb / $totalMb MB • $pct%) • Ready to Resume';
  }

  /// Download or Resume GGUF Model weights with HTTP Range support, pause/continue, speed, and ETA
  static Future<bool> downloadModel({Function(double progress, String status)? onProgress}) async {
    if (isDownloadingNotifier.value) return false;
    isDownloadingNotifier.value = true;
    isPausedNotifier.value = false;
    _isPausedRequested = false;
    _isCancelledRequested = false;

    IOSink? sink;
    File? tempFile;

    try {
      final targetFile = await getModelFile();
      tempFile = File('${targetFile.path}.tmp');

      int existingBytes = 0;
      if (await tempFile.exists()) {
        existingBytes = await tempFile.length();
      }

      bytesDownloadedNotifier.value = existingBytes;
      final resumePercent = (existingBytes / estimatedSizeBytes * 100).clamp(0.0, 100.0).toStringAsFixed(1);
      downloadStatusNotifier.value = existingBytes > 0
          ? 'Resuming from ${(existingBytes / (1024 * 1024)).toStringAsFixed(1)} MB ($resumePercent%)...'
          : 'Connecting to HuggingFace repository...';

      _activeHttpClient = HttpClient();
      _activeHttpClient!.connectionTimeout = const Duration(seconds: 25);

      Uri currentUri = Uri.parse(modelDownloadUrl);
      HttpClientResponse? response;

      // Handle redirect manually to preserve HTTP Range headers
      for (int redirectCount = 0; redirectCount < 5; redirectCount++) {
        if (_isPausedRequested || _isCancelledRequested) break;

        final request = await _activeHttpClient!.getUrl(currentUri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'T7-HealthVault-Mobile/1.0');

        if (existingBytes > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
        }

        response = await request.close();

        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null && location.isNotEmpty) {
            currentUri = Uri.parse(location);
            continue;
          }
        }
        break;
      }

      if (response == null) {
        throw Exception('Unable to establish connection with model repository.');
      }

      final statusCode = response.statusCode;
      if (statusCode != HttpStatus.ok && statusCode != HttpStatus.partialContent) {
        throw Exception('Server returned HTTP $statusCode');
      }

      // Determine total content length
      int totalBytes = estimatedSizeBytes;
      if (statusCode == HttpStatus.partialContent) {
        final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
        if (contentRange != null && contentRange.contains('/')) {
          final totalStr = contentRange.split('/').last.trim();
          totalBytes = int.tryParse(totalStr) ?? (existingBytes + response.contentLength);
        } else {
          totalBytes = existingBytes + response.contentLength;
        }
        sink = tempFile.openWrite(mode: FileMode.append);
      } else {
        // Full content from 0 (if server didn't support Range)
        existingBytes = 0;
        totalBytes = response.contentLength > 0 ? response.contentLength : estimatedSizeBytes;
        sink = tempFile.openWrite(mode: FileMode.write);
      }

      totalBytesNotifier.value = totalBytes;
      int currentBytesDownloaded = existingBytes;

      final startTime = DateTime.now();
      var lastNotifyTime = DateTime.now();
      int sessionBytesDownloaded = 0;

      await for (final chunk in response) {
        if (_isPausedRequested) {
          if (sink != null) {
            await sink.flush();
            await sink.close();
            sink = null;
          }
          isDownloadingNotifier.value = false;
          isPausedNotifier.value = true;
          final mb = (currentBytesDownloaded / (1024 * 1024)).toStringAsFixed(1);
          final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          final pct = (currentBytesDownloaded / totalBytes * 100).clamp(0.0, 100.0).toStringAsFixed(1);
          downloadStatusNotifier.value = 'Download Paused ($mb / $totalMb MB • $pct%) • Ready to Resume';
          _activeHttpClient?.close(force: true);
          _activeHttpClient = null;
          return false;
        }

        if (_isCancelledRequested) {
          throw Exception('Download cancelled by user.');
        }

        currentBytesDownloaded += chunk.length;
        sessionBytesDownloaded += chunk.length;
        sink?.add(chunk);
        bytesDownloadedNotifier.value = currentBytesDownloaded;

        final now = DateTime.now();
        if (now.difference(lastNotifyTime).inMilliseconds >= 100 || currentBytesDownloaded >= totalBytes) {
          lastNotifyTime = now;
          final progress = (currentBytesDownloaded / totalBytes).clamp(0.0, 1.0);
          downloadProgressNotifier.value = progress;

          final elapsedSeconds = now.difference(startTime).inMilliseconds / 1000.0;
          final speedBytesPerSec = elapsedSeconds > 0 ? (sessionBytesDownloaded / elapsedSeconds) : 0.0;
          final speedMbps = (speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1);

          final mbDownloaded = (currentBytesDownloaded / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

          final remainingBytes = totalBytes - currentBytesDownloaded;
          final etaSeconds = speedBytesPerSec > 0 ? (remainingBytes / speedBytesPerSec).round() : 0;
          final etaStr = etaSeconds > 60 ? '${(etaSeconds / 60).toStringAsFixed(1)} min' : '${etaSeconds}s';

          final statusStr = '$mbDownloaded / $mbTotal MB (${(progress * 100).toStringAsFixed(1)}%) • $speedMbps MB/s • ETA: $etaStr';
          downloadStatusNotifier.value = statusStr;

          if (onProgress != null) {
            onProgress(progress, statusStr);
          }
        }
      }

      if (sink != null) {
        await sink.flush();
        await sink.close();
        sink = null;
      }

      if (_isPausedRequested) {
        return false;
      }

      // Rename temp file to final target
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      isModelDownloadedNotifier.value = true;
      isDownloadingNotifier.value = false;
      isPausedNotifier.value = false;
      downloadProgressNotifier.value = 1.0;
      final finalMb = (currentBytesDownloaded / (1024 * 1024)).toStringAsFixed(1);
      downloadStatusNotifier.value = 'T7 Clinical AI Ready ($finalMb MB On-Device)';
      _activeHttpClient = null;
      return true;
    } catch (e) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      isDownloadingNotifier.value = false;
      _activeHttpClient = null;

      if (_isPausedRequested) {
        isPausedNotifier.value = true;
        return false;
      }

      if (_isCancelledRequested) {
        if (tempFile != null && await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
        isPausedNotifier.value = false;
        downloadProgressNotifier.value = 0.0;
        bytesDownloadedNotifier.value = 0;
        downloadStatusNotifier.value = 'Download cancelled & cleared.';
      } else {
        // If network error occurred, keep bytes in tempFile so user can resume without losing data!
        isPausedNotifier.value = true;
        downloadStatusNotifier.value = 'Connection paused / interrupted. Tap Resume to continue.';
      }
      return false;
    }
  }

  /// Delete local GGUF model and any temporary partial download file to free storage completely
  static Future<void> deleteModel() async {
    _isCancelledRequested = true;
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;

    final targetFile = await getModelFile();
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    final tempFile = File('${targetFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    isModelDownloadedNotifier.value = false;
    isDownloadingNotifier.value = false;
    isPausedNotifier.value = false;
    downloadProgressNotifier.value = 0.0;
    bytesDownloadedNotifier.value = 0;
    downloadStatusNotifier.value = 'Model & cache deleted • Built-in AI Active';
  }

  /// Unified Professional-Grade Model Management Dialog (used across Home, Member Detail, and Chat)
  static void showModelManagementDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return ValueListenableBuilder<bool>(
              valueListenable: isDownloadingNotifier,
              builder: (context, isDownloading, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: isPausedNotifier,
                  builder: (context, isPaused, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: isModelDownloadedNotifier,
                      builder: (context, isDownloaded, _) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: Row(
                            children: [
                              Icon(
                                isDownloaded
                                    ? Icons.verified_rounded
                                    : (isDownloading
                                        ? Icons.downloading_rounded
                                        : (isPaused ? Icons.pause_circle_filled : Icons.download_for_offline)),
                                color: isDownloaded
                                    ? const Color(0xFF00796B)
                                    : (isPaused ? Colors.orange.shade800 : const Color(0xFF00796B)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isDownloaded
                                      ? 'T7 On-Device Clinical AI'
                                      : (isPaused
                                          ? 'Resume Model Download'
                                          : (isDownloading ? 'Downloading AI Weights' : 'T7 Clinical AI Model')),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isDownloaded) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle, color: Colors.green, size: 28),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: const [
                                              Text(
                                                'GGUF Neural Model Active (~1.05 GB)',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                '100% Offline neural weights are installed and active on this device.',
                                                style: TextStyle(fontSize: 11, color: Colors.black87),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (isDownloading || isPaused) ...[
                                  Text(
                                    isPaused
                                        ? 'Download paused. You can resume at any time from this exact point:'
                                        : 'Downloading quantized neural weights from HuggingFace:',
                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 12),
                                  ValueListenableBuilder<double>(
                                    valueListenable: downloadProgressNotifier,
                                    builder: (context, progress, _) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: LinearProgressIndicator(
                                              value: progress > 0 ? progress : null,
                                              minHeight: 10,
                                              backgroundColor: Colors.grey.shade200,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                isPaused ? Colors.orange.shade700 : const Color(0xFF00796B),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ValueListenableBuilder<String>(
                                            valueListenable: downloadStatusNotifier,
                                            builder: (context, status, _) {
                                              return Text(
                                                status,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: isPaused ? Colors.orange.shade900 : const Color(0xFF004D40),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ] else ...[
                                  const Text(
                                    'Download the optional 1.05 GB Qwen3-1.7B (Q4_K_M) neural model weights for enhanced offline generative reasoning. The built-in expert engine is already active and responsive!',
                                    style: TextStyle(fontSize: 12, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: const [
                                        Icon(Icons.info_outline, color: Colors.blue, size: 18),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Downloads can be paused and resumed at any time, even after restarting the app.',
                                            style: TextStyle(fontSize: 11, color: Colors.black87),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          actions: [
                            if (isDownloading) ...[
                              TextButton(
                                onPressed: () async {
                                  await deleteModel();
                                  setModalState(() {});
                                },
                                child: const Text('Cancel & Clear', style: TextStyle(color: Colors.red)),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade600,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.pause_rounded, size: 16),
                                label: const Text('Pause'),
                                onPressed: () {
                                  pauseDownload();
                                  setModalState(() {});
                                },
                              ),
                            ] else if (isPaused) ...[
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text('Clear Progress'),
                                onPressed: () async {
                                  await deleteModel();
                                  setModalState(() {});
                                },
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00796B),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                label: const Text('Resume Download'),
                                onPressed: () async {
                                  setModalState(() {});
                                  final success = await downloadModel();
                                  if (ctx.mounted) {
                                    setModalState(() {});
                                    if (success) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('T7 Clinical AI Model downloaded successfully!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ] else if (isDownloaded) ...[
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text('Delete Model (~1.05 GB)'),
                                onPressed: () async {
                                  await deleteModel();
                                  if (context.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Model deleted. Built-in engine remains active!')),
                                    );
                                  }
                                },
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00796B),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                                label: const Text('Open AI Chat'),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  QwenAIChatModal.show(context);
                                },
                              ),
                            ] else ...[
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(LanguageService.tr('cancel')),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00796B),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.download, size: 16),
                                label: Text(LanguageService.tr('start_download', defaultText: 'Start Download (~1.05 GB)')),
                                onPressed: () async {
                                  setModalState(() {});
                                  final success = await downloadModel();
                                  if (ctx.mounted) {
                                    setModalState(() {});
                                    if (success) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('T7 Clinical AI Model downloaded successfully!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  static Process? _serverProcess;
  static bool _isStartingServer = false;
  static int serverPort = 8088;

  /// Stop background local llama-server if running
  static void stopServer() {
    _serverProcess?.kill();
    _serverProcess = null;
  }

  /// Check if local inference server is responding
  static Future<bool> isServerAlive() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$serverPort/health'));
      final resp = await req.close();
      client.close();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Locate llama-server.exe binary on desktop
  static Future<File?> findLlamaServerBinary() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return null;

    final docDir = await getApplicationDocumentsDirectory();
    final candidates = [
      File('${docDir.path}/models/bin/llama-server.exe'),
      File('d:/Projects Working in Progress/T7_HealthVault/llama_bin/llama-server.exe'),
      File('${Directory.current.path}/../llama_bin/llama-server.exe'),
      File('${Directory.current.path}/llama_bin/llama-server.exe'),
    ];

    for (final f in candidates) {
      if (await f.exists()) return f;
    }
    return null;
  }

  /// Start local llama-server in background if not already running
  static Future<bool> ensureServerRunning() async {
    if (await isServerAlive()) return true;
    if (_isStartingServer) {
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (await isServerAlive()) return true;
      }
      return false;
    }

    _isStartingServer = true;
    try {
      final modelFile = await getModelFile();
      if (!await modelFile.exists()) {
        _isStartingServer = false;
        return false;
      }

      final serverBin = await findLlamaServerBinary();
      if (serverBin == null) {
        _isStartingServer = false;
        return false;
      }

      // Start background process
      _serverProcess = await Process.start(
        serverBin.path,
        [
          '-m', modelFile.path,
          '--port', '$serverPort',
          '-c', '2048',
          '--threads', '4',
        ],
        mode: ProcessStartMode.detached,
      );

      // Poll until ready (give up to 15 seconds)
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (await isServerAlive()) {
          _isStartingServer = false;
          return true;
        }
      }
    } catch (_) {}

    _isStartingServer = false;
    return await isServerAlive();
  }

  /// Query Qwen3-1.7B on-device — native FFI on mobile, llama-server on desktop
  static Future<String> queryRealModel({
    required String question,
    required String languageCode,
    required Map<String, dynamic> member,
    required dynamic news2Score,
    required dynamic sepsisScore,
    required String sepsisLevel,
  }) async {
    final patientName = member['name'] ?? member['full_name'] ?? 'Community Member';
    final age = member['age'] ?? 'N/A';
    final isGeneralQuery = patientName == 'General Health Query' || member['id'] == null;
    final langInfo = LanguageService.getLanguageInfo(languageCode);
    final langName = langInfo['name'] ?? 'English';
    final gender = member['gender'] ?? 'N/A';
    final isPreg = member['is_pregnant'] == 1 || member['is_pregnant'] == true;

    final systemPrompt = '''You are T7 Clinical AI, a professional medical decision support assistant for ASHA community health workers in India.
Follow WHO, Indian Ministry of Health (MoHFW), and IMNCI clinical guidelines.
Patient Profile:
- Name: $patientName (Age: $age, Gender: $gender, Pregnant: $isPreg)
- Current NEWS2 Early Warning Score: $news2Score
- PhysioNet Sepsis Probability: $sepsisScore ($sepsisLevel)

Clinical Instructions:
1. Provide concise, clear, and actionable clinical advice.
2. Highlight any danger signs/red flags that require immediate PHC transfer.
3. Recommend safe initial supportive care or triage advice.
4. Respond in $langName ($languageCode).''';

    // ── Mobile path: native in-process llama.cpp via llm_llamacpp FFI ──────────
    if (Platform.isAndroid || Platform.isIOS) {
      return _queryNative(
        systemPrompt: systemPrompt,
        question: question,
        languageCode: languageCode,
        patientName: patientName.toString(),
        age: age,
        isGeneralQuery: isGeneralQuery,
        news2Score: news2Score,
        sepsisScore: sepsisScore,
        sepsisLevel: sepsisLevel,
      );
    }

    // ── Desktop path: llama-server HTTP ─────────────────────────────────────
    final serverReady = await ensureServerRunning();
    if (!serverReady) {
      final modelFile = await getModelFile();
      if (!await modelFile.exists()) {
        return _getModelNotLoadedMessage(languageCode);
      }
      return '⚠️ On-device neural server is initializing or unavailable. Please verify the local llama-server process and retry.';
    }

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 45);
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$serverPort/v1/chat/completions'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

      final body = jsonEncode({
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': question},
        ],
        'max_tokens': 350,
        'temperature': 0.7,
      });

      req.add(utf8.encode(body));
      final resp = await req.close();
      final respBody = await utf8.decodeStream(resp);
      client.close();

      if (resp.statusCode == 200) {
        final data = jsonDecode(respBody) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']?['content']?.toString().trim();
          if (content != null && content.isNotEmpty) {
            return content;
          }
        }
      }
      return '⚠️ The on-device neural model returned an empty response. Please retry.';
    } catch (e) {
      return '⚠️ Could not connect to on-device neural model server: $e';
    }
  }

  /// Native in-process inference via llm_llamacpp (Android/iOS).
  /// Delegates to nativeInfer() / nativeDispose() from the conditional shim so
  /// Windows / Linux / macOS builds never touch any llm_llamacpp native code.
  static Future<String> _queryNative({
    required String systemPrompt,
    required String question,
    required String languageCode,
    required String patientName,
    required dynamic age,
    required bool isGeneralQuery,
    required dynamic news2Score,
    required dynamic sepsisScore,
    required String sepsisLevel,
  }) async {
    final modelFile = await getModelFile();
    if (!await modelFile.exists()) {
      return _getModelNotLoadedMessage(languageCode);
    }

    try {
      return await nativeInfer(
        modelPath: modelFile.path,
        systemPrompt: systemPrompt,
        question: question,
      );
    } catch (e) {
      nativeDispose(); // reset on error so next call retries loading
      return '⚠️ On-device neural inference error ($e). Please retry.';
    }
  }


  /// Generate Generative Clinical Explanation using T7 Clinical AI
  static Future<String> generateGenerativeClinicalExplanation({
    required Map<String, dynamic> member,
    required Map<String, dynamic> news2Result,
    required Map<String, dynamic> sepsisResult,
    required Map<String, Map<String, dynamic>> delta,
    required String languageCode,
    String? customQuestion,
  }) async {
    final news2Score = news2Result['score'] ?? 0;
    final sepsisScore = sepsisResult['risk_percent'] ?? '0%';
    final sepsisLevel = sepsisResult['risk_level'] ?? 'Normal / Low Risk';

    if (customQuestion != null && customQuestion.trim().isNotEmpty) {
      return queryRealModel(
        question: customQuestion.trim(),
        languageCode: languageCode,
        member: member,
        news2Score: news2Score,
        sepsisScore: sepsisScore,
        sepsisLevel: sepsisLevel,
      );
    }

    // Default Clinical Summary Card
    return LanguageService.generateClinicalExplanation(
      member: member,
      news2Result: {'score': news2Score, 'risk_level': sepsisLevel, 'action': 'Monitor patient vitals regularly.'},
      sepsisResult: {'risk_percent': sepsisScore, 'risk_level': sepsisLevel},
      delta: delta,
      languageCode: languageCode,
    );
  }

  /// Clean prompt shown when on-device GGUF neural weights have not yet been downloaded
  static String _getModelNotLoadedMessage(String languageCode) {
    if (languageCode == 'hi') {
      return '⚠️ ऑन-डिवाइस न्यूरल AI मॉडल (~1.05 GB) अभी डाउनलोड नहीं हुआ है।\n\n'
          'पूर्ण ऑफलाइन AI सक्रिय करने के लिए कृपया होम स्क्रीन पर दिए गए "Download" बटन पर टैप करें।';
    } else if (languageCode == 'kn') {
      return '⚠️ ಆನ್-ಡಿವೈಸ್ ನ್ಯೂರಲ್ AI ಮಾದರಿ (~1.05 GB) ಇನ್ನೂ ಡೌನ್‌ಲೋಡ್ ಆಗಿಲ್ಲ.\n\n'
          'ಸಂಪೂರ್ಣ ಆಫ್‌ಲೈನ್ AI ಸಕ್ರಿಯಗೊಳಿಸಲು ದಯವಿಟ್ಟು ಮುಖಪುಟದಲ್ಲಿರುವ "Download" ಬಟನ್ ಟ್ಯಾಪ್ ಮಾಡಿ.';
    } else if (languageCode == 'te') {
      return '⚠️ ఆన్-డివైస్ న్యూరల్ AI మోడల్ (~1.05 GB) ఇంకా డౌన్‌లోడ్ కాలేదు.\n\n'
          'ఆఫ్‌లైన్ AIని ప్రారంభించడానికి హోమ్ స్క్రీన్‌పై "Download" బటన్‌ను నొక్కండి.';
    } else if (languageCode == 'ta') {
      return '⚠️ ஆன்-டிவைஸ் நியூரல் AI மாடல் (~1.05 GB) இன்னும் பதிவிறக்கப்படவில்லை.\n\n'
          'ஆஃப்லைன் AI ஐ இயக்க முகப்புத் திரையில் உள்ள "Download" பொத்தானைத் தட்டவும்.';
    }

    return '⚠️ On-Device Qwen3-1.7B Neural Model (~1.05 GB) is not loaded.\n\n'
        'To enable real, open-ended clinical AI reasoning without internet, please tap "Download" on the Home Screen to install the offline neural weights.';
  }
}

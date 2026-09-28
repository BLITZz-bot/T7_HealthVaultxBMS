import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/on_device_llm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  group('T7 Clinical AI Chatbot - Zero Hardcoding Tests', () {
    final mockMember = {
      'id': 1,
      'name': 'Abhishek',
      'full_name': 'Abhishek',
      'age': 21,
      'gender': 'Male',
      'is_pregnant': 0,
    };
    final mockNews2 = {'score': 0, 'risk_level': 'Normal / Low Risk'};
    final mockSepsis = {'risk_percent': '0%', 'risk_level': 'Normal / Low Risk'};

    test('Never returns hardcoded canned clinical ladders for queries', () async {
      final response = await OnDeviceLLMService.generateGenerativeClinicalExplanation(
        member: mockMember,
        news2Result: mockNews2,
        sepsisResult: mockSepsis,
        delta: {},
        languageCode: 'en',
        customQuestion: 'cnscbc\\',
      );

      // Must never return fake hardcoded templates
      expect(response.contains('Community Health Guidance for: "cnscbc'), isFalse);
      expect(response.contains('Action Protocol:'), isFalse);
      expect(response.contains('Red Flags & Danger Signs:'), isFalse);
    });

    test('Prompts user clearly when offline weights are not yet downloaded', () async {
      final response = await OnDeviceLLMService.generateGenerativeClinicalExplanation(
        member: mockMember,
        news2Result: mockNews2,
        sepsisResult: mockSepsis,
        delta: {},
        languageCode: 'en',
        customQuestion: 'What should I do for high fever?',
      );

      // In environment without downloaded GGUF, informs user to install model
      expect(response.contains('Qwen3-1.7B') || response.contains('neural model'), isTrue);
    });
  });
}

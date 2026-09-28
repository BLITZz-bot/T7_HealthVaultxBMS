import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart';
import 'package:flutter_app/services/app_update_service.dart';

void main() {
  group('AppUpdateService Version Tests', () {
    test('parseVersionSegments parses clean versions and prefixes/suffixes', () {
      expect(AppUpdateService.parseVersionSegments('v1.0.1'), equals([1, 0, 1]));
      expect(AppUpdateService.parseVersionSegments('V2.3.4'), equals([2, 3, 4]));
      expect(AppUpdateService.parseVersionSegments('1.0.0+1'), equals([1, 0, 0]));
      expect(AppUpdateService.parseVersionSegments('1.0.1-beta.1'), equals([1, 0, 1]));
      expect(AppUpdateService.parseVersionSegments('1.2'), equals([1, 2]));
    });

    test('isNewerVersion correctly compares versions', () {
      // Newer versions
      expect(AppUpdateService.isNewerVersion('v1.0.1', '1.0.0'), isTrue);
      expect(AppUpdateService.isNewerVersion('v1.0.2', '1.0.1'), isTrue);
      expect(AppUpdateService.isNewerVersion('v1.1.0', '1.0.9'), isTrue);
      expect(AppUpdateService.isNewerVersion('v2.0.0', '1.9.9'), isTrue);
      expect(AppUpdateService.isNewerVersion('1.0.1', '1.0.0+1'), isTrue);

      // Same versions (no update needed)
      expect(AppUpdateService.isNewerVersion('v1.0.1', '1.0.1'), isFalse);
      expect(AppUpdateService.isNewerVersion('v1.0.0', '1.0.0'), isFalse);
      expect(AppUpdateService.isNewerVersion('v1.0.1', '1.0.1+1'), isFalse);
      expect(AppUpdateService.isNewerVersion('1.0.1', 'v1.0.1'), isFalse);

      // Older versions (no update needed)
      expect(AppUpdateService.isNewerVersion('v1.0.0', '1.0.1'), isFalse);
      expect(AppUpdateService.isNewerVersion('v1.0.1', '1.0.2'), isFalse);
      expect(AppUpdateService.isNewerVersion('v0.9.9', '1.0.0'), isFalse);
    });
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HealthVaultApp(showFirstRunLanguageSetup: false));
    expect(find.text('T7 HealthVault'), findsOneWidget);
  });
}


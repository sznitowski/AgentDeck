import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Codemagic CI/CD Configuration Validation', () {
    final codemagicFile = File('codemagic.yaml');
    final ciScript = File('tool/ci_verify.sh');
    final preCiScript = File('tool/pre_ci_check.ps1');

    test('codemagic.yaml exists and contains valid structure', () {
      expect(codemagicFile.existsSync(), isTrue,
          reason: 'codemagic.yaml must exist in root');
      final content = codemagicFile.readAsStringSync();
      final lines = content.split('\n');

      // 1. Root structure
      expect(content.contains('workflows:'), isTrue);

      // 2. Workflow 1: ios-unsigned-validation is present and configured
      expect(content.contains('ios-unsigned-validation:'), isTrue);
      expect(content.contains('flutter: 3.47.5'), isTrue);
      expect(content.contains('mac_mini_m2'), isTrue);
      expect(content.contains('bash tool/ci_verify.sh'), isTrue);
      expect(
          content.contains('flutter build ios --debug --no-codesign'), isTrue);

      // 3. ios-unsigned-validation does NOT require or reference Apple credentials
      final unsignedWorkflowChunk = content.substring(
        content.indexOf('ios-unsigned-validation:'),
        content.indexOf('ios-testflight:'),
      );
      expect(unsignedWorkflowChunk.contains('app_store_credentials'), isFalse,
          reason: 'unsigned workflow must not require apple credential groups');
      expect(unsignedWorkflowChunk.contains('app_store_connect'), isFalse,
          reason: 'unsigned workflow must not require app store connect');
      expect(unsignedWorkflowChunk.contains('keychain initialize'), isFalse,
          reason: 'unsigned workflow must not initialize signing keychain');

      // 4. Workflow 2: ios-testflight exists as scaffold
      expect(content.contains('ios-testflight:'), isTrue);
      expect(content.contains('com.agentdeck.app'), isTrue);

      // 5. ios-testflight does NOT have active publishing that causes Codemagic validation errors
      // Lines under ios-testflight must not contain uncommented `auth: integration` or active `publishing:`
      final testflightChunk =
          content.substring(content.indexOf('ios-testflight:'));
      final activePublishingLines = testflightChunk.split('\n').where((l) {
        final trimmed = l.trim();
        return !trimmed.startsWith('#') &&
            (trimmed == 'publishing:' || trimmed.startsWith('auth:'));
      }).toList();
      expect(activePublishingLines, isEmpty,
          reason:
              'ios-testflight must not contain active publishing without real integration');

      // 6. Ensure lines have no illegal tabs (strict YAML compliance)
      for (var i = 0; i < lines.length; i++) {
        expect(lines[i].contains('\t'), isFalse,
            reason:
                'Line ${i + 1} contains tab character which is invalid in YAML');
      }
    });

    test('CI helper scripts exist and are well-formed', () {
      expect(ciScript.existsSync(), isTrue);
      final ciContent = ciScript.readAsStringSync();
      expect(ciContent.contains('flutter pub get'), isTrue);
      expect(ciContent.contains('flutter analyze'), isTrue);
      expect(ciContent.contains('flutter test'), isTrue);
      expect(ciContent.contains('python3 -B -m unittest'), isTrue);
      expect(ciContent.contains('tool/push_lab.dart'), isTrue);

      expect(preCiScript.existsSync(), isTrue);
      final preCiContent = preCiScript.readAsStringSync();
      expect(preCiContent.contains('pub get'), isTrue);
      expect(preCiContent.contains('analyze'), isTrue);
      expect(preCiContent.contains('test'), isTrue);
      expect(preCiContent.contains('push_lab.dart'), isTrue);
    });
  });
}

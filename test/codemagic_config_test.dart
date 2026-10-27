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

      expect(content.contains('workflows:'), isTrue);
      expect(content.contains('ios-unsigned-validation:'), isTrue);
      expect(content.contains('ios-testflight:'), isTrue);
      expect(content.contains('flutter: 3.47.5'), isTrue);
      expect(content.contains('mac_mini_m2'), isTrue);
      expect(content.contains('bash tool/ci_verify.sh'), isTrue);
      expect(
          content.contains('flutter build ios --debug --no-codesign'), isTrue);
      expect(content.contains('com.agentdeck.app'), isTrue);
    });

    test('CI helper scripts exist and are well-formed', () {
      expect(ciScript.existsSync(), isTrue);
      final ciContent = ciScript.readAsStringSync();
      expect(ciContent.contains('flutter pub get'), isTrue);
      expect(ciContent.contains('flutter analyze'), isTrue);
      expect(ciContent.contains('flutter test'), isTrue);
      expect(ciContent.contains('python3 -m unittest'), isTrue);
      expect(ciContent.contains('tool/push_lab.dart'), isTrue);

      expect(preCiScript.existsSync(), isTrue);
      final preCiContent = preCiScript.readAsStringSync();
      expect(preCiContent.contains('flutter pub get'), isTrue);
      expect(preCiContent.contains('flutter analyze'), isTrue);
      expect(preCiContent.contains('flutter test'), isTrue);
    });
  });
}

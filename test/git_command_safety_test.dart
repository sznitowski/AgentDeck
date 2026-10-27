import 'package:flutter_test/flutter_test.dart';
import 'package:agentdeck/features/git/domain/git_parsers.dart';

void main() {
  group('GitCommandSafety', () {
    test('validates safe executable names and rejects command injection', () {
      expect(GitCommandSafety.isValidExecutable('git'), isTrue);
      expect(GitCommandSafety.isValidExecutable('/usr/bin/git'), isTrue);
      expect(GitCommandSafety.isValidExecutable('/usr/local/bin/git'), isTrue);

      expect(GitCommandSafety.isValidExecutable(''), isFalse);
      expect(GitCommandSafety.isValidExecutable('git; rm -rf /'), isFalse);
      expect(GitCommandSafety.isValidExecutable('git && whoami'), isFalse);
      expect(GitCommandSafety.isValidExecutable('git | cat'), isFalse);
      expect(GitCommandSafety.isValidExecutable('git `id`'), isFalse);
      expect(GitCommandSafety.isValidExecutable(r'git $(id)'), isFalse);
    });

    test('escapes POSIX arguments safely against shell escapes', () {
      expect(GitCommandSafety.escapeArgument('main'), "'main'");
      expect(GitCommandSafety.escapeArgument("feat: user's fix"),
          "'feat: user'\"'\"'s fix'");
      expect(
          GitCommandSafety.escapeArgument('msg; rm -rf /'), "'msg; rm -rf /'");
      expect(GitCommandSafety.escapeArgument(r'$(whoami)'), "'\$(whoami)'");
      expect(GitCommandSafety.escapeArgument('`id`'), "'`id`'");

      expect(() => GitCommandSafety.escapeArgument('bad\u0000arg'),
          throwsFormatException);
    });

    test('detects sensitive file patterns correctly', () {
      expect(GitCommandSafety.isSensitiveFile('.env'), isTrue);
      expect(GitCommandSafety.isSensitiveFile('.env.production'), isTrue);
      expect(GitCommandSafety.isSensitiveFile('/var/www/project/.env.local'),
          isTrue);
      expect(GitCommandSafety.isSensitiveFile('certs/server.key'), isTrue);
      expect(GitCommandSafety.isSensitiveFile('secrets/tls.pem'), isTrue);
      expect(GitCommandSafety.isSensitiveFile('id_rsa'), isTrue);
      expect(GitCommandSafety.isSensitiveFile('id_ed25519'), isTrue);
      expect(GitCommandSafety.isSensitiveFile('credentials.json'), isTrue);
      expect(GitCommandSafety.isSensitiveFile('api_token_config.dart'), isTrue);

      expect(GitCommandSafety.isSensitiveFile('lib/main.dart'), isFalse);
      expect(GitCommandSafety.isSensitiveFile('pubspec.yaml'), isFalse);
      expect(GitCommandSafety.isSensitiveFile('README.md'), isFalse);
    });

    test('sanitizes working directory path against invalid characters', () {
      expect(GitCommandSafety.sanitizeWorkingDirectory('/var/www/app'),
          '/var/www/app');
      expect(GitCommandSafety.sanitizeWorkingDirectory('/home/user/project/'),
          '/home/user/project');

      expect(() => GitCommandSafety.sanitizeWorkingDirectory('/bad\npath'),
          throwsFormatException);
      expect(() => GitCommandSafety.sanitizeWorkingDirectory('/bad\u0000path'),
          throwsFormatException);
    });
  });
}

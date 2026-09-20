import 'package:agentdeck/core/domain/posix_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PosixPath.normalize', () {
    test('normalizes root and simple absolute paths', () {
      expect(PosixPath.normalize('/'), '/');
      expect(PosixPath.normalize('///'), '/');
      expect(PosixPath.normalize('/var/log'), '/var/log');
      expect(PosixPath.normalize('/var/log/'), '/var/log');
      expect(PosixPath.normalize('/var//log///app.log'), '/var/log/app.log');
    });

    test('resolves . and .. in absolute paths', () {
      expect(PosixPath.normalize('/a/b/../c'), '/a/c');
      expect(PosixPath.normalize('/a/./b/./c'), '/a/b/c');
      expect(PosixPath.normalize('/a/b/../../..'), '/');
      expect(PosixPath.normalize('/..'), '/');
      expect(PosixPath.normalize('/a/b/../../c/d'), '/c/d');
    });

    test('normalizes relative paths', () {
      expect(PosixPath.normalize(''), '.');
      expect(PosixPath.normalize('.'), '.');
      expect(PosixPath.normalize('a/b/../c'), 'a/c');
      expect(PosixPath.normalize('a/b/../../..'), '..');
      expect(PosixPath.normalize('../a'), '../a');
    });

    test('rejects null bytes', () {
      expect(() => PosixPath.normalize('/etc/pass\u0000wd'),
          throwsA(isA<FormatException>()));
    });
  });

  group('PosixPath.join', () {
    test('joins base and relative segment', () {
      expect(PosixPath.join('/var/docker', 'project'), '/var/docker/project');
      expect(PosixPath.join('/var/docker/', 'project'), '/var/docker/project');
      expect(PosixPath.join('/', 'home'), '/home');
      expect(PosixPath.join('', 'home'), 'home');
      expect(PosixPath.join('.', 'file.txt'), 'file.txt');
    });

    test('replaces base when segment is absolute', () {
      expect(PosixPath.join('/var/docker', '/etc/hosts'), '/etc/hosts');
    });

    test('rejects null bytes in base or segment', () {
      expect(() => PosixPath.join('/var', 'test\u0000'),
          throwsA(isA<FormatException>()));
      expect(() => PosixPath.join('/var\u0000', 'test'),
          throwsA(isA<FormatException>()));
    });
  });

  group('PosixPath.parent and basename', () {
    test('computes parent path', () {
      expect(PosixPath.parent('/var/docker/project'), '/var/docker');
      expect(PosixPath.parent('/var'), '/');
      expect(PosixPath.parent('/'), '/');
      expect(PosixPath.parent('.'), '.');
      expect(PosixPath.parent('a/b'), 'a');
    });

    test('computes basename', () {
      expect(PosixPath.basename('/var/docker/project'), 'project');
      expect(PosixPath.basename('/var/docker/file.txt'), 'file.txt');
      expect(PosixPath.basename('/'), '/');
      expect(PosixPath.basename('file.txt'), 'file.txt');
    });

    test('computes extension', () {
      expect(PosixPath.extension('/var/file.txt'), '.txt');
      expect(PosixPath.extension('/var/archive.tar.gz'), '.gz');
      expect(PosixPath.extension('/var/noext'), '');
      expect(PosixPath.extension('/var/.env'), '');
      expect(PosixPath.extension('/var/.env.local'), '.local');
    });
  });

  group('PosixPath validation', () {
    test('isValidFilename allows valid POSIX names', () {
      expect(PosixPath.isValidFilename('project'), isTrue);
      expect(PosixPath.isValidFilename('docker-compose.yml'), isTrue);
      expect(PosixPath.isValidFilename('.env'), isTrue);
      expect(PosixPath.isValidFilename('archivo-ñ-漢字.txt'), isTrue);
    });

    test('isValidFilename rejects invalid filenames', () {
      expect(PosixPath.isValidFilename(''), isFalse);
      expect(PosixPath.isValidFilename('   '), isFalse);
      expect(PosixPath.isValidFilename('.'), isFalse);
      expect(PosixPath.isValidFilename('..'), isFalse);
      expect(PosixPath.isValidFilename('a/b'), isFalse);
      expect(PosixPath.isValidFilename('a\u0000b'), isFalse);
      expect(PosixPath.isValidFilename('a' * 256), isFalse);
    });

    test('containsTraversal detects .. in paths', () {
      expect(PosixPath.containsTraversal('a/../b'), isTrue);
      expect(PosixPath.containsTraversal('../b'), isTrue);
      expect(PosixPath.containsTraversal('/var/docker/project'), isFalse);
      expect(PosixPath.containsTraversal('a/b\u0000c'), isTrue);
    });
  });
}

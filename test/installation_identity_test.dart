import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/domain/installation_identity.dart';
import 'package:agentdeck/core/infrastructure/file_installation_identity_repository.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';

void main() {
  group('InstallationIdentity.generate', () {
    test('has 128 bits in a stable, validatable format', () {
      final id = InstallationIdentity.generate().id;
      expect(id, matches(RegExp(r'^inst_[0-9a-f]{32}$')));
      expect(InstallationIdentity.isValidId(id), isTrue);
    });

    test('is unique across many draws and independent of the clock', () {
      final fixedNow = DateTime.utc(2026, 1, 1);
      final ids = {
        for (var i = 0; i < 2000; i++)
          InstallationIdentity.generate(now: fixedNow).id
      };
      expect(ids.length, 2000);
    });

    test('accepts an injected random source for deterministic tests', () {
      final a = InstallationIdentity.generate(random: Random(7)).id;
      final b = InstallationIdentity.generate(random: Random(7)).id;
      final c = InstallationIdentity.generate(random: Random(8)).id;
      expect(a, b);
      expect(a, isNot(c));
      expect(InstallationIdentity.isValidId(a), isTrue);
    });

    test('json round trip keeps id and creation time', () {
      final original = InstallationIdentity.generate();
      final copy = InstallationIdentity.fromJson(original.toJson());
      expect(copy.id, original.id);
      expect(copy.createdAt, original.createdAt);
    });
  });

  group('InstallationIdentity.isValidId', () {
    test('accepts current and legacy formats only', () {
      expect(InstallationIdentity.isValidId('inst_${'a' * 32}'), isTrue);
      expect(InstallationIdentity.isValidId('inst_${'0' * 16}'), isTrue);
      for (final bad in [
        '',
        'inst_',
        'inst_${'a' * 31}',
        'inst_${'a' * 33}',
        'inst_${'A' * 32}',
        'inst_${'g' * 32}',
        'device_${'a' * 32}',
        ' inst_${'a' * 32}',
      ]) {
        expect(InstallationIdentity.isValidId(bad), isFalse, reason: bad);
      }
    });
  });

  group('FileInstallationIdentityRepository', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('agentdeck_identity_');
      file = File('${dir.path}/identity.json');
    });
    tearDown(() async => await dir.delete(recursive: true));

    FileInstallationIdentityRepository repo() =>
        FileInstallationIdentityRepository(JsonFileStore(file));

    test('generates once and persists across repository instances', () async {
      final first = await repo().getIdentity();
      expect(InstallationIdentity.isValidId(first.id), isTrue);
      final second = await repo().getIdentity();
      expect(second.id, first.id);
      expect(second.createdAt, first.createdAt);
    });

    test('an existing legacy identity is kept, never regenerated', () async {
      const legacy = 'inst_0123456789abcdef';
      await file.writeAsString(jsonEncode({
        'schema': 1,
        'items': [
          {'id': legacy, 'createdAt': '2026-09-24T20:00:00.000Z'}
        ]
      }));
      final identity = await repo().getIdentity();
      expect(identity.id, legacy);
      expect(identity.createdAt, DateTime.utc(2026, 9, 24, 20));
      expect(await file.readAsString(), contains(legacy));
    });

    test('a missing or malformed id is replaced by a valid one', () async {
      for (final item in [
        <String, dynamic>{'id': '', 'createdAt': '2026-01-01T00:00:00Z'},
        <String, dynamic>{'id': 'not-an-installation-id'},
        <String, dynamic>{'createdAt': '2026-01-01T00:00:00Z'},
      ]) {
        await file.writeAsString(jsonEncode({
          'schema': 1,
          'items': [item]
        }));
        final identity = await repo().getIdentity();
        expect(InstallationIdentity.isValidId(identity.id), isTrue);
        expect((await repo().getIdentity()).id, identity.id);
      }
    });

    test('a corrupt file fails closed and is not overwritten', () async {
      await file.writeAsString('{ definitely not json');
      await expectLater(repo().getIdentity(), throwsA(anything));
      expect(await file.readAsString(), '{ definitely not json');
    });
  });
}

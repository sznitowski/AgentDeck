import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/notifications/infrastructure/file_relay_config_repository.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('agentdeck_relay_cfg_');
    file = File('${dir.path}/relay_config.json');
  });
  tearDown(() async => await dir.delete(recursive: true));

  FileRelayConfigRepository repo() =>
      FileRelayConfigRepository(JsonFileStore(file));

  test('the relay URL is empty initially and nothing is written', () async {
    expect(await repo().getRelayUrl(), isNull);
    await repo().readCheck();
    expect(await file.exists(), isFalse);
  });

  test('saves the normalized origin and survives a restart', () async {
    await repo().setRelayUrl(' https://Relay.Example.com:8443/ ');
    expect(await repo().getRelayUrl(), 'https://relay.example.com:8443');
    // New instance over the same file = app restart.
    expect(await FileRelayConfigRepository(JsonFileStore(file)).getRelayUrl(),
        'https://relay.example.com:8443');
  });

  test('stored data is versioned JSON holding only the origin', () async {
    await repo().setRelayUrl('https://relay.example.com');
    final decoded = jsonDecode(await file.readAsString());
    expect(decoded['schema'], 1);
    expect(decoded['items'], [
      {'relayUrl': 'https://relay.example.com'}
    ]);
    final text = await file.readAsString();
    for (final forbidden in ['token', 'secret', 'adt_', 'Authorization']) {
      expect(text.toLowerCase(), isNot(contains(forbidden.toLowerCase())));
    }
  });

  test('invalid URLs are rejected and leave the stored value untouched',
      () async {
    await repo().setRelayUrl('https://relay.example.com');
    for (final bad in [
      '',
      'http://relay.example.com',
      'https://relay.example.com/path',
      'https://user@relay.example.com',
      'ftp://relay.example.com',
    ]) {
      await expectLater(repo().setRelayUrl(bad), throwsArgumentError,
          reason: bad);
    }
    expect(await repo().getRelayUrl(), 'https://relay.example.com');
  });

  test('null clears the configuration', () async {
    await repo().setRelayUrl('https://relay.example.com');
    await repo().setRelayUrl(null);
    expect(await repo().getRelayUrl(), isNull);
  });

  test('a tampered file cannot smuggle in a URL the policy rejects', () async {
    await file.writeAsString(jsonEncode({
      'schema': 1,
      'items': [
        {'relayUrl': 'http://evil.example.com'}
      ]
    }));
    expect(await repo().getRelayUrl(), isNull);
  });

  test('a corrupt file fails closed and is not overwritten', () async {
    await file.writeAsString('<<<corrupt>>>');
    await expectLater(repo().readCheck(), throwsA(anything));
    await expectLater(repo().getRelayUrl(), throwsA(anything));
    expect(await file.readAsString(), '<<<corrupt>>>');
  });

  test('changing the URL does not leave the previous origin behind', () async {
    await repo().setRelayUrl('https://relay-a.example.com');
    await repo().setRelayUrl('https://relay-b.example.com');
    final decoded = jsonDecode(await file.readAsString());
    expect((decoded['items'] as List).length, 1);
    expect(await repo().getRelayUrl(), 'https://relay-b.example.com');
  });
}

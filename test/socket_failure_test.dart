import 'dart:io';

import 'package:agentdeck/features/connections/domain/ssh_models.dart';
import 'package:agentdeck/features/connections/infrastructure/dart_ssh_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows timeout and refusal socket codes map to distinct SSH failures',
      () {
    expect(
        classifySocketException(const SocketException('localized',
                osError: OSError('localized', 10060)))
            .kind,
        SshFailureKind.timeout);
    expect(
        classifySocketException(const SocketException('localized',
                osError: OSError('localized', 10061)))
            .kind,
        SshFailureKind.refused);
  });

  test('Windows 1225 localized refusal maps to refused', () {
    expect(
        classifySocketException(const SocketException('localized',
                osError: OSError('localized', 1225)))
            .kind,
        SshFailureKind.refused);
  });

  test('POSIX timeout and refusal codes and host lookup are classified', () {
    expect(
        classifySocketException(const SocketException('localized',
                osError: OSError('localized', 110)))
            .kind,
        SshFailureKind.timeout);
    expect(
        classifySocketException(const SocketException('localized',
                osError: OSError('localized', 111)))
            .kind,
        SshFailureKind.refused);
    expect(
        classifySocketException(const SocketException('Failed host lookup'))
            .kind,
        SshFailureKind.dns);
  });
}

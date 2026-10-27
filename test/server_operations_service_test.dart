import 'package:flutter_test/flutter_test.dart';
import 'package:agentdeck/core/domain/git.dart' show RemoteCommandOutput;
import 'package:agentdeck/core/domain/server_operations.dart';
import 'package:agentdeck/features/servers/application/server_operations_service.dart';

class _FakeServerCommandExecutor implements ServerCommandExecutor {
  final Map<String, RemoteCommandOutput> responses = {};
  final List<String> executedCommands = [];

  void setResponse(
      String executable, List<String> args, RemoteCommandOutput output) {
    final key = '$executable ${args.join(' ')}';
    responses[key] = output;
  }

  @override
  Future<RemoteCommandOutput> execute(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    final key = '$executable ${arguments.join(' ')}';
    executedCommands.add(key);
    if (responses.containsKey(key)) {
      return responses[key]!;
    }
    // Generic fallbacks
    if (executable == 'uname') {
      return const RemoteCommandOutput(0, 'Linux testhost 5.15.0 x86_64\n', '');
    }
    if (executable == 'cat' && arguments.contains('/proc/stat')) {
      return const RemoteCommandOutput(
          0, 'cpu  5000 100 500 4000 10 5 5 0 0 0\n', '');
    }
    if (executable == 'cat' && arguments.contains('/proc/meminfo')) {
      return const RemoteCommandOutput(
          0,
          'MemTotal: 8000000 kB\nMemFree: 2000000 kB\nMemAvailable: 4000000 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n',
          '');
    }
    if (executable == 'cat' && arguments.contains('/proc/loadavg')) {
      return const RemoteCommandOutput(0, '0.50 0.60 0.70 1/150 12345\n', '');
    }
    if (executable == 'cat' && arguments.contains('/proc/uptime')) {
      return const RemoteCommandOutput(0, '123456.78 456789.12\n', '');
    }
    if (executable == 'cat' && arguments.contains('/etc/os-release')) {
      return const RemoteCommandOutput(
          0,
          'NAME="Ubuntu"\nVERSION="22.04 LTS"\nID=ubuntu\nPRETTY_NAME="Ubuntu 22.04 LTS"\n',
          '');
    }
    if (executable == 'df') {
      return const RemoteCommandOutput(
          0,
          'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 10000000 4000000 6000000 40% /\n',
          '');
    }
    if (executable == 'command' && arguments.contains('systemctl')) {
      return const RemoteCommandOutput(0, '/bin/systemctl\n', '');
    }
    if (executable == 'systemctl' && arguments.contains('is-system-running')) {
      return const RemoteCommandOutput(0, 'running\n', '');
    }
    if (executable == 'systemctl' && arguments.contains('list-units')) {
      return const RemoteCommandOutput(
          0,
          'nginx.service loaded active running Nginx Web Server\nportal.service loaded failed failed Portal Backend\n',
          '');
    }
    if (executable == 'ps') {
      return const RemoteCommandOutput(
          0,
          'PID PPID USER %CPU %MEM STAT COMMAND\n1 0 root 0.1 0.2 Ss systemd\n200 1 app 15.0 4.0 R node\n',
          '');
    }

    return const RemoteCommandOutput(0, '', '');
  }
}

void main() {
  late _FakeServerCommandExecutor executor;
  late RemoteServerOperationsService service;

  setUp(() {
    executor = _FakeServerCommandExecutor();
    service = RemoteServerOperationsService(executor: executor);
  });

  group('RemoteServerOperationsService', () {
    test('discoverCapabilities detects Linux, procfs, and systemd', () async {
      final caps = await service.discoverCapabilities();
      expect(caps.isLinux, isTrue);
      expect(caps.hasProcfs, isTrue);
      expect(caps.hasSystemd, isTrue);
      expect(caps.isAlpine, isFalse);
    });

    test('discoverCapabilities detects Alpine without systemd', () async {
      executor.setResponse(
        'cat',
        ['/etc/os-release'],
        const RemoteCommandOutput(0, 'NAME="Alpine Linux"\nID=alpine\n', ''),
      );
      executor.setResponse(
        'command',
        ['-v', 'systemctl'],
        const RemoteCommandOutput(1, '', 'not found'),
      );

      final service2 = RemoteServerOperationsService(executor: executor);
      final caps = await service2.discoverCapabilities();
      expect(caps.isLinux, isTrue);
      expect(caps.isAlpine, isTrue);
      expect(caps.hasSystemd, isFalse);
    });

    test('getHostInfo aggregates identity details', () async {
      final info = await service.getHostInfo();
      expect(info.hostname, equals('testhost'));
      expect(info.osName, equals('Ubuntu 22.04 LTS'));
      expect(info.architecture, equals('x86_64'));
      expect(info.uptimeSeconds, equals(123456.78));
      expect(info.bootTime, isNotNull);
    });

    test('getHealthSnapshot collects memory, disk, load, and service counts',
        () async {
      final snapshot = await service.getHealthSnapshot();
      expect(snapshot.loadAvg1m, equals(0.50));
      expect(snapshot.loadAvg5m, equals(0.60));
      expect(snapshot.loadAvg15m, equals(0.70));
      expect(snapshot.memory.totalBytes, equals(8000000 * 1024));
      expect(snapshot.memory.availableBytes, equals(4000000 * 1024));
      expect(snapshot.memory.usagePercent, equals(50.0));
      expect(snapshot.disks.length, equals(1));
      expect(snapshot.disks[0].mountPoint, equals('/'));
      expect(snapshot.disks[0].usagePercent, equals(40.0));
      expect(snapshot.processCount, equals(150));
      expect(snapshot.runningServicesCount, equals(1));
      expect(snapshot.failedServicesCount, equals(1));
    });

    test('getProcesses returns processes and sorts by requested field',
        () async {
      final list =
          await service.getProcesses(sortField: 'cpu', descending: true);
      expect(list.length, equals(2));
      expect(list[0].command, equals('node'));
      expect(list[0].cpuPercent, equals(15.0));
      expect(list[1].command, equals('systemd'));
    });

    test('getServices and getServiceDetail work with systemd', () async {
      final svcs = await service.getServices();
      expect(svcs.length, equals(2));
      expect(svcs[0].name, equals('nginx.service'));
      expect(svcs[0].isActive, isTrue);
      expect(svcs[1].name, equals('portal.service'));
      expect(svcs[1].isFailed, isTrue);

      executor.setResponse(
        'systemctl',
        [
          'show',
          'nginx.service',
          '--property=Id,Description,LoadState,ActiveState,SubState,UnitFileState,MainPID',
        ],
        const RemoteCommandOutput(
          0,
          'Id=nginx.service\nDescription=Nginx\nLoadState=loaded\nActiveState=active\nSubState=running\nUnitFileState=enabled\nMainPID=1200\n',
          '',
        ),
      );

      final detail = await service.getServiceDetail('nginx.service');
      expect(detail.name, equals('nginx.service'));
      expect(detail.mainPid, equals(1200));
      expect(detail.enabledState, equals('enabled'));
    });

    test('service actions throw permissionDenied on unauthorized user',
        () async {
      executor.setResponse(
        'systemctl',
        ['restart', 'nginx.service'],
        const RemoteCommandOutput(4, '',
            'Failed to restart nginx.service: Interactive authentication required.'),
      );

      expect(
        () => service.restartService('nginx.service'),
        throwsA(isA<ServerOperationFailure>().having(
          (e) => e.kind,
          'kind',
          ServerOperationFailureKind.permissionDenied,
        )),
      );
    });

    test('service actions validate against injection attempts', () async {
      expect(
        () => service.restartService('nginx; reboot'),
        throwsA(isA<ServerOperationFailure>().having(
          (e) => e.kind,
          'kind',
          ServerOperationFailureKind.invalidServiceName,
        )),
      );
    });
  });
}

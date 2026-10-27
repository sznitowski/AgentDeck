import 'package:flutter_test/flutter_test.dart';
import 'package:agentdeck/core/domain/server_operations.dart';
import 'package:agentdeck/features/servers/domain/server_parsers.dart';

void main() {
  group('ProcStatParser', () {
    test('parses aggregate cpu line and calculates delta', () {
      const sample1Text = '''
cpu  4705 356 584 3699 23 12 21 0 0 0
cpu0 2350 178 292 1850 11 6 10 0 0 0
cpu1 2355 178 292 1849 12 6 11 0 0 0
''';
      final s1 = ProcStatParser.parseSample(sample1Text);
      expect(s1.user, equals(4705));
      expect(s1.nice, equals(356));
      expect(s1.system, equals(584));
      expect(s1.idle, equals(3699));
      expect(s1.iowait, equals(23));
      expect(s1.idleTime, equals(3722));

      const sample2Text = '''
cpu  5205 356 684 3799 23 12 21 0 0 0
''';
      final s2 = ProcStatParser.parseSample(sample2Text);
      // deltaNonIdle = (5205-4705) + (684-584) = 500 + 100 = 600
      // deltaIdle = (3799-3699) = 100
      // deltaTotal = 700
      // usage = (1 - 100/700) * 100 = 85.714%
      final delta = s1.calculateDelta(s2);
      expect(delta.totalPercent, closeTo(85.71, 0.05));
    });

    test('throws parseFailure if no aggregate cpu line', () {
      expect(
        () => ProcStatParser.parseSample('invalid stat content'),
        throwsA(isA<ServerOperationFailure>().having(
          (e) => e.kind,
          'kind',
          ServerOperationFailureKind.parseFailure,
        )),
      );
    });
  });

  group('ProcMeminfoParser', () {
    test('parses memory and swap correctly with MemAvailable', () {
      const meminfoText = '''
MemTotal:       16301284 kB
MemFree:         4125820 kB
MemAvailable:   11245800 kB
Buffers:          345612 kB
Cached:          7120400 kB
SwapTotal:       2097148 kB
SwapFree:        1048574 kB
''';
      final mem = ProcMeminfoParser.parse(meminfoText);
      expect(mem.totalBytes, equals(16301284 * 1024));
      expect(mem.availableBytes, equals(11245800 * 1024));
      expect(mem.usedBytes, equals((16301284 - 11245800) * 1024));
      expect(mem.swapTotalBytes, equals(2097148 * 1024));
      expect(mem.swapUsedBytes, equals((2097148 - 1048574) * 1024));
      expect(mem.usagePercent, closeTo(31.01, 0.05));
      expect(mem.swapUsagePercent, closeTo(50.0, 0.05));
    });

    test('calculates available memory fallback when MemAvailable is absent',
        () {
      const legacyMeminfo = '''
MemTotal:       4000000 kB
MemFree:        1000000 kB
Buffers:         500000 kB
Cached:          500000 kB
SwapTotal:             0 kB
SwapFree:              0 kB
''';
      final mem = ProcMeminfoParser.parse(legacyMeminfo);
      expect(mem.availableBytes, equals(2000000 * 1024));
      expect(mem.usedBytes, equals(2000000 * 1024));
      expect(mem.usagePercent, closeTo(50.0, 0.01));
      expect(mem.swapUsagePercent, equals(0.0));
    });
  });

  group('ProcLoadavgParser', () {
    test('parses 1m, 5m, 15m load averages', () {
      const loadavgText = '0.42 0.78 1.15 2/245 45892';
      final (m1, m5, m15) = ProcLoadavgParser.parse(loadavgText);
      expect(m1, equals(0.42));
      expect(m5, equals(0.78));
      expect(m15, equals(1.15));
    });
  });

  group('ProcUptimeParser', () {
    test('parses uptime seconds', () {
      const uptimeText = '350735.65 2783945.12';
      final uptime = ProcUptimeParser.parse(uptimeText);
      expect(uptime, equals(350735.65));
    });
  });

  group('OsReleaseParser', () {
    test('parses os-release key value pairs and quotes', () {
      const osReleaseText = '''
NAME="Ubuntu"
VERSION="22.04.3 LTS (Jammy Jellyfish)"
ID=ubuntu
PRETTY_NAME="Ubuntu 22.04.3 LTS"
VERSION_ID="22.04"
''';
      final map = OsReleaseParser.parseOsRelease(osReleaseText);
      expect(map['NAME'], equals('Ubuntu'));
      expect(map['ID'], equals('ubuntu'));
      expect(map['PRETTY_NAME'], equals('Ubuntu 22.04.3 LTS'));
      expect(map['VERSION_ID'], equals('22.04'));
    });

    test('combines uname, os-release, and uptime into ServerInfo', () {
      const osRelease = 'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"';
      const uname = 'Linux lab-node 6.1.0-18-amd64 x86_64';
      final info = OsReleaseParser.combine(
        osReleaseContent: osRelease,
        unameOutput: uname,
        uptimeSeconds: 86400 * 2 + 3600 * 3 + 120, // 2 days 3 hours 2 min
      );

      expect(info.hostname, equals('lab-node'));
      expect(info.osName, equals('Debian GNU/Linux 12 (bookworm)'));
      expect(info.kernel, equals('Linux 6.1.0-18-amd64'));
      expect(info.architecture, equals('x86_64'));
      expect(info.formattedUptime, equals('2 d 3 h 2 m'));
      expect(info.bootTime, isNotNull);
    });
  });

  group('DfParser', () {
    test('parses POSIX df -P -k and filters pseudo-filesystems', () {
      const dfOutput = '''
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/sda1        102626244  42150820  55215836      44% /
/dev/sdb1        512340000 125000000 361200000      26% /data
tmpfs              8150640         0   8150640       0% /dev/shm
udev               8124000         0   8124000       0% /dev
overlay           10000000   1000000   9000000      10% /var/lib/docker/overlay2/xxx
''';
      final disks = DfParser.parse(dfOutput);
      expect(disks.length, equals(2));
      expect(disks[0].mountPoint, equals('/'));
      expect(disks[0].filesystem, equals('/dev/sda1'));
      expect(disks[0].usagePercent, equals(44.0));
      expect(disks[0].totalBytes, equals(102626244 * 1024));

      expect(disks[1].mountPoint, equals('/data'));
      expect(disks[1].filesystem, equals('/dev/sdb1'));
      expect(disks[1].usagePercent, equals(26.0));
    });
  });

  group('PsParser', () {
    test('parses process list with command privacy', () {
      const psOutput = '''
PID  PPID USER     %CPU %MEM STAT COMMAND
  1     0 root      0.0  0.1 Ss   systemd
 45     1 root      1.2  0.5 S    dockerd
120    45 root      5.4  2.1 Sl   containerd
450   120 appuser  12.5  4.8 R    node
''';
      final list = PsParser.parse(psOutput);
      expect(list.length, equals(4));

      expect(list[0].pid, equals(1));
      expect(list[0].parentPid, equals(0));
      expect(list[0].user, equals('root'));
      expect(list[0].command, equals('systemd'));
      expect(list[0].state, equals(ProcessState.sleeping));

      expect(list[3].pid, equals(450));
      expect(list[3].user, equals('appuser'));
      expect(list[3].cpuPercent, equals(12.5));
      expect(list[3].memoryPercent, equals(4.8));
      expect(list[3].state, equals(ProcessState.running));
      expect(list[3].command, equals('node'));
    });
  });

  group('SystemctlParser', () {
    test('parses list-units output into active and failed services', () {
      const listUnits = '''
nginx.service loaded active running A high performance web server
portal-api.service loaded failed failed Portal Backend Daemon
ssh.service loaded active running OpenBSD Secure Shell server
cron.service loaded inactive dead Regular background program processing daemon
''';
      final svcs = SystemctlParser.parseListUnits(listUnits);
      expect(svcs.length, equals(4));
      expect(svcs[0].name, equals('nginx.service'));
      expect(svcs[0].activeState, equals(ServiceActiveState.active));
      expect(svcs[0].subState, equals('running'));
      expect(svcs[0].description, equals('A high performance web server'));

      expect(svcs[1].name, equals('portal-api.service'));
      expect(svcs[1].isFailed, isTrue);

      expect(svcs[3].name, equals('cron.service'));
      expect(svcs[3].activeState, equals(ServiceActiveState.inactive));
    });

    test('parses systemctl show properties', () {
      const showOutput = '''
Id=nginx.service
Description=A high performance web server and a reverse proxy server
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=1452
''';
      final svc = SystemctlParser.parseShow(showOutput, 'nginx.service');
      expect(svc.name, equals('nginx.service'));
      expect(svc.description,
          equals('A high performance web server and a reverse proxy server'));
      expect(svc.loadState, equals('loaded'));
      expect(svc.activeState, equals(ServiceActiveState.active));
      expect(svc.subState, equals('running'));
      expect(svc.enabledState, equals('enabled'));
      expect(svc.mainPid, equals(1452));
    });
  });

  group('ServerOpsCommandSafety', () {
    test('validates valid service names', () {
      expect(
          ServerOpsCommandSafety.isValidServiceName('nginx.service'), isTrue);
      expect(ServerOpsCommandSafety.isValidServiceName('portal-api@1.service'),
          isTrue);
      expect(
          ServerOpsCommandSafety.isValidServiceName('docker.socket'), isTrue);
      expect(
          ServerOpsCommandSafety.isValidServiceName('user-1000.slice'), isTrue);
    });

    test('blocks malicious and injection service names', () {
      expect(ServerOpsCommandSafety.isValidServiceName('nginx; rm -rf /'),
          isFalse);
      expect(ServerOpsCommandSafety.isValidServiceName('nginx && reboot'),
          isFalse);
      expect(ServerOpsCommandSafety.isValidServiceName('nginx | cat'), isFalse);
      expect(ServerOpsCommandSafety.isValidServiceName('`whoami`.service'),
          isFalse);
      expect(ServerOpsCommandSafety.isValidServiceName('\$(reboot).service'),
          isFalse);
      expect(
          ServerOpsCommandSafety.isValidServiceName('service\nname'), isFalse);
      expect(ServerOpsCommandSafety.isValidServiceName(''), isFalse);

      expect(
        () => ServerOpsCommandSafety.validateServiceName('bad; service'),
        throwsA(isA<ServerOperationFailure>().having(
          (e) => e.kind,
          'kind',
          ServerOperationFailureKind.invalidServiceName,
        )),
      );
    });
  });
}

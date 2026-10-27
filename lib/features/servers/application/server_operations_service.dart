import 'dart:async';

import '../../../core/domain/server_operations.dart';
import '../domain/server_parsers.dart';

/// Implementation of [ServerOperationsService] for remote Linux hosts over SSH.
class RemoteServerOperationsService implements ServerOperationsService {
  RemoteServerOperationsService({
    required this.executor,
  });

  final ServerCommandExecutor executor;

  ServerCapabilities? _cachedCapabilities;
  CpuSample? _lastCpuSample;
  DateTime? _lastCpuSampleTime;

  @override
  Future<ServerCapabilities> discoverCapabilities() async {
    if (_cachedCapabilities != null) {
      return _cachedCapabilities!;
    }

    try {
      final unameRes = await executor.execute('uname', ['-s']);
      final isLinux = unameRes.stdout.trim().toLowerCase().startsWith('linux');

      if (!isLinux) {
        final caps = const ServerCapabilities(
          isLinux: false,
          hasProcfs: false,
          hasSystemd: false,
        );
        _cachedCapabilities = caps;
        return caps;
      }

      // Check procfs
      final procStatRes = await executor.execute('cat', ['/proc/stat']);
      final hasProcfs = procStatRes.exitCode == 0;

      // Check distribution (Alpine vs Debian/RHEL/etc.)
      var isAlpine = false;
      String? distId;
      try {
        final osRes = await executor.execute('cat', ['/etc/os-release']);
        if (osRes.exitCode == 0) {
          final osMap = OsReleaseParser.parseOsRelease(osRes.stdout);
          distId = osMap['ID']?.toLowerCase();
          final idLike = osMap['ID_LIKE']?.toLowerCase() ?? '';
          if (distId == 'alpine' || idLike.contains('alpine')) {
            isAlpine = true;
          }
        }
      } catch (_) {}

      // Check systemd
      var hasSystemd = false;
      try {
        final systemctlCheck =
            await executor.execute('command', ['-v', 'systemctl']);
        if (systemctlCheck.exitCode == 0) {
          final runningCheck =
              await executor.execute('systemctl', ['is-system-running']);
          // is-system-running returns 0 (running), or non-zero with states like degraded, maintenance, initializing
          final out = runningCheck.stdout.trim().toLowerCase();
          if (runningCheck.exitCode == 0 ||
              out == 'degraded' ||
              out == 'running' ||
              out == 'maintenance' ||
              out == 'initializing' ||
              out == 'stopping') {
            hasSystemd = true;
          }
        }
      } catch (_) {}

      final caps = ServerCapabilities(
        isLinux: true,
        hasProcfs: hasProcfs,
        hasSystemd: hasSystemd,
        isAlpine: isAlpine,
        distributionId: distId,
      );
      _cachedCapabilities = caps;
      return caps;
    } catch (e) {
      if (e is ServerOperationFailure) rethrow;
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'Failed to discover server capabilities: $e',
        e,
      );
    }
  }

  @override
  Future<ServerInfo> getHostInfo() async {
    try {
      final unameRes =
          await executor.execute('uname', ['-s', '-n', '-r', '-m']);
      if (unameRes.exitCode != 0) {
        _mapError('uname', unameRes.exitCode, unameRes.stderr);
      }

      var osReleaseContent = '';
      try {
        final osRes = await executor.execute('cat', ['/etc/os-release']);
        if (osRes.exitCode == 0) {
          osReleaseContent = osRes.stdout;
        } else {
          final fallbackOs =
              await executor.execute('cat', ['/usr/lib/os-release']);
          if (fallbackOs.exitCode == 0) {
            osReleaseContent = fallbackOs.stdout;
          }
        }
      } catch (_) {}

      var uptimeSeconds = 0.0;
      try {
        final uptimeRes = await executor.execute('cat', ['/proc/uptime']);
        if (uptimeRes.exitCode == 0) {
          uptimeSeconds = ProcUptimeParser.parse(uptimeRes.stdout);
        }
      } catch (_) {}

      return OsReleaseParser.combine(
        osReleaseContent: osReleaseContent,
        unameOutput: unameRes.stdout,
        uptimeSeconds: uptimeSeconds,
      );
    } catch (e) {
      if (e is ServerOperationFailure) rethrow;
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'Failed to retrieve host information: $e',
        e,
      );
    }
  }

  @override
  Future<ServerHealthSnapshot> getHealthSnapshot() async {
    try {
      final caps = await discoverCapabilities();
      if (!caps.isLinux) {
        throw const ServerOperationFailure(
          ServerOperationFailureKind.unsupportedPlatform,
          'Host is not a Linux system.',
        );
      }

      // 1. Load Average
      final loadRes = await executor.execute('cat', ['/proc/loadavg']);
      if (loadRes.exitCode != 0) {
        _mapError('/proc/loadavg', loadRes.exitCode, loadRes.stderr);
      }
      final (m1, m5, m15) = ProcLoadavgParser.parse(loadRes.stdout);

      // 2. Memory
      final memRes = await executor.execute('cat', ['/proc/meminfo']);
      if (memRes.exitCode != 0) {
        _mapError('/proc/meminfo', memRes.exitCode, memRes.stderr);
      }
      final memory = ProcMeminfoParser.parse(memRes.stdout);

      // 3. Disks
      final dfRes = await executor.execute('df', ['-P', '-k']);
      final disks =
          dfRes.exitCode == 0 ? DfParser.parse(dfRes.stdout) : <DiskUsage>[];

      // 4. CPU calculation (delta sampling)
      CpuUsage cpuUsage = const CpuUsage(totalPercent: 0.0);
      try {
        final statRes = await executor.execute('cat', ['/proc/stat']);
        if (statRes.exitCode == 0) {
          final sample = ProcStatParser.parseSample(statRes.stdout);
          final now = DateTime.now();

          if (_lastCpuSample != null &&
              _lastCpuSampleTime != null &&
              now.difference(_lastCpuSampleTime!).inMilliseconds > 200 &&
              now.difference(_lastCpuSampleTime!).inSeconds < 60) {
            cpuUsage = _lastCpuSample!.calculateDelta(sample);
            _lastCpuSample = sample;
            _lastCpuSampleTime = now;
          } else {
            _lastCpuSample = sample;
            _lastCpuSampleTime = now;
            // Short 250ms delta measurement on initial observation
            await Future<void>.delayed(const Duration(milliseconds: 250));
            final statRes2 = await executor.execute('cat', ['/proc/stat']);
            if (statRes2.exitCode == 0) {
              final sample2 = ProcStatParser.parseSample(statRes2.stdout);
              cpuUsage = sample.calculateDelta(sample2);
              _lastCpuSample = sample2;
              _lastCpuSampleTime = DateTime.now();
            }
          }
        }
      } catch (_) {}

      // 5. Process count
      var processCount = 0;
      final tokens = loadRes.stdout
          .trim()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.length >= 4 && tokens[3].contains('/')) {
        final parts = tokens[3].split('/');
        if (parts.length >= 2) {
          processCount = int.tryParse(parts[1]) ?? 0;
        }
      }

      // 6. Services count (if systemd available)
      var runningServices = 0;
      var failedServices = 0;
      if (caps.hasSystemd) {
        try {
          final svcs = await getServices();
          for (final s in svcs) {
            if (s.isActive) runningServices++;
            if (s.isFailed) failedServices++;
          }
        } catch (_) {}
      }

      return ServerHealthSnapshot(
        observedAt: DateTime.now(),
        loadAvg1m: m1,
        loadAvg5m: m5,
        loadAvg15m: m15,
        cpu: cpuUsage,
        memory: memory,
        disks: disks,
        processCount: processCount,
        runningServicesCount: runningServices,
        failedServicesCount: failedServices,
      );
    } catch (e) {
      if (e is ServerOperationFailure) rethrow;
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'Failed to get health snapshot: $e',
        e,
      );
    }
  }

  @override
  Future<List<RemoteProcess>> getProcesses({
    String? sortField,
    bool descending = true,
  }) async {
    try {
      // Default to sorting by CPU on server if supported
      var psRes = await executor.execute(
        'ps',
        ['-eo', 'pid,ppid,user,%cpu,%mem,stat,comm', '--sort=-%cpu'],
      );

      if (psRes.exitCode != 0) {
        // Fallback without GNU sort option for Alpine/Busybox ps
        psRes = await executor.execute(
          'ps',
          ['-eo', 'pid,ppid,user,%cpu,%mem,stat,comm'],
        );
      }

      if (psRes.exitCode != 0) {
        _mapError('ps', psRes.exitCode, psRes.stderr);
      }

      final list = PsParser.parse(psRes.stdout);

      if (sortField != null) {
        list.sort((a, b) {
          final cmp = switch (sortField) {
            'cpu' => a.cpuPercent.compareTo(b.cpuPercent),
            'memory' => a.memoryPercent.compareTo(b.memoryPercent),
            'pid' => a.pid.compareTo(b.pid),
            'name' =>
              a.command.toLowerCase().compareTo(b.command.toLowerCase()),
            _ => a.cpuPercent.compareTo(b.cpuPercent),
          };
          return descending ? -cmp : cmp;
        });
      }

      return list;
    } catch (e) {
      if (e is ServerOperationFailure) rethrow;
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'Failed to list processes: $e',
        e,
      );
    }
  }

  @override
  Future<List<SystemService>> getServices() async {
    final caps = await discoverCapabilities();
    if (!caps.hasSystemd) {
      return const [];
    }

    try {
      final res = await executor.execute(
        'systemctl',
        [
          'list-units',
          '--type=service',
          '--all',
          '--no-pager',
          '--no-legend',
          '--plain',
        ],
      );

      if (res.exitCode != 0) {
        _mapError('systemctl list-units', res.exitCode, res.stderr);
      }

      return SystemctlParser.parseListUnits(res.stdout);
    } catch (e) {
      if (e is ServerOperationFailure) rethrow;
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'Failed to list systemd services: $e',
        e,
      );
    }
  }

  @override
  Future<SystemService> getServiceDetail(String serviceName) async {
    ServerOpsCommandSafety.validateServiceName(serviceName);
    final caps = await discoverCapabilities();
    if (!caps.hasSystemd) {
      throw const ServerOperationFailure(
        ServerOperationFailureKind.commandUnavailable,
        'Systemd is not available on this host.',
      );
    }

    try {
      final res = await executor.execute(
        'systemctl',
        [
          'show',
          serviceName,
          '--property=Id,Description,LoadState,ActiveState,SubState,UnitFileState,MainPID',
        ],
      );

      if (res.exitCode != 0) {
        _mapError('systemctl show', res.exitCode, res.stderr);
      }

      return SystemctlParser.parseShow(res.stdout, serviceName);
    } catch (e) {
      if (e is ServerOperationFailure) rethrow;
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'Failed to inspect service $serviceName: $e',
        e,
      );
    }
  }

  @override
  Future<void> startService(String serviceName) async {
    ServerOpsCommandSafety.validateServiceName(serviceName);
    await _executeServiceAction('start', serviceName);
  }

  @override
  Future<void> stopService(String serviceName) async {
    ServerOpsCommandSafety.validateServiceName(serviceName);
    await _executeServiceAction('stop', serviceName);
  }

  @override
  Future<void> restartService(String serviceName) async {
    ServerOpsCommandSafety.validateServiceName(serviceName);
    await _executeServiceAction('restart', serviceName);
  }

  Future<void> _executeServiceAction(String action, String serviceName) async {
    final caps = await discoverCapabilities();
    if (!caps.hasSystemd) {
      throw const ServerOperationFailure(
        ServerOperationFailureKind.commandUnavailable,
        'Systemd is not available on this host.',
      );
    }

    try {
      final res = await executor.execute('systemctl', [action, serviceName]);
      if (res.exitCode != 0) {
        _mapError('systemctl $action', res.exitCode, res.stderr);
      }
    } catch (e) {
      if (e is ServerOperationFailure) rethrow;
      throw ServerOperationFailure(
        ServerOperationFailureKind.operationFailed,
        'Failed to $action service $serviceName: $e',
        e,
      );
    }
  }

  void _mapError(String command, int exitCode, String stderr) {
    final lower = stderr.toLowerCase();
    if (exitCode == 4 ||
        lower.contains('permission denied') ||
        lower.contains('access denied') ||
        lower.contains('interactive authentication required') ||
        lower.contains('must be root') ||
        lower.contains('failed to connect to bus')) {
      throw ServerOperationFailure(
        ServerOperationFailureKind.permissionDenied,
        '$command requires elevated permissions: $stderr',
      );
    }
    if (exitCode == 127 ||
        lower.contains('not found') ||
        lower.contains('no such file')) {
      throw ServerOperationFailure(
        ServerOperationFailureKind.commandUnavailable,
        'Command unavailable: $command',
      );
    }
    throw ServerOperationFailure(
      ServerOperationFailureKind.operationFailed,
      '$command exited with status $exitCode: $stderr',
    );
  }
}

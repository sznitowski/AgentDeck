import '../../../core/domain/server_operations.dart';

/// Validation and safety rules for remote server execution.
class ServerOpsCommandSafety {
  static final RegExp _serviceNameRegex = RegExp(r'^[a-zA-Z0-9_\.\-@]+$');

  /// Validates whether a service name is safe to pass to systemctl without injection.
  static bool isValidServiceName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 256) return false;
    return _serviceNameRegex.hasMatch(trimmed);
  }

  /// Validates service name and throws a typed failure if invalid.
  static void validateServiceName(String name) {
    if (!isValidServiceName(name)) {
      throw ServerOperationFailure(
        ServerOperationFailureKind.invalidServiceName,
        'Invalid service name contains forbidden characters: "$name"',
      );
    }
  }

  /// Escapes a string for safe inclusion in a POSIX shell command if needed.
  static String posixEscape(String argument) {
    if (argument.isEmpty) return "''";
    if (RegExp(r'^[a-zA-Z0-9_./\-+=@]+$').hasMatch(argument)) {
      return argument;
    }
    return "'${argument.replaceAll("'", "'\\''")}'";
  }
}

/// Parser for Linux /proc/stat CPU counters.
class ProcStatParser {
  /// Parses the aggregate "cpu " line from /proc/stat content.
  static CpuSample parseSample(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('cpu ') || trimmed.startsWith('cpu\t')) {
        final tokens =
            trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (tokens.length >= 5) {
          final user = int.tryParse(tokens[1]) ?? 0;
          final nice = int.tryParse(tokens[2]) ?? 0;
          final system = int.tryParse(tokens[3]) ?? 0;
          final idle = int.tryParse(tokens[4]) ?? 0;
          final iowait = tokens.length > 5 ? (int.tryParse(tokens[5]) ?? 0) : 0;
          final irq = tokens.length > 6 ? (int.tryParse(tokens[6]) ?? 0) : 0;
          final softirq =
              tokens.length > 7 ? (int.tryParse(tokens[7]) ?? 0) : 0;
          final steal = tokens.length > 8 ? (int.tryParse(tokens[8]) ?? 0) : 0;
          final guest = tokens.length > 9 ? (int.tryParse(tokens[9]) ?? 0) : 0;
          final guestNice =
              tokens.length > 10 ? (int.tryParse(tokens[10]) ?? 0) : 0;

          return CpuSample(
            user: user,
            nice: nice,
            system: system,
            idle: idle,
            iowait: iowait,
            irq: irq,
            softirq: softirq,
            steal: steal,
            guest: guest,
            guestNice: guestNice,
          );
        }
      }
    }
    throw const ServerOperationFailure(
      ServerOperationFailureKind.parseFailure,
      'Could not find aggregate cpu line in /proc/stat',
    );
  }
}

/// Parser for Linux /proc/meminfo memory and swap metrics.
class ProcMeminfoParser {
  static MemoryUsage parse(String content) {
    final lines = content.split('\n');
    final map = <String, int>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex != -1) {
        final key = trimmed.substring(0, colonIndex).trim();
        final valPart = trimmed.substring(colonIndex + 1).trim();
        final tokens = valPart.split(RegExp(r'\s+'));
        if (tokens.isNotEmpty) {
          final valKb = int.tryParse(tokens[0]);
          if (valKb != null) {
            map[key] = valKb;
          }
        }
      }
    }

    final totalKb = map['MemTotal'] ?? 0;
    final freeKb = map['MemFree'] ?? 0;
    final buffersKb = map['Buffers'] ?? 0;
    final cachedKb = map['Cached'] ?? 0;
    final availableKb = map['MemAvailable'] ?? (freeKb + buffersKb + cachedKb);
    final usedKb = (totalKb - availableKb).clamp(0, totalKb);

    final swapTotalKb = map['SwapTotal'] ?? 0;
    final swapFreeKb = map['SwapFree'] ?? 0;
    final swapUsedKb = (swapTotalKb - swapFreeKb).clamp(0, swapTotalKb);

    return MemoryUsage(
      totalBytes: totalKb * 1024,
      availableBytes: availableKb * 1024,
      usedBytes: usedKb * 1024,
      freeBytes: freeKb * 1024,
      cachedBytes: cachedKb * 1024,
      buffersBytes: buffersKb * 1024,
      swapTotalBytes: swapTotalKb * 1024,
      swapUsedBytes: swapUsedKb * 1024,
      swapFreeBytes: swapFreeKb * 1024,
    );
  }
}

/// Parser for Linux /proc/loadavg load averages.
class ProcLoadavgParser {
  static (double, double, double) parse(String content) {
    final tokens = content
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length >= 3) {
      final m1 = double.tryParse(tokens[0]) ?? 0.0;
      final m5 = double.tryParse(tokens[1]) ?? 0.0;
      final m15 = double.tryParse(tokens[2]) ?? 0.0;
      return (m1, m5, m15);
    }
    throw const ServerOperationFailure(
      ServerOperationFailureKind.parseFailure,
      'Invalid /proc/loadavg format',
    );
  }
}

/// Parser for Linux /proc/uptime.
class ProcUptimeParser {
  static double parse(String content) {
    final tokens = content
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isNotEmpty) {
      final uptime = double.tryParse(tokens[0]);
      if (uptime != null) return uptime;
    }
    throw const ServerOperationFailure(
      ServerOperationFailureKind.parseFailure,
      'Invalid /proc/uptime format',
    );
  }
}

/// Parser for OS release details and uname outputs.
class OsReleaseParser {
  static Map<String, String> parseOsRelease(String content) {
    final result = <String, String>{};
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final idx = trimmed.indexOf('=');
      if (idx != -1) {
        final key = trimmed.substring(0, idx).trim();
        var val = trimmed.substring(idx + 1).trim();
        if ((val.startsWith('"') && val.endsWith('"')) ||
            (val.startsWith("'") && val.endsWith("'"))) {
          val = val.substring(1, val.length - 1);
        }
        result[key] = val;
      }
    }
    return result;
  }

  static ServerInfo combine({
    required String osReleaseContent,
    required String unameOutput,
    required double uptimeSeconds,
  }) {
    final osMap = parseOsRelease(osReleaseContent);
    final unameTokens = unameOutput
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    // uname -s -r -m -n output: [sysname, nodename/host, release, machine]
    // Or uname -s -n -r -m
    String kernel = 'Linux';
    String hostname = 'unknown';
    String architecture = 'unknown';

    if (unameTokens.length >= 4) {
      kernel = '${unameTokens[0]} ${unameTokens[2]}';
      hostname = unameTokens[1];
      architecture = unameTokens[3];
    } else if (unameTokens.isNotEmpty) {
      kernel = unameTokens.join(' ');
    }

    final osName =
        osMap['PRETTY_NAME'] ?? osMap['NAME'] ?? osMap['ID'] ?? 'Linux';
    final osVersion = osMap['VERSION'] ?? osMap['VERSION_ID'] ?? '';

    final now = DateTime.now();
    final bootTime =
        now.subtract(Duration(milliseconds: (uptimeSeconds * 1000).toInt()));

    return ServerInfo(
      hostname: hostname,
      osName: osName,
      osVersion: osVersion,
      kernel: kernel,
      architecture: architecture,
      uptimeSeconds: uptimeSeconds,
      bootTime: bootTime,
    );
  }
}

/// Parser for `df -P -k` POSIX disk usage.
class DfParser {
  static List<DiskUsage> parse(String output) {
    final lines = output.split('\n');
    final result = <DiskUsage>[];

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty || i == 0 && trimmed.startsWith('Filesystem'))
        continue;

      final tokens =
          trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.length >= 6) {
        final fs = tokens[0];
        final total1k = int.tryParse(tokens[1]) ?? 0;
        final used1k = int.tryParse(tokens[2]) ?? 0;
        final avail1k = int.tryParse(tokens[3]) ?? 0;
        var capStr = tokens[4];
        if (capStr.endsWith('%')) {
          capStr = capStr.substring(0, capStr.length - 1);
        }
        final capPercent = double.tryParse(capStr) ?? 0.0;
        final mount = tokens.sublist(5).join(' ');

        // Filter out pseudo-filesystems
        if (_isPseudoFilesystem(fs, mount)) continue;

        result.add(DiskUsage(
          filesystem: fs,
          mountPoint: mount,
          totalBytes: total1k * 1024,
          usedBytes: used1k * 1024,
          availableBytes: avail1k * 1024,
          usagePercent: capPercent,
        ));
      }
    }

    return result;
  }

  static bool _isPseudoFilesystem(String fs, String mountPoint) {
    final lowerFs = fs.toLowerCase();
    if (lowerFs.startsWith('tmpfs') ||
        lowerFs.startsWith('devtmpfs') ||
        lowerFs.startsWith('udev') ||
        lowerFs.startsWith('none') ||
        lowerFs.startsWith('cgroup') ||
        lowerFs.startsWith('shm') ||
        lowerFs.startsWith('squashfs') ||
        (lowerFs.startsWith('overlay') && mountPoint != '/')) {
      return true;
    }
    return false;
  }
}

/// Parser for `ps -eo pid,ppid,user,%cpu,%mem,stat,comm --sort=-%cpu`.
class PsParser {
  static List<RemoteProcess> parse(String output) {
    final lines = output.split('\n');
    final result = <RemoteProcess>[];

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty ||
          (i == 0 && trimmed.toUpperCase().startsWith('PID'))) {
        continue;
      }

      final tokens =
          trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.length >= 7) {
        final pid = int.tryParse(tokens[0]) ?? 0;
        final ppid = int.tryParse(tokens[1]);
        final user = tokens[2];
        final cpu = double.tryParse(tokens[3]) ?? 0.0;
        final mem = double.tryParse(tokens[4]) ?? 0.0;
        final statRaw = tokens[5];
        final comm = tokens.sublist(6).join(' ');

        final state = _mapProcessState(statRaw);

        result.add(RemoteProcess(
          pid: pid,
          parentPid: ppid,
          user: user,
          command: comm,
          executable: comm,
          cpuPercent: cpu,
          memoryPercent: mem,
          state: state,
          stateRaw: statRaw,
        ));
      }
    }

    return result;
  }

  static ProcessState _mapProcessState(String statRaw) {
    if (statRaw.isEmpty) return ProcessState.unknown;
    final primary = statRaw[0].toUpperCase();
    return switch (primary) {
      'R' => ProcessState.running,
      'S' => ProcessState.sleeping,
      'D' => ProcessState.diskSleep,
      'T' => ProcessState.stopped,
      'Z' => ProcessState.zombie,
      'I' => ProcessState.idle,
      'X' => ProcessState.dead,
      _ => ProcessState.unknown,
    };
  }
}

/// Parser for systemd service unit listings and property blocks.
class SystemctlParser {
  /// Parses output of `systemctl list-units --type=service --all --no-pager --no-legend --plain`.
  static List<SystemService> parseListUnits(String output) {
    final lines = output.split('\n');
    final result = <SystemService>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final tokens =
          trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.length >= 4) {
        final unitName = tokens[0];
        final loadState = tokens[1];
        final activeStr = tokens[2];
        final subState = tokens[3];
        final description =
            tokens.length > 4 ? tokens.sublist(4).join(' ') : '';

        final activeState = _mapActiveState(activeStr);

        result.add(SystemService(
          name: unitName,
          description: description,
          loadState: loadState,
          activeState: activeState,
          subState: subState,
        ));
      }
    }

    return result;
  }

  /// Parses output of `systemctl show <unit> --property=...`.
  static SystemService parseShow(String output, String defaultName) {
    final lines = output.split('\n');
    final map = <String, String>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf('=');
      if (idx != -1) {
        final key = trimmed.substring(0, idx).trim();
        final val = trimmed.substring(idx + 1).trim();
        map[key] = val;
      }
    }

    final name = map['Id'] ?? defaultName;
    final description = map['Description'] ?? '';
    final loadState = map['LoadState'] ?? 'unknown';
    final activeStr = map['ActiveState'] ?? 'unknown';
    final subState = map['SubState'] ?? 'unknown';
    final unitFileState = map['UnitFileState'];
    final mainPidStr = map['MainPID'];
    final mainPid = mainPidStr != null ? int.tryParse(mainPidStr) : null;

    return SystemService(
      name: name,
      description: description,
      loadState: loadState,
      activeState: _mapActiveState(activeStr),
      subState: subState,
      enabledState: unitFileState,
      mainPid: mainPid != 0 ? mainPid : null,
    );
  }

  static ServiceActiveState _mapActiveState(String raw) {
    return switch (raw.toLowerCase()) {
      'active' => ServiceActiveState.active,
      'reloading' => ServiceActiveState.reloading,
      'inactive' => ServiceActiveState.inactive,
      'failed' => ServiceActiveState.failed,
      'activating' => ServiceActiveState.activating,
      'deactivating' => ServiceActiveState.deactivating,
      _ => ServiceActiveState.unknown,
    };
  }
}

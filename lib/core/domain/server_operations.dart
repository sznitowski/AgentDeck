import 'git.dart' show RemoteCommandOutput;

/// Host identity and kernel release metadata.
class ServerInfo {
  const ServerInfo({
    required this.hostname,
    required this.osName,
    required this.osVersion,
    required this.kernel,
    required this.architecture,
    required this.uptimeSeconds,
    this.bootTime,
  });

  final String hostname;
  final String osName;
  final String osVersion;
  final String kernel;
  final String architecture;
  final double uptimeSeconds;
  final DateTime? bootTime;

  String get formattedUptime {
    final totalSeconds = uptimeSeconds.toInt();
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (days > 0) {
      return '$days d $hours h $minutes m';
    } else if (hours > 0) {
      return '$hours h $minutes m';
    } else {
      return '$minutes m';
    }
  }
}

/// A raw counter reading from /proc/stat.
class CpuSample {
  const CpuSample({
    required this.user,
    required this.nice,
    required this.system,
    required this.idle,
    required this.iowait,
    required this.irq,
    required this.softirq,
    required this.steal,
    required this.guest,
    required this.guestNice,
  });

  final int user;
  final int nice;
  final int system;
  final int idle;
  final int iowait;
  final int irq;
  final int softirq;
  final int steal;
  final int guest;
  final int guestNice;

  int get idleTime => idle + iowait;
  int get nonIdleTime => user + nice + system + irq + softirq + steal;
  int get totalTime => idleTime + nonIdleTime;

  /// Calculates the CPU usage between this sample and a later [second] sample.
  CpuUsage calculateDelta(CpuSample second) {
    final deltaIdle = second.idleTime - idleTime;
    final deltaTotal = second.totalTime - totalTime;

    if (deltaTotal <= 0) {
      return const CpuUsage(totalPercent: 0.0);
    }

    final usage = (1.0 - (deltaIdle / deltaTotal)) * 100.0;
    final clamped = usage.clamp(0.0, 100.0);
    return CpuUsage(totalPercent: clamped);
  }
}

/// Instantaneous or delta-computed CPU utilization percentages.
class CpuUsage {
  const CpuUsage({
    required this.totalPercent,
    this.userPercent,
    this.systemPercent,
    this.idlePercent,
    this.iowaitPercent,
  });

  final double totalPercent;
  final double? userPercent;
  final double? systemPercent;
  final double? idlePercent;
  final double? iowaitPercent;
}

/// Memory and swap utilization in bytes and percentages.
class MemoryUsage {
  const MemoryUsage({
    required this.totalBytes,
    required this.availableBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.cachedBytes,
    required this.buffersBytes,
    required this.swapTotalBytes,
    required this.swapUsedBytes,
    required this.swapFreeBytes,
  });

  final int totalBytes;
  final int availableBytes;
  final int usedBytes;
  final int freeBytes;
  final int cachedBytes;
  final int buffersBytes;
  final int swapTotalBytes;
  final int swapUsedBytes;
  final int swapFreeBytes;

  double get usagePercent =>
      totalBytes > 0 ? (usedBytes / totalBytes) * 100.0 : 0.0;

  double get swapUsagePercent =>
      swapTotalBytes > 0 ? (swapUsedBytes / swapTotalBytes) * 100.0 : 0.0;
}

/// Disk utilization for a mounted filesystem.
class DiskUsage {
  const DiskUsage({
    required this.filesystem,
    required this.mountPoint,
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
    required this.usagePercent,
  });

  final String filesystem;
  final String mountPoint;
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  final double usagePercent;
}

/// Operating system process state.
enum ProcessState {
  running,
  sleeping,
  diskSleep,
  stopped,
  zombie,
  idle,
  dead,
  unknown,
}

/// A running or sleeping process on the remote server.
class RemoteProcess {
  const RemoteProcess({
    required this.pid,
    this.parentPid,
    this.user,
    required this.command,
    this.executable,
    this.cpuPercent = 0.0,
    this.memoryPercent = 0.0,
    this.memoryBytes,
    this.state = ProcessState.unknown,
    this.stateRaw,
    this.startedAt,
  });

  final int pid;
  final int? parentPid;
  final String? user;
  final String command;
  final String? executable;
  final double cpuPercent;
  final double memoryPercent;
  final int? memoryBytes;
  final ProcessState state;
  final String? stateRaw;
  final String? startedAt;
}

/// State of a systemd service unit.
enum ServiceActiveState {
  active,
  reloading,
  inactive,
  failed,
  activating,
  deactivating,
  unknown,
}

/// A discovered system service (e.g. systemd unit).
class SystemService {
  const SystemService({
    required this.name,
    required this.description,
    required this.loadState,
    required this.activeState,
    required this.subState,
    this.enabledState,
    this.mainPid,
  });

  final String name;
  final String description;
  final String loadState;
  final ServiceActiveState activeState;
  final String subState;
  final String? enabledState;
  final int? mainPid;

  bool get isFailed => activeState == ServiceActiveState.failed;
  bool get isActive => activeState == ServiceActiveState.active;
}

/// Complete aggregated health observation of a server at a point in time.
class ServerHealthSnapshot {
  const ServerHealthSnapshot({
    required this.observedAt,
    required this.loadAvg1m,
    required this.loadAvg5m,
    required this.loadAvg15m,
    required this.cpu,
    required this.memory,
    required this.disks,
    required this.processCount,
    this.runningServicesCount = 0,
    this.failedServicesCount = 0,
  });

  final DateTime observedAt;
  final double loadAvg1m;
  final double loadAvg5m;
  final double loadAvg15m;
  final CpuUsage cpu;
  final MemoryUsage memory;
  final List<DiskUsage> disks;
  final int processCount;
  final int runningServicesCount;
  final int failedServicesCount;
}

/// Detected platform capabilities of the remote host.
class ServerCapabilities {
  const ServerCapabilities({
    required this.isLinux,
    required this.hasProcfs,
    required this.hasSystemd,
    this.isAlpine = false,
    this.distributionId,
  });

  final bool isLinux;
  final bool hasProcfs;
  final bool hasSystemd;
  final bool isAlpine;
  final String? distributionId;
}

/// Categorized failure states for server operations.
enum ServerOperationFailureKind {
  unsupportedPlatform,
  commandUnavailable,
  permissionDenied,
  timeout,
  connectionLost,
  parseFailure,
  notFound,
  operationFailed,
  invalidServiceName,
}

/// Exception raised when a server observability or management operation fails.
class ServerOperationFailure implements Exception {
  const ServerOperationFailure(this.kind, [this.message, this.cause]);

  final ServerOperationFailureKind kind;
  final String? message;
  final Object? cause;

  @override
  String toString() =>
      'ServerOperationFailure($kind${message != null ? ': $message' : ''})';
}

/// Abstract contract for executing commands against a remote server.
abstract interface class ServerCommandExecutor {
  Future<RemoteCommandOutput> execute(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  });
}

/// Application contract for observing and operating remote servers.
abstract interface class ServerOperationsService {
  Future<ServerCapabilities> discoverCapabilities();

  Future<ServerInfo> getHostInfo();

  Future<ServerHealthSnapshot> getHealthSnapshot();

  Future<List<RemoteProcess>> getProcesses({
    String? sortField,
    bool descending = true,
  });

  Future<List<SystemService>> getServices();

  Future<SystemService> getServiceDetail(String serviceName);

  Future<void> startService(String serviceName);

  Future<void> stopService(String serviceName);

  Future<void> restartService(String serviceName);
}

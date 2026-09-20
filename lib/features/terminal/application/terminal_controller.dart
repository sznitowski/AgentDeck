import 'dart:async';
import 'dart:convert';

import '../../../core/domain/remote_contracts.dart';
import '../../connections/application/ssh_connection_service.dart';

enum TerminalStatus { opening, active, failed, lost, closed }

class TerminalController {
  TerminalController(this.connection, {this.openSession});

  final SshConnectionService connection;
  final Future<TerminalSession> Function(int columns, int rows)? openSession;
  final _output = StreamController<String>.broadcast();
  final _statuses = StreamController<TerminalStatus>.broadcast();
  Stream<String> get output => _output.stream;
  Stream<TerminalStatus> get statuses => _statuses.stream;
  TerminalStatus status = TerminalStatus.opening;
  TerminalSession? _session;
  StreamSubscription<String>? _subscription;
  Timer? _resizeTimer;
  bool _closing = false;
  int _columns = 80;
  int _rows = 24;

  void _setStatus(TerminalStatus value) {
    status = value;
    if (!_statuses.isClosed) _statuses.add(value);
  }

  Future<void> open({int columns = 80, int rows = 24}) async {
    if (_closing || _session != null) return;
    _columns = columns;
    _rows = rows;
    _setStatus(TerminalStatus.opening);
    TerminalSession session;
    try {
      session = await (openSession?.call(columns, rows) ??
          connection.openTerminal(columns, rows));
    } catch (_) {
      _setStatus(TerminalStatus.failed);
      rethrow;
    }
    if (_closing) {
      await session.close();
      return;
    }
    _session = session;
    _subscription = utf8.decoder.bind(session.output).listen(
      (chunk) {
        if (!_output.isClosed) _output.add(chunk);
      },
      onError: (Object _) => _lost(),
      onDone: _lost,
    );
    _setStatus(TerminalStatus.active);
  }

  void _lost() {
    if (_closing || status == TerminalStatus.lost) return;
    _resizeTimer?.cancel();
    _session = null;
    _setStatus(TerminalStatus.lost);
  }

  Future<void> send(String input) async {
    final session = _session;
    if (status != TerminalStatus.active || session == null) return;
    try {
      await session.send(utf8.encode(input));
    } catch (_) {
      _lost();
    }
  }

  void resize(int columns, int rows) {
    if (columns < 1 || rows < 1 || columns > 1000 || rows > 1000) return;
    if (_columns == columns && _rows == rows) return;
    _columns = columns;
    _rows = rows;
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 100), () async {
      final session = _session;
      if (status != TerminalStatus.active || session == null) return;
      try {
        await session.resize(_columns, _rows);
      } catch (_) {
        _lost();
      }
    });
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _resizeTimer?.cancel();
    await _subscription?.cancel();
    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.close();
      } catch (_) {}
    }
    _setStatus(TerminalStatus.closed);
    await _output.close();
    await _statuses.close();
  }
}

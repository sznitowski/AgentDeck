import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../core/domain/profiles.dart';
import '../connections/application/ssh_connection_service.dart';
import '../connections/domain/ssh_models.dart';
import 'application/terminal_controller.dart';
import '../tmux/application/tmux_service.dart';
import '../tmux/domain/tmux_models.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage(
      {super.key,
      required this.profile,
      required this.connection,
      this.tmux,
      this.sessionName})
      : assert((tmux == null) == (sessionName == null));
  final ServerProfile profile;
  final SshConnectionService connection;
  final TmuxService? tmux;
  final String? sessionName;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final TerminalController _connectionTerminal;
  late final xterm.Terminal _terminal;
  late final xterm.TerminalController _viewController;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<TerminalStatus>? _statusSubscription;
  TerminalStatus _status = TerminalStatus.opening;
  bool _ctrl = false;
  bool _toolbarVisible = true;
  String? _errorCategory;

  @override
  void initState() {
    super.initState();
    _connectionTerminal = TerminalController(widget.connection,
        openSession: widget.tmux == null
            ? null
            : (columns, rows) =>
                widget.tmux!.attach(widget.sessionName!, columns, rows));
    _viewController = xterm.TerminalController();
    _terminal = xterm.Terminal(
      maxLines: 2000,
      onOutput: (data) {
        unawaited(_send(data));
      },
      onResize: (columns, rows, _, __) =>
          _connectionTerminal.resize(columns, rows),
    );
    _outputSubscription = _connectionTerminal.output.listen(_terminal.write);
    _statusSubscription = _connectionTerminal.statuses.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _connectionTerminal.open(
          columns: _terminal.viewWidth, rows: _terminal.viewHeight);
    } on TmuxFailure catch (failure) {
      if (mounted)
        setState(() {
          _errorCategory = failure.kind;
          _status = TerminalStatus.failed;
        });
    } on SshFailure catch (failure) {
      if (mounted)
        setState(() {
          _errorCategory = failure.kind.name;
          _status = TerminalStatus.failed;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _errorCategory = 'protocol';
          _status = TerminalStatus.failed;
        });
    }
  }

  Future<void> _reconnect() async {
    if (mounted) setState(() => _status = TerminalStatus.opening);
    try {
      await widget.connection.reconnect(
          widget.profile, const ReconnectPolicy(enabled: true, maxAttempts: 2));
      await _open();
    } on SshFailure catch (failure) {
      if (mounted)
        setState(() {
          _errorCategory = failure.kind.name;
          _status = TerminalStatus.failed;
        });
    }
  }

  Future<void> _detach() async {
    await _connectionTerminal.close();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _send(String data) async {
    if (_ctrl) {
      setState(() => _ctrl = false);
      if (data.length == 1) {
        final code = data.toUpperCase().codeUnitAt(0);
        if (code >= 64 && code <= 95) {
          await _connectionTerminal.send(String.fromCharCode(code & 31));
          return;
        }
      }
    }
    await _connectionTerminal.send(data);
  }

  void _key(xterm.TerminalKey key) {
    _terminal.keyInput(key, ctrl: _ctrl);
    if (_ctrl) setState(() => _ctrl = false);
  }

  Future<void> _copy() async {
    final selection = _viewController.selection;
    if (selection == null) return;
    final text = _terminal.buffer.getText(selection);
    await Clipboard.setData(ClipboardData(text: text));
    _viewController.clearSelection();
  }

  Future<void> _paste() async {
    final value = await Clipboard.getData(Clipboard.kTextPlain);
    final text = value?.text;
    if (text == null || text.isEmpty || !mounted) return;
    _terminal.paste(text);
  }

  @override
  void dispose() {
    unawaited(_outputSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_connectionTerminal.close());
    _viewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _status == TerminalStatus.active;
    return Scaffold(
      appBar:
          AppBar(title: Text('${widget.profile.name} · Terminal'), actions: [
        if (widget.tmux != null)
          TextButton(onPressed: _detach, child: const Text('Detach')),
        IconButton(
            onPressed: () => setState(() => _toolbarVisible = !_toolbarVisible),
            tooltip: _toolbarVisible ? 'Hide key toolbar' : 'Show key toolbar',
            icon: Icon(_toolbarVisible ? Icons.keyboard_hide : Icons.keyboard)),
        if (widget.profile.environment == Environment.production)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                  child: Text('PRODUCTION',
                      style: TextStyle(fontWeight: FontWeight.bold)))),
      ]),
      body: Column(children: [
        if (!active)
          MaterialBanner(
              content: Text(_status == TerminalStatus.opening
                  ? 'Opening shell…'
                  : _status == TerminalStatus.failed
                      ? 'Shell/PTY unavailable (${_errorCategory ?? 'protocol'}). A new connection opens a new shell.'
                      : widget.tmux == null
                          ? 'CONNECTION LOST. Previous shell cannot be resumed. Reconnect opens a new shell.'
                          : 'CONNECTION LOST. Remote tmux session may continue. Reconnect verifies it before Resume.'),
              actions: [
                if (_status != TerminalStatus.opening)
                  TextButton(
                      onPressed: _reconnect, child: const Text('Reconnect')),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ]),
        Expanded(
            child: xterm.TerminalView(_terminal,
                controller: _viewController,
                autofocus: true,
                readOnly: !active)),
        if (active && _toolbarVisible)
          SafeArea(
              top: false,
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _button('Esc', () => _key(xterm.TerminalKey.escape)),
                    _button('Tab', () => _key(xterm.TerminalKey.tab)),
                    _button('Ctrl', () => setState(() => _ctrl = !_ctrl),
                        selected: _ctrl),
                    _button('↑', () => _key(xterm.TerminalKey.arrowUp)),
                    _button('↓', () => _key(xterm.TerminalKey.arrowDown)),
                    _button('←', () => _key(xterm.TerminalKey.arrowLeft)),
                    _button('→', () => _key(xterm.TerminalKey.arrowRight)),
                    _button('Copy', _copy),
                    _button('Paste', _paste),
                  ]))),
      ]),
    );
  }

  Widget _button(String label, VoidCallback action, {bool selected = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: OutlinedButton(
              onPressed: action,
              style: selected
                  ? OutlinedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer)
                  : null,
              child: Text(label)));
}

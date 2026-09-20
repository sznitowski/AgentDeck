import 'package:flutter/material.dart';

import '../../core/domain/profiles.dart';
import '../connections/application/ssh_connection_service.dart';
import '../terminal/terminal_page.dart';
import 'application/tmux_service.dart';
import 'domain/tmux_models.dart';

class PersistentSessionsPage extends StatefulWidget {
  const PersistentSessionsPage(
      {super.key,
      required this.profile,
      required this.connection,
      required this.references});
  final ServerProfile profile;
  final SshConnectionService connection;
  final TmuxSessionRepository references;

  @override
  State<PersistentSessionsPage> createState() => _PersistentSessionsPageState();
}

class _PersistentSessionsPageState extends State<PersistentSessionsPage> {
  late final TmuxService _service;
  TmuxCapability? _capability;
  List<TmuxSessionInfo> _sessions = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TmuxService(
        connection: widget.connection,
        references: widget.references,
        serverId: widget.profile.id);
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted)
      setState(() {
        _busy = true;
        _error = null;
      });
    try {
      final capability = await _service.detect();
      final sessions = capability.availability == TmuxAvailability.available
          ? await _service.list()
          : <TmuxSessionInfo>[];
      if (mounted)
        setState(() {
          _capability = capability;
          _sessions = sessions;
        });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Persistent sessions could not be loaded.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final directory = TextEditingController();
    try {
      final requested = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('New persistent session'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        maxLength: 80,
                        decoration:
                            const InputDecoration(labelText: 'Display name')),
                    TextField(
                        controller: directory,
                        decoration: const InputDecoration(
                            labelText: 'Working directory (optional)',
                            helperText: 'Absolute Linux path')),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Create')),
                  ]));
      if (requested != true || !mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      await _service.create(
          displayName: name.text,
          workingDirectory:
              directory.text.trim().isEmpty ? null : directory.text.trim());
      await _refresh();
    } on TmuxFailure catch (failure) {
      if (mounted) setState(() => _error = 'Create failed: ' + failure.kind);
    } catch (_) {
      if (mounted) setState(() => _error = 'Create failed.');
    } finally {
      name.dispose();
      directory.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(TmuxSessionInfo session) async {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => TerminalPage(
                profile: widget.profile,
                connection: widget.connection,
                tmux: _service,
                sessionName: session.remoteName)));
    if (mounted) await _refresh();
  }

  Future<void> _terminate(TmuxSessionInfo session) async {
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Terminate persistent session?'),
                content: Text('Processes running inside ' +
                    session.displayName +
                    ' will stop.' +
                    (widget.profile.environment == Environment.production
                        ? '\nPRODUCTION'
                        : '')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Terminate')),
                ]));
    if (approved != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.terminate(session.remoteName);
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _error = 'Termination was not confirmed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _capability?.availability == TmuxAvailability.available;
    return Scaffold(
      appBar: AppBar(title: const Text('Persistent Sessions'), actions: [
        IconButton(
            onPressed: _busy ? null : _refresh,
            tooltip: 'Refresh sessions',
            icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.profile.name),
        if (widget.profile.environment == Environment.production)
          const Text('PRODUCTION',
              style: TextStyle(fontWeight: FontWeight.bold)),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_capability?.availability == TmuxAvailability.notInstalled)
          const Text(
              'tmux is not installed on this server. Persistent sessions unavailable. Use a temporary shell.'),
        if (_capability?.availability == TmuxAvailability.unsupported)
          const Text(
              'tmux version could not be understood. Persistent sessions unavailable.'),
        if (_capability?.availability == TmuxAvailability.error)
          const Text('tmux availability could not be verified.'),
        if (available) ...[
          Text('tmux ' + (_capability?.version ?? '')),
          FilledButton(
              onPressed: _busy ? null : _create,
              child: const Text('New persistent session')),
          if (_sessions.isEmpty) const Text('No remote sessions found.'),
          for (final session in _sessions)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(session.displayName,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(session.managed
                              ? 'AgentDeck-managed'
                              : 'External tmux session'),
                          Text(session.state == TmuxSessionState.stale
                              ? 'STALE — not found on server'
                              : session.attachedClients > 0
                                  ? 'Attached on another client'
                                  : 'Detached'),
                          if (session.lastAttachedAt != null)
                            Text('Last attached: ' +
                                session.lastAttachedAt!.toLocal().toString()),
                          if (session.managed)
                            Wrap(spacing: 8, children: [
                              if (session.state != TmuxSessionState.stale)
                                TextButton(
                                    onPressed:
                                        _busy ? null : () => _open(session),
                                    child: Text(session.lastAttachedAt == null
                                        ? 'Open'
                                        : 'Resume')),
                              if (session.state != TmuxSessionState.stale)
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _terminate(session),
                                    child: const Text('Terminate')),
                              if (session.state == TmuxSessionState.stale)
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            await widget.references.delete(
                                                widget.profile.id,
                                                session.remoteName);
                                            if (mounted) await _refresh();
                                          },
                                    child: const Text('Forget reference')),
                            ])
                        ]))),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => TerminalPage(
                        profile: widget.profile,
                        connection: widget.connection))),
            child: const Text('New temporary shell')),
      ]),
    );
  }
}

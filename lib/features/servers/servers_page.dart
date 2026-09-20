import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' hide ConnectionState;

import '../../core/domain/agents.dart';
import '../../core/domain/profiles.dart';
import '../../core/domain/remote_contracts.dart';
import '../connections/application/ssh_connection_service.dart';
import '../connections/domain/ssh_models.dart';
import 'domain/server_profile_repository.dart';

class ServersPage extends StatefulWidget {
  const ServersPage(
      {super.key,
      this.profiles,
      this.credentials,
      this.knownHosts,
      this.connection});
  final ServerProfileRepository? profiles;
  final SecureCredentialStore? credentials;
  final KnownHostRepository? knownHosts;
  final SshConnectionService? connection;

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  List<ServerProfile> _servers = [];
  ServerProfile? _selected;
  StreamSubscription<ConnectionState>? _subscription;
  String? _message;
  SshFailure? _failure;
  String? _connectedId;
  DateTime? _connectedSince;
  bool _busy = false;

  bool get _ready =>
      widget.profiles != null &&
      widget.credentials != null &&
      widget.knownHosts != null &&
      widget.connection != null;

  @override
  void initState() {
    super.initState();
    _subscription = widget.connection?.states.listen((state) {
      if (!mounted) return;
      if (state == ConnectionState.disconnected ||
          state == ConnectionState.failed) {
        _connectedId = null;
        _connectedSince = null;
      }
      setState(() {});
    });
    if (_ready) _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await widget.profiles!.all();
      if (mounted)
        setState(() {
          _servers = items;
          if (_selected != null) {
            for (final item in items) {
              if (item.id == _selected!.id) {
                _selected = item;
                break;
              }
            }
          }
        });
    } catch (_) {
      if (mounted)
        setState(() => _message = 'Server profiles could not be loaded.');
    }
  }

  String _id() {
    final random = Random.secure();
    return List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _editServer([ServerProfile? old]) async {
    if (!_ready) return;
    final draft = await showDialog<_ServerDraft>(
      context: context,
      builder: (context) => _ServerEditorDialog(existing: old),
    );
    if (draft == null) return;
    final newCredential = draft.secret.isNotEmpty;
    final credentialId = newCredential ? _id() : old!.credentialId;
    final newPassphrase = draft.method == SshAuthenticationMethod.privateKey &&
        draft.passphrase.isNotEmpty;
    final passphraseId = newPassphrase
        ? _id()
        : (newCredential ? null : old?.passphraseCredentialId);
    final profile = ServerProfile(
      id: old?.id ?? _id(),
      name: draft.name,
      host: draft.host,
      username: draft.username,
      port: draft.port,
      authenticationMethod: draft.method,
      environment: draft.environment,
      credentialId: credentialId,
      passphraseCredentialId: passphraseId,
    );
    setState(() {
      _busy = true;
      _message = null;
    });
    var saved = false;
    try {
      if (newCredential)
        await widget.credentials!.put(credentialId, utf8.encode(draft.secret));
      if (newPassphrase)
        await widget.credentials!
            .put(passphraseId!, utf8.encode(draft.passphrase));
      await widget.profiles!.save(profile);
      saved = true;
      if (old != null && newCredential)
        await widget.credentials!.delete(old.credentialId);
      if (old?.passphraseCredentialId != null &&
          old!.passphraseCredentialId != passphraseId) {
        await widget.credentials!.delete(old.passphraseCredentialId!);
      }
      await _load();
      if (mounted) setState(() => _selected = profile);
    } catch (_) {
      if (!saved) {
        if (newCredential) {
          try {
            await widget.credentials!.delete(credentialId);
          } catch (_) {}
        }
        if (newPassphrase) {
          try {
            await widget.credentials!.delete(passphraseId!);
          } catch (_) {}
        }
      }
      if (mounted)
        setState(() => _message = saved
            ? 'Server saved, but old credential cleanup failed.'
            : 'Server could not be saved. Check storage availability.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteServer() async {
    final p = _selected;
    if (p == null || !_ready) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Delete server?'),
              content: Text(
                  'Remove ${p.name}, its stored credential and host trust for ${p.host}:${p.port}?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'))
              ],
            ));
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      if (_connectedId == p.id) await widget.connection!.disconnect();
      await widget.credentials!.delete(p.credentialId);
      if (p.passphraseCredentialId != null)
        await widget.credentials!.delete(p.passphraseCredentialId!);
      await widget.knownHosts!.delete(p.host.trim().toLowerCase(), p.port);
      await widget.profiles!.delete(p.id);
      if (mounted) setState(() => _selected = null);
      await _load();
    } catch (_) {
      if (mounted)
        setState(() => _message =
            'Deletion was incomplete. Review storage before reconnecting.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetHost() async {
    final p = _selected;
    if (p == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Remove trusted host identity?'),
              content: const Text(
                  'Only do this after verifying the server identity through a trusted channel. The next connection will ask you to approve its fingerprint again.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remove trust'))
              ],
            ));
    if (confirmed != true) return;
    try {
      await widget.knownHosts!.delete(p.host.trim().toLowerCase(), p.port);
      if (mounted)
        setState(() => _message =
            'Host trust removed. Verify the next fingerprint independently.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not remove host trust.');
    }
  }

  Future<bool> _approveHost(
      ServerProfile profile, HostIdentity identity) async {
    if (!mounted) return false;
    return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
                  title: const Text('Host identity unknown'),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${profile.host}:${profile.port}'),
                        Text('Algorithm: ${identity.algorithm}'),
                        SelectableText('Fingerprint: ${identity.fingerprint}'),
                        const SizedBox(height: 12),
                        const Text(
                            'Confirm this fingerprint through a trusted channel before connecting.')
                      ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Trust & Connect'))
                  ],
                )) ??
        false;
  }

  Future<void> _connect({bool reconnect = false}) async {
    final p = _selected;
    if (p == null || !_ready) return;
    setState(() {
      _busy = true;
      _failure = null;
      _message = null;
    });
    try {
      if (reconnect) {
        await widget.connection!.reconnect(
            p, const ReconnectPolicy(enabled: true, maxAttempts: 2),
            approve: _approveHost);
      } else {
        await widget.connection!.connect(p, approve: _approveHost);
      }
      if (mounted)
        setState(() {
          _connectedId = p.id;
          _connectedSince = DateTime.now();
        });
    } on SshFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } catch (_) {
      if (mounted) setState(() => _message = 'Connection failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _failureText(SshFailure failure) => switch (failure.kind) {
        SshFailureKind.hostMismatch =>
          'CONNECTION BLOCKED: server identity changed.\nExpected: ${failure.expected?.fingerprint}\nReceived: ${failure.received?.fingerprint}',
        SshFailureKind.hostRevoked =>
          'CONNECTION BLOCKED: host identity was revoked.',
        SshFailureKind.hostUnknown => 'Host identity was not approved.',
        SshFailureKind.authentication =>
          'Authentication failed. Check the credential.',
        SshFailureKind.missingCredential ||
        SshFailureKind.secureStorageUnavailable =>
          'Secure credential storage is unavailable or the credential is missing.',
        SshFailureKind.timeout => 'Connection timed out.',
        SshFailureKind.dns => 'Hostname could not be resolved.',
        SshFailureKind.refused => 'Connection was refused.',
        _ => 'Connection failed: ${failure.kind.name}',
      };

  @override
  Widget build(BuildContext context) {
    final p = _selected;
    final state = widget.connection?.state ?? ConnectionState.disconnected;
    final thisConnected =
        p != null && _connectedId == p.id && state == ConnectionState.connected;
    return SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        const Expanded(
            child: Text('Servers',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
        IconButton(
            onPressed: _ready && !_busy ? () => _editServer() : null,
            icon: const Icon(Icons.add),
            tooltip: 'Add server')
      ]),
      const Text('SSH connection · M1.5'),
      if (!_ready)
        const Card(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Storage is not configured. Connection unavailable.'))),
      if (_message != null)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16), child: Text(_message!))),
      for (final server in _servers)
        ListTile(
          title: Text(server.name),
          subtitle: Text('${server.host}:${server.port}'),
          trailing: server.environment == Environment.production
              ? const Chip(label: Text('PRODUCTION'))
              : null,
          selected: p?.id == server.id,
          onTap: () => setState(() {
            _selected = server;
            _failure = null;
          }),
        ),
      if (_servers.isEmpty)
        const ListTile(title: Text('No servers configured')),
      if (p != null) ...[
        const Divider(),
        Text(p.name, style: Theme.of(context).textTheme.titleLarge),
        if (p.environment == Environment.production)
          const Text('PRODUCTION',
              style: TextStyle(fontWeight: FontWeight.bold)),
        Text('${p.host}:${p.port}'),
        Text('user: ${p.username}'),
        Text('authentication: ${p.authenticationMethod.name}'),
        Text('connection: ${thisConnected ? 'CONNECTED' : state.name}'),
        if (thisConnected) ...[
          const Text('Host verification: Trusted'),
          Text('Connected since: ${_connectedSince?.toLocal()}')
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
              onPressed: !_ready ||
                      _busy ||
                      state == ConnectionState.connected ||
                      state == ConnectionState.connecting ||
                      state == ConnectionState.reconnecting
                  ? null
                  : () => _connect(),
              child: const Text('Connect')),
          OutlinedButton(
              onPressed:
                  !_ready || _busy || state == ConnectionState.disconnected
                      ? null
                      : () => widget.connection!.disconnect(),
              child: const Text('Disconnect')),
          OutlinedButton(
              onPressed: !_ready ||
                      _busy ||
                      state == ConnectionState.connecting ||
                      state == ConnectionState.reconnecting
                  ? null
                  : () => _connect(reconnect: true),
              child: const Text('Reconnect')),
          TextButton(
              onPressed: _busy ? null : () => _editServer(p),
              child: const Text('Edit')),
          TextButton(
              onPressed: _busy ? null : _deleteServer,
              child: const Text('Delete')),
          TextButton(
              onPressed: _busy || state == ConnectionState.connected
                  ? null
                  : _resetHost,
              child: const Text('Remove trusted key')),
        ]),
        if (_failure != null)
          Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_failureText(_failure!)))),
      ],
    ]));
  }
}

class _ServerDraft {
  const _ServerDraft(this.name, this.host, this.username, this.port,
      this.method, this.environment, this.secret, this.passphrase);
  final String name;
  final String host;
  final String username;
  final int port;
  final SshAuthenticationMethod method;
  final Environment environment;
  final String secret;
  final String passphrase;
}

class _ServerEditorDialog extends StatefulWidget {
  const _ServerEditorDialog({this.existing});
  final ServerProfile? existing;
  @override
  State<_ServerEditorDialog> createState() => _ServerEditorDialogState();
}

class _ServerEditorDialogState extends State<_ServerEditorDialog> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final host = TextEditingController(text: widget.existing?.host ?? '');
  late final user =
      TextEditingController(text: widget.existing?.username ?? '');
  late final port =
      TextEditingController(text: '${widget.existing?.port ?? 22}');
  final secret = TextEditingController();
  final passphrase = TextEditingController();
  late var method =
      widget.existing?.authenticationMethod ?? SshAuthenticationMethod.password;
  late var environment =
      widget.existing?.environment ?? Environment.development;
  String? validation;

  @override
  void dispose() {
    name.dispose();
    host.dispose();
    user.dispose();
    port.dispose();
    secret.dispose();
    passphrase.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = int.tryParse(port.text.trim());
    if (name.text.trim().isEmpty ||
        host.text.trim().isEmpty ||
        user.text.trim().isEmpty ||
        parsed == null ||
        parsed < 1 ||
        parsed > 65535 ||
        (secret.text.isEmpty &&
            (widget.existing == null ||
                method != widget.existing!.authenticationMethod))) {
      setState(() =>
          validation = 'Enter name, host, user, valid port and a credential.');
      return;
    }
    Navigator.pop(
        context,
        _ServerDraft(name.text.trim(), host.text.trim(), user.text.trim(),
            parsed, method, environment, secret.text, passphrase.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'Add server' : 'Edit server'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name')),
                TextField(
                    controller: host,
                    decoration: const InputDecoration(labelText: 'Hostname')),
                TextField(
                    controller: user,
                    decoration: const InputDecoration(labelText: 'Username')),
                TextField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port')),
                const SizedBox(height: 8),
                DropdownButton<Environment>(
                    value: environment,
                    isExpanded: true,
                    items: Environment.values
                        .map((v) => DropdownMenuItem(
                            value: v, child: Text(v.name.toUpperCase())))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => environment = v ?? environment)),
                DropdownButton<SshAuthenticationMethod>(
                    value: method,
                    isExpanded: true,
                    items: SshAuthenticationMethod.values
                        .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v == SshAuthenticationMethod.password
                                ? 'Password'
                                : 'Private key')))
                        .toList(),
                    onChanged: (v) => setState(() => method = v ?? method)),
                if (method == SshAuthenticationMethod.password)
                  TextField(
                      controller: secret,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                          labelText: widget.existing == null
                              ? 'Password'
                              : 'New password (blank keeps current)')),
                if (method == SshAuthenticationMethod.privateKey) ...[
                  TextField(
                      controller: secret,
                      maxLines: 6,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                          labelText: widget.existing == null
                              ? 'Paste PEM/OpenSSH private key'
                              : 'New private key (blank keeps current)',
                          helperText:
                              'Visible only while entering; never shown again.')),
                  TextField(
                      controller: passphrase,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                          labelText: 'Passphrase (optional)')),
                ],
                if (validation != null)
                  Text(validation!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}

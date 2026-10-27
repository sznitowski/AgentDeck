import 'dart:math';

import 'package:flutter/material.dart' hide ConnectionState;

import '../../core/domain/agents.dart';
import '../../core/domain/profiles.dart';
import '../agents/application/agent_coordinator.dart';
import '../agents/presentation/project_agents_view.dart';
import '../connections/application/ssh_connection_service.dart';
import '../files/application/remote_file_service.dart';
import '../files/presentation/remote_files_page.dart';
import '../git/presentation/project_git_page.dart';
import '../notifications/application/notification_coordinator.dart';
import '../servers/domain/server_profile_repository.dart';
import '../terminal/terminal_page.dart';
import 'application/project_workspace_coordinator.dart';
import 'domain/project_profile_repository.dart';
import 'presentation/project_workspace_page.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({
    super.key,
    this.projects,
    this.servers,
    this.connection,
    this.agents,
    this.coordinator,
    this.notifications,
  });

  final ProjectProfileRepository? projects;
  final ServerProfileRepository? servers;
  final SshConnectionService? connection;
  final AgentCoordinator? agents;
  final ProjectWorkspaceCoordinator? coordinator;
  final NotificationCoordinator? notifications;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  List<ProjectProfile> _projectList = [];
  List<ServerProfile> _serverList = [];
  ProjectProfile? _selected;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.projects == null && widget.servers == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final pList = widget.projects != null
          ? await widget.projects!.all()
          : <ProjectProfile>[];
      final sList = widget.servers != null
          ? await widget.servers!.all()
          : <ServerProfile>[];

      if (mounted) {
        setState(() {
          _projectList = pList;
          _serverList = sList;
          if (_selected != null) {
            _selected = pList.cast<ProjectProfile?>().firstWhere(
                  (p) => p?.id == _selected!.id,
                  orElse: () => pList.isNotEmpty ? pList.first : null,
                );
          } else if (pList.isNotEmpty) {
            _selected = pList.first;
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _id() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _editProject([ProjectProfile? old]) async {
    if (_serverList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Please add a Server first before configuring projects.')),
      );
      return;
    }

    final draft = await showDialog<_ProjectDraft>(
      context: context,
      builder: (context) => _ProjectEditorDialog(
        existing: old,
        servers: _serverList,
      ),
    );

    if (draft == null) return;

    final project = ProjectProfile(
      id: old?.id ?? _id(),
      name: draft.name,
      serverId: draft.serverId,
      workingDirectory: draft.workingDirectory,
      environment: draft.environment,
      executionPolicy: ExecutionPolicy(environment: draft.environment),
      repository: draft.repository.isNotEmpty ? draft.repository : null,
      runtime: draft.runtime.isNotEmpty ? draft.runtime : null,
      preferredAgentId:
          draft.preferredAgentId.isNotEmpty ? draft.preferredAgentId : null,
    );

    if (widget.projects != null) {
      await widget.projects!.save(project);
      await _load();
      setState(() => _selected = project);
    }
  }

  Future<void> _deleteProject(ProjectProfile project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project'),
        content:
            Text('Are you sure you want to remove project "${project.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && widget.projects != null) {
      await widget.projects!.delete(project.id);
      await _load();
    }
  }

  ServerProfile? _findServer(String serverId) {
    for (final s in _serverList) {
      if (s.id == serverId) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = _selected;
    final server = p != null ? _findServer(p.serverId) : null;
    final isConnected = widget.connection != null &&
        server != null &&
        widget.connection!.state == ConnectionState.connected &&
        widget.connection!.connectedProfileId == server.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add project',
            onPressed: () => _editProject(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                for (final project in _projectList) ...[
                  ListTile(
                    title: Text(project.name),
                    subtitle: Text(
                      '${_findServer(project.serverId)?.name ?? project.serverId} · ${project.workingDirectory}',
                    ),
                    trailing: project.environment == Environment.production
                        ? const Chip(
                            label: Text('PRODUCTION',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                    selected: p?.id == project.id,
                    onTap: () => setState(() => _selected = project),
                  ),
                ],
                if (_projectList.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_open,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text(
                            'No projects configured',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Add a project to bind a remote directory to Git and agent orchestration.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _editProject(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Project'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (p != null && server != null) ...[
                  const Divider(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Server: ${server.name} (${server.host}:${server.port})',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13),
                            ),
                            Text(
                              'Path: ${p.workingDirectory}',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (p.environment == Environment.production)
                        const Chip(
                          label: Text('PRODUCTION',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold)),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!isConnected)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.link_off, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Server is disconnected. Connect in Servers tab to perform remote operations.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PROJECT OPERATIONS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: () {
                                  final coord = widget.coordinator ??
                                      (widget.connection != null &&
                                              widget.servers != null
                                          ? ProjectWorkspaceCoordinator(
                                              connection: widget.connection!,
                                              servers: widget.servers!,
                                              agents: widget.agents,
                                            )
                                          : null);
                                  if (coord == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Workspace services unavailable.'),
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ProjectWorkspacePage(
                                        project: p,
                                        coordinator: coord,
                                        connection: widget.connection,
                                        serverProfiles: widget.servers,
                                        agents: widget.agents,
                                        notifications: widget.notifications,
                                      ),
                                    ),
                                  );
                                },
                                icon:
                                    const Icon(Icons.space_dashboard_outlined),
                                label: const Text('Open Workspace'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ProjectGitPage(
                                        project: p,
                                        connection: widget.connection,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.merge_type),
                                label: const Text('Git Operations'),
                              ),
                              if (widget.agents != null)
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ProjectAgentsView(
                                          server: server,
                                          project: p,
                                          coordinator: widget.agents!,
                                          serverProfiles: widget.servers,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.smart_toy_outlined),
                                  label: const Text('Agents'),
                                ),
                              if (widget.connection != null) ...[
                                OutlinedButton.icon(
                                  onPressed: isConnected
                                      ? () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => RemoteFilesPage(
                                                profile: server,
                                                initialPath: p.workingDirectory,
                                                service: RemoteFileService(
                                                  connection:
                                                      widget.connection!,
                                                  serverId: server.id,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      : null,
                                  icon: const Icon(Icons.folder_open),
                                  label: const Text('Browse Files'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: isConnected
                                      ? () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => TerminalPage(
                                                profile: server,
                                                connection: widget.connection!,
                                              ),
                                            ),
                                          );
                                        }
                                      : null,
                                  icon: const Icon(Icons.terminal),
                                  label: const Text('Terminal'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _editProject(p),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        onPressed: () => _deleteProject(p),
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _ProjectDraft {
  _ProjectDraft({
    required this.name,
    required this.serverId,
    required this.workingDirectory,
    required this.environment,
    this.repository = '',
    this.runtime = '',
    this.preferredAgentId = '',
  });

  final String name;
  final String serverId;
  final String workingDirectory;
  final Environment environment;
  final String repository;
  final String runtime;
  final String preferredAgentId;
}

class _ProjectEditorDialog extends StatefulWidget {
  const _ProjectEditorDialog({
    this.existing,
    required this.servers,
  });

  final ProjectProfile? existing;
  final List<ServerProfile> servers;

  @override
  State<_ProjectEditorDialog> createState() => _ProjectEditorDialogState();
}

class _ProjectEditorDialogState extends State<_ProjectEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _workingDir;
  late final TextEditingController _repository;
  late final TextEditingController _runtime;
  late String _serverId;
  late Environment _environment;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _workingDir = TextEditingController(text: p?.workingDirectory ?? '/home');
    _repository = TextEditingController(text: p?.repository ?? '');
    _runtime = TextEditingController(text: p?.runtime ?? '');
    _serverId = p?.serverId ?? widget.servers.first.id;
    _environment = p?.environment ?? Environment.development;
  }

  @override
  void dispose() {
    _name.dispose();
    _workingDir.dispose();
    _repository.dispose();
    _runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Project' : 'Edit Project'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Project Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _serverId,
              decoration: const InputDecoration(labelText: 'Server'),
              items: widget.servers
                  .map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                  .toList(),
              onChanged: (v) => setState(() => _serverId = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _workingDir,
              decoration: const InputDecoration(labelText: 'Working Directory'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Environment>(
              initialValue: _environment,
              decoration: const InputDecoration(labelText: 'Environment'),
              items: Environment.values
                  .map((e) => DropdownMenuItem(
                      value: e, child: Text(e.name.toUpperCase())))
                  .toList(),
              onChanged: (v) => setState(() => _environment = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repository,
              decoration:
                  const InputDecoration(labelText: 'Repository URL (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _runtime,
              decoration:
                  const InputDecoration(labelText: 'Runtime (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isNotEmpty &&
                _workingDir.text.trim().isNotEmpty) {
              Navigator.of(context).pop(
                _ProjectDraft(
                  name: _name.text.trim(),
                  serverId: _serverId,
                  workingDirectory: _workingDir.text.trim(),
                  environment: _environment,
                  repository: _repository.text.trim(),
                  runtime: _runtime.text.trim(),
                  preferredAgentId: widget.existing?.preferredAgentId ?? '',
                ),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

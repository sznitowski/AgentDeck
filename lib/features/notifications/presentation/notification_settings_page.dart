import 'package:flutter/material.dart';

import '../../../core/domain/events.dart';
import '../../../core/domain/installation_identity.dart';
import '../domain/notification_policy.dart';
import '../domain/push_device_registration.dart';
import '../domain/push_notification_service.dart';
import '../domain/push_relay_client.dart';

/// Settings page for configuring Push Notifications, iOS permissions, and lock-screen privacy.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({
    super.key,
    required this.pushService,
    required this.relayClient,
    required this.identityRepo,
    this.registrationRepo,
    this.policy,
    this.relayUrl = 'http://127.0.0.1:8443',
    this.onPolicyChanged,
  });

  final PushNotificationService pushService;
  final PushRelayClient relayClient;
  final InstallationIdentityRepository identityRepo;
  final PushRegistrationRepository? registrationRepo;
  final NotificationPolicy? policy;
  final String relayUrl;
  final ValueChanged<NotificationPolicy>? onPolicyChanged;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  PushAuthorizationStatus _status = PushAuthorizationStatus.notDetermined;
  String? _deviceToken;
  bool _loading = false;
  String? _relayStatus;
  late NotificationPolicy _policy;

  @override
  void initState() {
    super.initState();
    _policy = widget.policy ?? NotificationPolicy();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() => _loading = true);
    final status = await widget.pushService.getAuthorizationStatus();
    final token = await widget.pushService.getDeviceToken();
    final health =
        await widget.relayClient.checkRelayHealth(relayUrl: widget.relayUrl);

    if (mounted) {
      setState(() {
        _status = status;
        _deviceToken = token;
        _relayStatus = health['status'] as String? ?? 'offline';
        _loading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    // 1. Show contextual pre-prompt explanation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Enable Remote Alerts'),
          ],
        ),
        content: const Text(
          'AgentDeck will alert you on your iPhone lock screen when background AI agents require approval or when critical server events occur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    final status = await widget.pushService.requestAuthorization();
    final token = await widget.pushService.getDeviceToken();

    if (status == PushAuthorizationStatus.authorized && token != null) {
      final identity = await widget.identityRepo.getIdentity();
      final registration = PushDeviceRegistration(
        installationId: identity.id,
        deviceToken: token,
        privacyMode: _policy.globalPreferences.privacyMode.name,
      );
      await widget.relayClient
          .registerDevice(registration, relayUrl: widget.relayUrl);
      if (widget.registrationRepo != null) {
        await widget.registrationRepo!.saveRegistration(registration);
      }
    }

    if (mounted) {
      setState(() {
        _status = status;
        _deviceToken = token;
        _loading = false;
      });
    }
  }

  void _updatePrivacyMode(NotificationPrivacyMode mode) {
    setState(() {
      _policy = _policy.copyWith(
        globalPreferences:
            _policy.globalPreferences.copyWith(privacyMode: mode),
      );
    });
    widget.onPolicyChanged?.call(_policy);
  }

  void _toggleType(EventType type, bool enabled) {
    var prefs = _policy.globalPreferences;
    switch (type) {
      case EventType.agentWaitingUser:
        prefs = prefs.copyWith(notifyAgentWaiting: enabled);
        break;
      case EventType.agentFailed:
        prefs = prefs.copyWith(notifyAgentFailed: enabled);
        break;
      case EventType.agentFinished:
        prefs = prefs.copyWith(notifyAgentFinished: enabled);
        break;
      case EventType.gitConflictDetected:
        prefs = prefs.copyWith(notifyGitConflict: enabled);
        break;
      case EventType.serverResourceCritical:
        prefs = prefs.copyWith(notifyServerCritical: enabled);
        break;
      default:
        break;
    }
    setState(() {
      _policy = _policy.copyWith(globalPreferences: prefs);
    });
    widget.onPolicyChanged?.call(_policy);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAuthorized = _status == PushAuthorizationStatus.authorized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Notification Settings'),
        actions: [
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Status',
              onPressed: _loadState,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Permission Status Card
          _buildStatusCard(theme, isAuthorized),
          const SizedBox(height: 20),

          // 2. Lock Screen Privacy Section
          Text('Lock Screen Privacy', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildPrivacySelector(theme),
          const SizedBox(height: 24),

          // 3. Notification Category Toggles
          Text('Notification Categories', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildCategoryToggles(),
          const SizedBox(height: 24),

          // 4. Relay Server & Token Diagnostics
          Text('Push Relay & Token Diagnostics',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildDiagnosticsCard(theme),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, bool isAuthorized) {
    final (statusColor, statusText, statusDesc) = switch (_status) {
      PushAuthorizationStatus.authorized => (
          Colors.green,
          'AUTHORIZED',
          'Push notifications are enabled. You will receive lock screen alerts.'
        ),
      PushAuthorizationStatus.denied => (
          Colors.red,
          'DENIED',
          'Notifications are disabled in iOS Settings. Please open Settings to enable.'
        ),
      PushAuthorizationStatus.notDetermined => (
          Colors.amber,
          'NOT REQUESTED',
          'AgentDeck has not requested permission yet.'
        ),
      _ => (Colors.grey, 'UNKNOWN', 'Status could not be determined.'),
    };

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isAuthorized
                      ? Icons.check_circle_outline
                      : Icons.notifications_off_outlined,
                  color: statusColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'iOS Permission: $statusText',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(statusDesc, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (!isAuthorized)
              FilledButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.notifications_active),
                label: const Text('Enable Notifications'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacySelector(ThemeData theme) {
    final current = _policy.globalPreferences.privacyMode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: RadioGroup<NotificationPrivacyMode>(
          groupValue: current,
          onChanged: (val) => val != null ? _updatePrivacyMode(val) : null,
          child: const Column(
            children: [
              RadioListTile<NotificationPrivacyMode>(
                title: Text('Full Preview'),
                subtitle: Text('Shows project name and agent action details.'),
                value: NotificationPrivacyMode.full,
              ),
              RadioListTile<NotificationPrivacyMode>(
                title: Text('Project Only'),
                subtitle:
                    Text('Displays project name with masked action text.'),
                value: NotificationPrivacyMode.projectOnly,
              ),
              RadioListTile<NotificationPrivacyMode>(
                title: Text('Generic Mode'),
                subtitle: Text(
                    'Completely hides project names and command contents.'),
                value: NotificationPrivacyMode.generic,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryToggles() {
    final prefs = _policy.globalPreferences;

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Agent Waiting for Input'),
            subtitle: const Text(
                'Alert when AI agent requires interactive prompt confirmation'),
            value: prefs.notifyAgentWaiting,
            onChanged: (val) => _toggleType(EventType.agentWaitingUser, val),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Agent Failed'),
            subtitle: const Text(
                'Alert on non-zero exit codes or tool execution errors'),
            value: prefs.notifyAgentFailed,
            onChanged: (val) => _toggleType(EventType.agentFailed, val),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Git Merge Conflicts'),
            subtitle: const Text(
                'Alert when unresolved merge conflicts are detected'),
            value: prefs.notifyGitConflict,
            onChanged: (val) => _toggleType(EventType.gitConflictDetected, val),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Server Resource Spikes'),
            subtitle: const Text(
                'Alert when CPU, Memory, or Disk exceeds 90% utilization'),
            value: prefs.notifyServerCritical,
            onChanged: (val) =>
                _toggleType(EventType.serverResourceCritical, val),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Agent Finished (Informative)'),
            subtitle: const Text('Notify when task completes cleanly'),
            value: prefs.notifyAgentFinished,
            onChanged: (val) => _toggleType(EventType.agentFinished, val),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard(ThemeData theme) {
    final tokenPreview = _deviceToken != null && _deviceToken!.length >= 12
        ? '${_deviceToken!.substring(0, 6)}...${_deviceToken!.substring(_deviceToken!.length - 6)}'
        : 'Not Available';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Relay Endpoint: ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    widget.relayUrl,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Relay Status: ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  _relayStatus?.toUpperCase() ?? 'UNKNOWN',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _relayStatus == 'ok' ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('APNs Device Token: ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  tokenPreview,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

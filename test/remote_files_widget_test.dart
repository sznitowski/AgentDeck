import 'dart:convert';

import 'package:agentdeck/core/domain/profiles.dart';
import 'package:agentdeck/features/connections/application/ssh_connection_service.dart';
import 'package:agentdeck/features/files/application/remote_file_service.dart';
import 'package:agentdeck/features/files/domain/remote_file_models.dart';
import 'package:agentdeck/features/files/presentation/file_viewer_page.dart';
import 'package:agentdeck/features/files/presentation/remote_files_page.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

import 'remote_file_service_test.dart';

void main() {
  const devProfile = ServerProfile(
    id: 'dev-server',
    name: 'Dev Server',
    host: '127.0.0.1',
    port: 22,
    username: 'lab',
    credentialId: 'lab',
    environment: Environment.development,
  );

  const prodProfile = ServerProfile(
    id: 'dev-server',
    name: 'Production Server',
    host: '127.0.0.1',
    port: 22,
    username: 'lab',
    credentialId: 'lab',
    environment: Environment.production,
  );

  late FakeFileSystem fs;
  late SshConnectionService connection;
  late RemoteFileService devService;
  late RemoteFileService prodService;

  setUp(() async {
    fs = FakeFileSystem();
    fs.directories.addAll(['/var', '/var/docker', '/var/docker/project']);
    fs.files['/var/docker/project/README.md'] =
        utf8.encode('# Project\nHello World');
    fs.files['/var/docker/project/.env'] = utf8.encode('SECRET=123');

    connection = SshConnectionService(
      credentials: FakeCredentials(),
      knownHosts: FakeKnownHosts(),
      transport: FakeSshTransport(fs),
    );
    await connection.connect(devProfile, approve: (_, __) async => true);
    devService =
        RemoteFileService(connection: connection, serverId: devProfile.id);
    prodService =
        RemoteFileService(connection: connection, serverId: prodProfile.id);
  });

  tearDown(() async {
    await connection.dispose();
  });

  testWidgets('RemoteFilesPage lists entries and navigates into folder',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteFilesPage(
        profile: devProfile,
        service: devService,
        initialPath: '/var/docker',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('project'), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);

    // Tap into project folder
    await tester.tap(find.text('project'));
    await tester.pumpAndSettle();

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('.env'), findsOneWidget);
    expect(find.text('.. (Parent directory)'), findsOneWidget);
  });

  testWidgets('RemoteFilesPage shows PRODUCTION badge and exact delete path',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteFilesPage(
        profile: prodProfile,
        service: prodService,
        initialPath: '/var/docker/project',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTION'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);

    // Open popup menu for README.md
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    // Tap Delete
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTION DELETE'), findsOneWidget);
    expect(find.textContaining('CRITICAL: This is a PRODUCTION server'),
        findsOneWidget);
    expect(find.textContaining('/var/docker/project/'), findsOneWidget);
  });

  testWidgets('RemoteFilesPage toggles dotfiles', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteFilesPage(
        profile: devProfile,
        service: devService,
        initialPath: '/var/docker/project',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('.env'), findsOneWidget);

    // Toggle hide dotfiles
    await tester.tap(find.byTooltip('Hide dotfiles'));
    await tester.pumpAndSettle();

    expect(find.text('.env'), findsNothing);
    expect(find.text('README.md'), findsOneWidget);
  });

  testWidgets('FileViewerPage displays text and sensitive file warning',
      (tester) async {
    const entry = RemoteEntry(
      name: '.env',
      path: '/var/docker/project/.env',
      type: RemoteEntryType.file,
      size: 10,
    );

    await tester.pumpWidget(MaterialApp(
      home: FileViewerPage(
        profile: devProfile,
        service: devService,
        entry: entry,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('SECRET=123'), findsOneWidget);
    expect(find.textContaining('SENSITIVE FILE: Contains credentials'),
        findsOneWidget);
  });
}

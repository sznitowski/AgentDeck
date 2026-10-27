import 'dart:io';

import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/infrastructure/json_file_store.dart';
import 'package:agentdeck/features/agents/infrastructure/file_agent_instance_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File file;
  late FileAgentInstanceRepository repo;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('agentdeck_instances_test_');
    file = File('${tempDir.path}${Platform.pathSeparator}instances.json');
    repo = FileAgentInstanceRepository(JsonFileStore(file));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('CRUD operations and queries by server and project', () async {
    final now = DateTime.now().toUtc();
    final instance1 = AgentInstance(
      id: 'ad_agent_codex_proj1_0102',
      providerId: 'codex',
      serverId: 'srv1',
      projectId: 'proj1',
      tmuxSessionName: 'ad_agent_codex_proj1_0102',
      workingDirectory: '/var/docker/proj1',
      displayName: 'OpenAI Codex (proj1)',
      executionState: AgentExecutionState.running,
      observation: AgentObservation(
        state: AgentExecutionState.running,
        confidence: ObservationConfidence.confirmed,
        source: ObservationSource.tmuxSession,
        observedAt: now,
      ),
      startedAt: now,
      lastObservedAt: now,
    );

    final instance2 = AgentInstance(
      id: 'ad_agent_claude_proj2_0304',
      providerId: 'claude',
      serverId: 'srv1',
      projectId: 'proj2',
      tmuxSessionName: 'ad_agent_claude_proj2_0304',
      workingDirectory: '/var/docker/proj2',
      displayName: 'Claude Code (proj2)',
      executionState: AgentExecutionState.waitingUser,
      startedAt: now,
      lastObservedAt: now,
    );

    await repo.put(instance1);
    await repo.put(instance2);

    final all = await repo.all();
    expect(all.length, 2);

    final found1 = await repo.find('ad_agent_codex_proj1_0102');
    expect(found1?.providerId, 'codex');
    expect(found1?.executionState, AgentExecutionState.running);
    expect(found1?.observation?.confidence, ObservationConfidence.confirmed);

    final srv1Instances = await repo.forServer('srv1');
    expect(srv1Instances.length, 2);

    final proj1Instances = await repo.forProject('srv1', 'proj1');
    expect(proj1Instances.length, 1);
    expect(proj1Instances.first.id, 'ad_agent_codex_proj1_0102');

    // Update instance1 to finished
    final updated1 = instance1.copyWith(
      executionState: AgentExecutionState.finished,
      exitCode: 0,
    );
    await repo.put(updated1);

    final reloaded1 = await repo.find('ad_agent_codex_proj1_0102');
    expect(reloaded1?.executionState, AgentExecutionState.finished);
    expect(reloaded1?.exitCode, 0);

    // Delete instance2
    await repo.delete('ad_agent_claude_proj2_0304');
    expect(await repo.find('ad_agent_claude_proj2_0304'), isNull);
    expect((await repo.all()).length, 1);
  });
}

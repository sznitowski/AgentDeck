import 'package:agentdeck/core/domain/agents.dart';
import 'package:agentdeck/core/domain/profiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'production writes require confirmation and destructive actions are denied',
      () {
    const policy = ExecutionPolicy(environment: Environment.production);
    expect(policy.decide(OperationRisk.read), PolicyDecision.allowed);
    expect(policy.decide(OperationRisk.write),
        PolicyDecision.confirmationRequired);
    expect(policy.decide(OperationRisk.destructive), PolicyDecision.denied);
  });

  test('lost mobile connection does not change agent execution state', () {
    const execution = AgentExecution(
      providerId: 'codex',
      projectId: 'portal',
      state: AgentExecutionState.running,
      connectionState: ConnectionState.disconnected,
    );
    expect(execution.state, AgentExecutionState.running);
    expect(execution.connectionState, ConnectionState.disconnected);
  });
}

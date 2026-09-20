enum Environment { development, staging, production }

enum SshAuthenticationMethod { password, privateKey }

class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    required this.credentialId,
    this.passphraseCredentialId,
    this.port = 22,
    this.authenticationMethod = SshAuthenticationMethod.password,
    this.environment = Environment.development,
  });

  final String id;
  final String name;
  final String host;
  final String username;
  final int port;
  final SshAuthenticationMethod authenticationMethod;
  final Environment environment;
  final String credentialId;
  final String? passphraseCredentialId;
}

class ProjectProfile {
  const ProjectProfile({
    required this.id,
    required this.name,
    required this.serverId,
    required this.workingDirectory,
    required this.environment,
    required this.executionPolicy,
    this.repository,
    this.runtime,
    this.preferredAgentId,
    this.capabilities = const {},
  });

  final String id;
  final String name;
  final String serverId;
  final String workingDirectory;
  final String? repository;
  final Environment environment;
  final String? runtime;
  final String? preferredAgentId;
  final Set<String> capabilities;
  final ExecutionPolicy executionPolicy;
}

enum PolicyDecision { allowed, confirmationRequired, denied }

enum OperationRisk { read, write, destructive }

class ExecutionPolicy {
  const ExecutionPolicy({required this.environment});
  final Environment environment;

  PolicyDecision decide(OperationRisk risk) {
    if (risk == OperationRisk.destructive) return PolicyDecision.denied;
    if (environment == Environment.production && risk == OperationRisk.write) {
      return PolicyDecision.confirmationRequired;
    }
    return PolicyDecision.allowed;
  }
}

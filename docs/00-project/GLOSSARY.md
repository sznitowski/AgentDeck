# Glossary

- **ServerProfile:** non-secret identity and connection metadata for a server.
- **ProjectProfile:** project context tied to a server, path, environment, runtime, agent, and policy.
- **MobileConnection:** transient network connection from the device.
- **RemoteSession:** server-side shell context; may outlive MobileConnection through tmux.
- **RemoteProcess:** process running on Linux.
- **AgentExecution:** observed lifecycle of one coding-agent run; observation can become stale.
- **ExecutionPolicy:** local decision for an action: allow, confirm, or deny. It does not replace server authorization.

# AgentDeck agent instructions

Read `docs/02-roadmap/CURRENT_STAGE.md`, `docs/07-agent/CURRENT_CONTEXT.md`, and `docs/01-architecture/ARCHITECTURE.md` before changing code. Read `docs/04-security/` for security work. Follow the current milestone and its exit criteria; do not silently start the next milestone.

Do not store secrets in source, preferences, JSON, logs, or Git. Do not execute destructive remote actions, change security policies silently, add telemetry without approval, push, force push, or rewrite history. Keep iOS as the primary target and add only necessary dependencies. Never copy KAMMEL code without the documented component, license, source commit, iOS analysis, and user approval.

Plan, implement, test, verify, document, then hand off. Run relevant validation when tooling is available. Never report an unrun check as passed. Update CURRENT_STAGE after meaningful tasks, record architectural decisions, and update HANDOFF and SESSION_LOG at important session boundaries.

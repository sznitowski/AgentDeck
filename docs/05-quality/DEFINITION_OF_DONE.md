# Definition of done

A task is done when its scope is implemented, architecture respected, meaningful tests and static analysis are run, errors handled, security reviewed, documentation and CURRENT_STAGE updated, and HANDOFF/SESSION_LOG updated for significant work. No secrets, dead code, or untracked critical TODOs.

An unavailable required gate prevents milestone completion. A platform gate explicitly deferred by the milestone plan may remain PENDING_MACOS_VALIDATION, but the milestone must not claim iOS build or device validation. M0 uses this exception only for the native iOS runner and device checks.

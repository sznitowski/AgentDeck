# Quality gates

**A Architecture:** responsibilities separated, domain independent of Flutter/SSH implementation, documentation current.

**B Static:** flutter analyze succeeds. If tooling is absent, status is BLOCKED, never PASS.

**C Tests:** flutter test succeeds, including relevant unit/widget tests. If tooling is absent, status is BLOCKED.

**D Security:** sensitive changes review secrets, logs, network, storage, host verification, and command execution. Record findings.

**E Platform:** iOS-sensitive functionality requires macOS/Xcode and real device review where lifecycle matters. For M0 core bootstrap, this gate may remain PENDING_MACOS_VALIDATION while M0 closes; that does not certify an iOS runner, build, or device behavior. Later milestones must define whether this gate blocks their exit.

A milestone advances only after its applicable exit criteria pass. A deferred platform gate stays explicit and cannot be reported as PASS.

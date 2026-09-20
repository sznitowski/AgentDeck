# Production policy

Structured actions will return allowed, confirmationRequired, or denied. Production defaults to the stricter decision, displays exact server/project/action/arguments, and requires intentional confirmation for writes and service changes. `sudo`, root, recursive deletion, Docker destructive operations, database writes, Git reset, and force push need separate review. No destructive operation is implemented in M0. Local policy is advisory for unrestricted SSH; server permissions are the enforcement boundary.

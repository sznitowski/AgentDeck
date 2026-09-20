# Test strategy

M0 unit tests cover domain invariants and policy decisions; a widget test covers shell navigation. M1 adds host verification, authentication failures, lifecycle, and reconnect tests with isolated fixtures. Later milestones add transport integration and device tests. Do not write tests that only repeat constructors or mock the implementation without asserting behavior. Record exact commands and results in CURRENT_STAGE/HANDOFF.

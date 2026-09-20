# Modules

- `app/`: composition and bottom navigation.
- `core/domain/`: immutable project/server data, independent states, policy and transport contracts.
- `features/home|servers|projects|agents|settings/`: M0 screens with labeled mock information.
- `shared/`: shared UI only when repetition appears.

Future infrastructure adapters will be added under the owning feature. Avoid a global service locator and avoid putting SSH clients into Flutter widgets.

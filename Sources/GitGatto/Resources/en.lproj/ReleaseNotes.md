## Added

- Expanded the developer tool catalog to 99 tools with bundled brand icons.
- Added separate install and upgrade queues with three concurrent lanes, queue positions, per-tool cancellation, multi-selection, select all, and batch upgrades.
- Added complete release goals and natural-language custom goal conditions.

## Improved

- After an install or upgrade, Agent completes current-user setup, component registration, environment migration, and version verification.
- Formulae without a compatible bottle may use Homebrew's normal source build and declared build dependencies.

## Fixed

- Homebrew upgrades now run through GitGatto's controlled execution path so Homebrew's build sandbox is not nested inside the Agent sandbox.
- Concurrent upgrade lanes serialize Homebrew mutations to prevent Cellar lock conflicts across shared dependencies.
- Docker Compose registers through the current user's CLI plug-in directory without reading or changing Docker credential configuration; incomplete setup remains action required.

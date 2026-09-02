## Added

- Expanded the developer tool catalog to 99 tools with bundled brand icons.
- Added separate install and upgrade queues with three concurrent lanes, queue positions, per-tool cancellation, multi-selection, select all, and batch upgrades.
- Added complete release goals and natural-language custom goal conditions.
- Added Disaster Recovery to monitor managed local repositories, save uncommitted work on a schedule, capture major changes immediately, and restore a recovery point to a new repository copy.
- Added backup management with storage usage, manual recovery points, and actions to reveal or delete one backup, one repository's backups, or all backups.

## Improved

- After an install or upgrade, Agent completes current-user setup, component registration, environment migration, and version verification.
- Formulae without a compatible bottle may use Homebrew's normal source build and declared build dependencies.
- Each repository retains no more than three rolling recovery points. Identical content is not written again, and changing the backup location migrates and verifies existing recovery points.

## Fixed

- Keep one app mark visible when the sidebar is collapsed without restoring the duplicated compact logo.
- Homebrew upgrades now run through GitGatto's controlled execution path so Homebrew's build sandbox is not nested inside the Agent sandbox.
- Concurrent upgrade lanes serialize Homebrew mutations to prevent Cellar lock conflicts across shared dependencies.
- Docker Compose registers through the current user's CLI plug-in directory without reading or changing Docker credential configuration; incomplete setup remains action required.
- Agent installations now share a controlled write scope; Homebrew package installs use the dedicated package runner and other Agent CLIs cannot write outside that scope.
- Account sign-in and token state no longer block a completed tool installation.

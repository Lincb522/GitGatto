## Added

- Added unified monitoring states for the working tree, remote synchronization, repository protection, GitHub Actions, and project goals.
- Added a menu bar monitor for the selected repository, live channel states, and a year of project activity, with direct access to the main app.
- Added settings for the monitoring engine, the menu bar item, and each of the five monitoring channels.
- Added a daily activity grid combining commits and monitored local changes.

## Fixed

- Repository protection now measures file and line changes made after the recovery baseline, avoiding alerts caused by pre-existing uncommitted work and listing the paths that crossed the configured threshold.
- Agent tool installs and upgrades are reported as successful only after the executable, version command, and update state pass local verification. Failed verification keeps the original output and labels it as unverified.

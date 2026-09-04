## Fixed

- Multi-repository sync, the GitHub inbox, and Issues no longer remain indefinitely in a loading state when concurrent Git and GitHub CLI commands wait on each other.
- Switching collaboration pages or repositories now cancels superseded requests and restores the correct loading state.

## Improved

- Repository status is loaded only after opening Multi-Repository Sync, so background scans no longer block other GitHub pages.

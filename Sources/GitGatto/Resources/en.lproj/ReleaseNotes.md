## Improved

- The menu bar monitor can now switch independently between all repositories and an individual repository, including aggregated yearly activity for the selected scope.
- Interface icons now use Reicon vector assets. Recovery, lost-change recovery, release-readiness, menu bar monitoring, and related states are included with consistent Retina sizing.

## Fixed

- Staging now verifies that a stale `.git/index.lock` is not in use before removing it and retrying. Fresh or active locks remain untouched, reducing `GG-GIT-STAGE-128` failures.
- Repository protection rebuilds a missing or migrated baseline instead of reporting repository damage, and concurrent checks create only one baseline.
- Repeated monitoring configuration and menu bar callbacks no longer trigger redundant workspace refreshes or replace valid sync state with cancellation errors.

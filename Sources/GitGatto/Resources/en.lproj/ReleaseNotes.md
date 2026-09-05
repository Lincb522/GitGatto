## Added

- Added the Luminous Stage theme, with glass surfaces and subdued ambient light in the workspace, Settings, and About windows, in light and dark appearances.
- Change Center can organize files or diff hunks into separate commits, creating a recovery point before applying the plan.
- Code Provenance traces a file line to its commit and related pull requests, issues, reviews, and checks.
- Reproduction Capsules export patches, untracked files, the base commit, failure output, and tool versions to a `.gatto` file, then validate and restore it in a separate worktree.
- External Agent Activity records Git reference and file-state changes alongside agent processes working in the repository and their association strength.

## Improved

- Console uses a tool rail, repository directory, workspace tabs, and compact file and diff views.
- Emerald places the file list and commit controls on the right, leaving a continuous surface for reading diffs.
- Folio uses an integrated grouped sidebar, horizontal file selection, and a separate commit panel. Collapsing the sidebar retains its icon navigation.
- The repository switcher supports search and activity-based groups, keeps the current repository visible, and allows older groups to collapse.
- Theme previews in Settings reflect their layouts. Secondary text has higher contrast, and action controls accommodate longer labels in narrow windows.
- Update failures retain underlying errors and recovery suggestions, with a specific message when the update helper times out during startup.

## Added

- Initialize a local Git repository from a folder and create a public or private GitHub repository, using Agent-filled settings or manual setup.
- Create or connect a remote for an existing local repository and configure branch tracking through Agent or manual setup. Uploading existing commits requires confirmation.
- Switch GitHub repositories between public and private from project or remote details, with permission checks and confirmation.
- Added repository creation, Agent setup and manual setup to command search, plus a File actions menu in file details.

## Improved

- Added text to common repository controls, including adding repositories, staging, renaming branches, commit actions, deleting stashes, removing worktrees and refreshing. Per-file staging remains visible without hovering.
- Action groups adapt to available space while retaining each theme. New controls include translations for supported languages.
- Repository setup refreshes branch and remote information without clearing the current page or commit draft. Agent naming retries when a repository name is already taken.

## Fixed

- Fixed some staging controls remaining clickable while Agent was editing the current repository, even though their actions could not run.
- Fixed loading placeholders widening narrow commit panels, clipped worktree Agent mode labels and an unrelated creation button in the recovery tab.
- Change-intent, file-provenance and related repository analysis errors now use shared explanations and recovery suggestions, with sensitive diagnostic content redacted.

## Added

- Custom OpenAI-compatible APIs and a DeepSeek API preset, with separate project and translation settings and keys stored in Keychain. Fetch model lists, check endpoint capabilities and stream responses.
- DeepSeek Harness (dsh), Cursor Agent, GitHub Copilot CLI and Qwen Code integrations. API Agents can read projects, run commands, make controlled file changes and handle tool installation or upgrades.
- Pin commands, browse recently used actions and search in the current interface language.
- Stage or unstage individual diff lines and hunks, or send the selection to Agent-assisted commit planning.
- Create goals from current changes, Issues, PRs or failed GitHub checks, retaining their context. Goals can run an existing project verification command before staging changes.
- Local drafts for Issue and PR replies and reviews, restored when switching projects or reopening the app. The inbox groups mentions, reviews and failed checks that need attention.
- Navigate from a file or line to its commit and code provenance. Preview differences before restoring a historical file version.
- Inspect recovery-point contents, compare files and export selected files to a new directory.
- Six development tool bundles: Web, Python, Swift, Rust/C++, Docker and SQL/Redis, with installation scope and configuration receipts.
- Per-repository automatic, active and low-frequency monitoring policies in Settings.

## Improved

- Commit planning keeps the change scope, commit preview and progress together. Refreshing, retrying and replanning retain the selection until you explicitly switch to all changes.
- Branch switching previews uncommitted files and can save a work scene first. Commit drafts, Agent input and selected files are retained per repository and branch.
- Main-repository and worktree Agent tasks run independently. Return after switching repositories to check progress, read results or cancel a task.
- Resolve conflicts block by block using current, incoming or both sides, then edit, save and continue the merge. Regression investigations can use an existing project command or manual checks.
- Installation and upgrade records survive reopening. Interrupted tasks check what is installed before continuing configuration; multi-repository sync can retry failed items only.
- Shared original, translation, retry and cancel controls, with better short-text and mixed-language detection. Translation checks preserve code, links, paths and numbers, keeping the original on failure.
- Fewer repeated scans during continuous saves, atomic writes and repository switching. Background monitoring adapts to power state and reuses unchanged history and activity data.
- Settings retain edits as drafts and refresh only affected services after saving. Error details can be expanded, with direct retry or recovery actions for common failures.
- The update center distinguishes checking, downloading, verification and installation errors, with a redacted diagnostic copy action and a link to release downloads.
- Updated feature guides, interface text in all 11 languages and missing icons, with layout adjustments for narrow windows, long labels and right-to-left languages.

## Fixed

- Background refreshes and completed sends no longer overwrite newer drafts; cancelled tasks cannot overwrite a newer task's state.
- Selected commits no longer include unrelated staged content or lose their selection during replanning. Changed content requires a fresh selection.
- Translation retries retain the requested target language, and stale requests cannot replace newer results.
- Pressing Return in the command palette no longer runs a different action when recent-use ordering changes.
- Branch switching and work-scene restoration refuse to overwrite same-named ignored files. Failed restoration retains the saved scene and error details.

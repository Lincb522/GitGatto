## Added

- Extended disaster-recovery protection to every managed local repository, including changes made by external Agents, Git CLIs, terminals, and scripts.
- Added rolling pre-operation recovery baselines that detect repository deletion, deleted files, lost uncommitted work, and unexpected branch, HEAD, or index changes.
- Added incident cards to Disaster Recovery with original errors, affected paths, repository state, and direct access to the preserved recovery point.

## Improved

- Recovery points now use atomic staging, commit markers, content verification, and filesystem synchronization. Only complete transactions survive an interrupted exit.
- Each repository retains no more than three rolling recovery points. A high-risk event freezes the latest recovery point so later automatic backups cannot replace the evidence.
- GitGatto's built-in Agent must create a recovery point before writing and audits deletions, overwritten work, and Git state afterward.

## Fixed

- Added a lightweight repository watchdog so delayed FSEvents cannot leave staging state or disaster-recovery incidents stale under load.
- Homebrew execution timeouts now begin after the process actually starts instead of counting scheduler wait time.

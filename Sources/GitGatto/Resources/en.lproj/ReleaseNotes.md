## Improved

- The application center loads content for the active page and batches tool scan results. Download and installation progress no longer repeatedly refresh the entire tool list.
- Reduced unrelated refreshes in Disaster Recovery. Multiple repository alerts remain accessible in a scrollable list.

## Fixed

- Backup creation, restoration, and cleanup no longer compete over the same backup. Directory migration blocks conflicting operations. Each repository still retains at most three backups.
- Failed or cancelled restores clean up temporary directories so incomplete copies do not block retries. Backup storage totals now include hidden files.
- Automatic backups before grouped commits use the updated backup directory and appear in Disaster Recovery.
- Installations with unfinished configuration show the remaining action instead of reporting success. Rescanning preserves failure details and retry actions.
- Results from old tasks no longer overwrite progress or status after rapid cancellation, retry, pause, or resume.
- Repeated scrolling no longer requests the same application page twice. Switching projects no longer displays results from the previous project.
- Replacing an installed application checks its bundle identifier and preserves the existing application if copying the new version fails.

## Added

- Added quick installation to the app catalog. DMG and ZIP releases use the native installer, while Agent inspects and installs other release artifacts with visible phase progress.
- Added a 63-item developer tool catalog with local installation detection, Homebrew upgrade checks, and Agent installation or exact-package upgrades.

## Improved

- Extended text, Markdown, and HTML translation runs to three minutes and gave each HTML batch its own timeout.
- Scans developer tools in bounded batches and detects Homebrew keg-only executable paths.
- Updated Sparkle to 2.9.6 and preserved underlying update failures, error domains, and error codes.

## Fixed

- Removed the compatibility path that force-restarted Sparkle's progress process and could interrupt the installation connection after download.

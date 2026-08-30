## Added

- App catalog details now provide dedicated overview and version download pages with the project logo, structured descriptions, features, screenshots, developer, release, and package information.

## Improved

- App catalog search supports exact repository names, developers, and fuzzy matches without excluding low-star projects. Results appear progressively as release assets are discovered, and recent releases are cached.
- Local repository status now reacts to file changes and coalesces rapid updates. UI and language icon caches are bounded to reduce idle resource use.

## Fixed

- Fixed a case where Sparkle's update progress interface could fail to launch while downloading an update on macOS 26.

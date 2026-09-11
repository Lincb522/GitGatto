## Added

- A “Continue monitoring after quitting” setting. When enabled, an independent background helper monitors repositories, records activity and creates recovery points according to your existing protection settings after the main app quits.
- The background menu bar panel can show all repositories or a single repository and follows the main app’s theme. Monitoring and the menu bar remain available while the main app is open.
- Separate controls for menu bar visibility and monitoring after quitting. Background monitoring is off by default; Settings provides a link to system approval when required.

## Fixed

- Fixed a crash that could occur when sending input to an external command that had already exited. Failed commands retain their error output.

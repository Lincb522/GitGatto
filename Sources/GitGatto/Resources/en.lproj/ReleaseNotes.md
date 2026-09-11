## Fixed

- Fixed page reinitialization that caused stuttering when switching themes and reloaded content when switching between light and dark appearances.
- Fixed missing dark-mode images in READMEs. Color changes now preserve the reading position and expanded sections.
- Fixed raw image tags appearing in issue descriptions and replies. Images fit the available width and can be clicked to open the original.
- Fixed author avatars appearing as application icons in the catalog and details. Applications now use their own icons, with a default icon when none is available.
- Fixed some README and application-description translations being incorrectly rejected as incomplete. Headings, code formatting, links and numbers are preserved; content that fails validation is retried once.

## Improved

- Application icons load on demand, and the list and details reuse the same result to avoid duplicate requests.

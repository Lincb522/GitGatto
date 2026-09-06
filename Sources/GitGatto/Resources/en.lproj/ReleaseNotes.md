## Added

- Search goals and filter active goals or history.

## Improved

- Create goals on a dedicated page with fields for the selected goal type and a step preview before confirmation.
- Goal details focus on the current step, next action, and failure reason, with expandable step records. Narrow windows switch between the list and details.
- Commit messages are saved explicitly instead of after each keystroke.

## Fixed

- Background refreshes no longer overwrite a saved commit message or a cancelled goal, or reorder the list by refresh time.
- Failed save and cancel operations preserve the previous state and show the error. Completed and cancelled goals can no longer run further actions.
- Custom plans must be regenerated if the repository, branch, or commit changes after planning.

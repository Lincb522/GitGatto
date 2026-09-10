## Improved

- Batch monitoring refreshes and ignore-rule checks during continuous saves and builds to reduce repeated Git commands.
- Reuse live status for activity records and unchanged history for commit statistics; multi-repository monitoring refreshes only repositories with changes.

## Fixed

- Fixed backup comparison copies repeatedly triggering their own checks and consuming CPU.
- Fixed background status reads updating the Git index and triggering another monitoring refresh.
- Fixed continuous changes repeatedly cancelling and restarting scans, adding overhead and delaying status updates.

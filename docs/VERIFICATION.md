# Syllavane 0.11 verification

Installed and reopened on October 13, 2026. Settings visibly confirmed 0.11.0, all five existing projects remained available, Bhoomi opened, and local models became ready. No draft was accepted or rewritten during normal-library UI verification.

## Improvements
- Rebuilds preserve the current draft until a replacement succeeds; offline startup, cancellation, failed validation, and writer failure retain it.
- Failed saves block draft discard and new-chapter creation.
- Pending Keep/Undo decisions persist across relaunch.
- Keep change and acceptance of a revised draft save approved rewrite examples. Failed requests and undone rewrites do not teach the project.
- Approved AI rewrites guide technique separately from user-written corrections and cannot establish character facts. Examples are project-specific, excluded from earlier story moments, and removable in What I’ve Learned.
- Saved drafts with detected intent/development problems offer a direct rebuild action.

## Verification
77 ordinary regression checks passed; 2 opt-in installed-model tests skipped in that run. A new local-model rewrite/approval/persistence test passed separately, with the sample revision completing in 2.29 seconds. Release build, packaging, and installed app signature verification passed. New regression cases cover rebuild failure and cancellation, offline and failed-save preservation, approval and undo across reopening, example time boundaries, serialization, and saved psychological drift.

## Limits
The measured latency is one example. Deterministic warnings and model validation cannot detect every unsupported inference. Context personalization uses approved examples; model weights are not retrained. Live dictation and PDF behavior were not revalidated in this update. Apple signing/notarization remains deferred.

# Architecture

Syllavane is a native SwiftUI/AppKit application backed by a reusable Swift core. It has no separate cloud backend.

## Draft pipeline

```text
Typed or spoken author idea
  → project and story context
  → hybrid lexical/embedding retrieval
  → local writer
  → deterministic checks and model meaning check
  → reviewable pending draft
  → author edits, approval, or revision
  → accepted manuscript
```

A failed whole-scene expansion can retry with tighter constraints, then develop individual story beats. Candidate sentences are filtered for unsupported facts and repetition. This fallback is intentionally constrained and may still produce weak prose. Unsuccessful expansion preserves narration; it does not present copied notes as completed ghostwriting.

## Context and authority

Project records contain writing format, sources, characters, relationships, chapters, scenes, preferences, and learning examples. Character developments have a starting moment. Retrieval excludes later story moments. Style samples supply technique rather than plot.

Human-written corrections and approved AI rewrites are represented separately. Author corrections can supply factual evidence; approved rewrites supply technique. Pending rewrite comparisons are stored with the scene so Keep/Undo survives reopening. No fine-tuning runs after editing.

## Persistence and cancellation

SQLite provides project storage, revision checkpoints, full-text retrieval, and content-addressed embedding caches. Saves use transactions, WAL, and synchronous commits. Daily backups and JSON project exports support recovery.

Operations carry identities so cancelled or stale results cannot overwrite a later operation. AI output must be a complete successful response. Rebuilding retains the old draft until a replacement succeeds; save failures block destructive navigation and draft removal. Interrupted voice capture stores atomic audio checkpoints with project and scene destinations.

## Runtimes

The app launches bundled llama.cpp writer/embedding servers and a patched whisper.cpp speech server. They bind to loopback with per-launch authentication. The runtime sources and model artifacts are pinned in Resources manifests. Model files are checksum-verified; changed files are verified again.

## PDF export

PDF layout lives in FolioCore; PDFKit displays the resulting document. Rendering runs asynchronously and discards stale previews. Export saves the displayed preview data. Typography settings persist within the project.

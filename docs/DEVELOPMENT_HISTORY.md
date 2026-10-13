# Development history

Historical implementation notes from versions 0.4–0.11. Descriptions and measurements refer to the version in their section; see the main README for the current workflow.

# Syllavane

Version 0.4 · native local preview.

A native, matte-black Mac writing companion. SwiftUI/AppKit interface; local Qwen3-4B-Instruct-2507 writing, MiniLM retrieval, and Whisper Small English dictation. No account or hosted AI service is required.

## Run

Open `dist/Folio.app`. On this Mac, the verified models are already installed. On a new Mac, open Settings and choose **Download & start**. Active models require about 3.03 GB; the application itself is approximately 35 MB. Runtime RAM is additional. This build targets Apple Silicon and macOS 14 or later; it has been tested on the development Mac, not every supported OS release.

## Write

1. Start in the project library. Create and name a Book, Blog, X post, or Technical paper project. The visible project list and New project button remain available in the workspace. Toggle the left sidebar from the toolbar or Option–Command–S. Each project keeps its own context and voice.
   Import or paste writing through Sources. Every new source asks **Continue from here**, **Reference material**, or **My writing style**. Continuation preserves the source text in the manuscript and opens a writing area after it; it also learns the voice. Existing sources have a Continue writing action. Each source gets local, editable observations about scene construction, inner experience, restraint, rhythm, dialogue, and imagery, supported by exact source quotes. Only sources marked as style samples guide the writing voice; references supply story context. Measurements appear immediately; analysis waits for local models. Analysis is an interpretation, not a guarantee of fidelity.
2. Tell the story naturally in the narration box, or click the microphone. Dictation currently supports English. It shows periodic previews, transcribes successive portions locally, and preserves the final transcript in your narration when stopped.
3. Choose **Write this moment**. Highlight a draft passage and type or dictate feedback to revise that passage; leave nothing selected to revise the whole draft. You can also edit directly. Unaccepted drafts are saved locally.
4. Accept a draft to add it to the continuous manuscript. Keep narrating in the next blank narration box. No manual scene setup is required.
5. Choose **Finish chapter here** when the current chapter feels complete. Automatic chapter suggestions are deliberately not implemented in this version; chapter boundaries remain under the writer's control.
6. Story map shows character connections and moment tiles with character badges. Connections are extracted from the author's narration, require a matching evidence quote, and remain marked as inferred until corrected. They are not guaranteed facts. Edit or remove them in the map.

Characters have a full workspace tab with a searchable cast and focused characteristic cards. Leaving a character saves its changes. Character profiles belong to their book and support aliases/corrected spellings, portraits, 17 optional characteristic categories, custom cards, additional notes, and editable developments effective from a particular moment. Each card includes a question to help articulate the character. Structured traits, active developments, source guides, and retrieved excerpts accompany generation; these are persisted project data, not a single static persona prompt. Saved aliases are resolved deterministically; uncertain aliases are not silently remapped. Typing `/character Name` and choosing Run typed command opens character search. Spoken structural commands are opt-in in the narration menu. Long dictation is processed in portions without the previous three-minute cutoff; microphone accuracy and uninterrupted long-session behavior still require testing with the user's own setup.

## Data and recovery

`~/Library/Application Support/Folio/library.sqlite` stores projects and revisions using SQLite WAL and full synchronous commits. Daily backups are created at application launch under `Backups`. Export manuscript creates continuous Markdown chapters; Export project backup creates a portable JSON project. Originals imported as sources are never changed. Draft acceptance, character edits, and restore operations save checkpoints. Restore preserves a checkpoint of the current project first.

Models and their pinned checksums are in `Resources/models.json`. Downloads verify SHA-256 before installation. Engine logs are local. Engines bind to loopback and require a per-launch token; the speech server is patched to disable unrelated routes. There is no telemetry, cloud sync, cloud fallback, or Apple Intelligence dependency.

## Build and verify

Requirements: Apple Silicon Mac, Xcode command line tools with Swift 6+, CMake, Python 3, and internet for the initial source/model downloads.

```sh
./scripts/build.sh
python3 scripts/prepare-models.py
python3 scripts/smoke-test.py
python3 scripts/memory-smoke.py
python3 scripts/expansion-smoke.py
open dist/Syllavane.app
```

The build downloads checksum-pinned upstream engine archives, applies the speech authentication patch, compiles the engines, runs unit tests, builds the Swift app, generates its icon, and ad-hoc signs the bundle. Apple Developer signing, notarization, and distribution are intentionally deferred. `scripts/package.py` rejects accidental Homebrew runtime dependencies.

Tests cover persistence/backup restoration, alias ambiguity, character timelines, future-scene exclusion, chapter commands, unaccepted-draft persistence, evidence-bound memory extraction, and selected-range rewriting. Engine smoke tests exercise real streaming output, embeddings, and a prerecorded English speech fixture. These are functional checks, not proof of literary fidelity or perfect dictation. The local writer can ignore nuances, invent details, or return weak prose; review drafts before acceptance.

## Version 0.4 verification

26 core tests pass, including rejection of copied notes, genuine expansion detection, preservation of temporal anchors, figurative language versus invented scenery, and character-behavior ownership. Real-model tests now require developed prose rather than allowing a conservative copy edit to count as success. The Joseph/George test produced multiple paragraphs while retaining the uncertainty, days of silence, and mother's anniversary. Original notes are not substituted as a finished draft.

The local writer is now Qwen3-4B-Instruct-2507 Q4_K_M, about 2.50 GB. It was selected after the 0.6B, 0.8B, and 2B candidates failed the expansion/faithfulness tests. Active model files total about 3.03 GB; application size and runtime memory are additional. The previous 0.6B file may remain cached for rollback and adds about 0.64 GB to disk usage. No cloud inference is used.

Generation uses recent author narration as factual memory, recent accepted prose for continuity, current character traits and relationships, and up to 24 shortlisted passages for local semantic retrieval. Style examples contribute writing technique rather than plot. A draft must add substantial new prose and retain the author’s events. When a whole-scene attempt drifts or simply echoes notes, the recovery path develops the chronological beats separately, filters unsupported actions/settings and repeated sentences, and assembles the surviving prose. Copy editing is used only to normalize each event anchor. The final result must still pass the expansion gate. Failures retain the narration and show an error; they do not silently return it as a draft.

These checks reduce drift but do not prove exact literary fidelity or catch every contradiction. The beat recovery path emphasizes inner experience and can be more constrained than unconstrained fiction generation. Review and refine the draft before accepting it.

Blog, X, and technical-paper modes are basic drafting workspaces. X uses a 280-character target and counter, not a platform publishing integration. Technical mode requests evidence and forbids invented citations/data; evidence is not externally fact-checked. There are no specialized citation managers, peer-review tools, or publishing integrations.

Dictation suppresses non-speech tokens, filters common sound annotations and optional filler sounds, and checks energy in each pending audio portion. It does not identify the intended speaker or reliably reject all breathing/background speech. No extra model downloads are required.

## Current limits

- English dictation only; no speaker diarization or audio file import UI.
- Models can produce superficial style observations or invent details. Verifiable source quotes do not prove the interpretation is correct. Expansion checks can reject valid prose; all drafts still need review.
- Inferred relationship meaning still needs human review even when its evidence is exact.
- No automatic chapter-boundary suggestions, chapter reordering, or DOCX manuscript export yet.
- Narration memory is refreshed after dictation/drafting, or manually via Story map → Read narration for the selected moment.
- Speech chunks overlap slightly; overlap matching can miss recognition variations. Audio is retained in memory for retry until the next recording or app exit.
- No Developer ID signing/notarization, full accessibility audit, or multi-machine testing yet. This is a working local preview, not a certified production release.

Application source: MIT. Model and engine licenses: `Resources/THIRD_PARTY.md` and `Resources/Licenses`.

## Version 0.5 interface

Display name is Syllavane. Internal bundle identity and Folio data directory remain stable to preserve existing projects, models and permissions. Highlighted text opens a compact native popover with a Rewrite menu, custom direction and optional project preference. The inspector no longer contains the large adjustment list and is hidden by default. Whole-draft adjustments remain beside draft feedback. Selected revisions receive the source-backed voice guidance and style example. Saved directions also apply during beat recovery. The model itself is not retrained from manual edits.

## Version 0.6 navigation and book preview

Projects open directly into writing. Chapters are nested beneath the selected project in the sidebar. The five workspace tabs are replaced by one project menu. Characters, sources, voice, story map, history and settings remain available there. Draft actions are grouped under Draft options.

A selected-passage revision shows elapsed time during generation and a measured completion time after validation. The replacement receives one subdued 1.6-second highlight and scrolls into view. The timed native check took 8.1 seconds on this Mac; this is one observation, not a performance guarantee.

Preview opens a local PDF viewer with 6-by-9-inch pages, serif text, chapter openings, running title and page numbers. Save PDF exports the displayed document. The chapter picker supports the whole manuscript or one chapter. An explicit toggle controls unaccepted drafts; accepted-only exports omit those drafts. Current preview includes a simple title page, without cover design, publishing metadata, a table of contents or advanced widow/orphan control.

27 core tests pass, including long-chapter PDF pagination, preservation of chapter endings, selected-chapter export and exclusion of unaccepted drafts. Native PDF preview and saving were exercised in Bhoomi.

## Version 0.7 author learning

Manual changes in both draft and manuscript editors are stored as bounded before/after examples, coalescing consecutive typing and removing a reverted example. Up to 80 examples stay within the project. The two most relevant examples, with the changed region rather than only the opening paragraph, guide later generation and revisions. Voice & style exposes examples with a Forget control. This is retrieval-based adaptation, not model weight training or a guarantee that every edit improves prose. AI-only revisions are not stored as human examples. Author rewrite directions are retained for the current story moment; explicitly remembered preferences remain project-wide. Original narration supplies character evidence through the current moment, avoiding future-scene leakage. Named author corrections appear alongside that evidence. Importing prior writing still uses source analysis and examples; reference sources do not become voice samples.

Revision prompts now use bounded relevant context, explicit prompt caching and a compact structured meaning check. A native Tone down check took 4.2 seconds versus the prior 8.1-second observation, with unaffected paragraphs unchanged. A 2.4-second highlight and fading outline identify the replaced region. Performance depends on passage length, context and machine load. Additional checks flag some unsupported certainty, but do not prove fidelity or psychological correctness.

Character face upload is visible as Upload face. No local image-generation model is bundled. The knowledge map shows named, directed relationships with author narration evidence and scene participation.

PDF formatting persists per project. Classic defaults to Baskerville, 12 point, first-line indentation and zero additional paragraph gap; Modern and Airy offer alternatives. Font, size, paragraph spacing, line gap, margins and indent are configurable. Chapter headings are centered; opening paragraphs have no first-line indent. Full typographic publishing features such as running-head parity, widow/orphan control, cover generation and font licensing/export preflight are not implemented.

31 tests pass, including author-edit persistence, reversal/coalescing, project isolation, future-scene exclusion, late-paragraph correction retrieval, and PDF typography presets. Native author-learning review, character evidence, theme switching and measured paragraph revision were exercised. The test edit in the example project was reverted and its learning example removed.


## Version 0.8 — voice-first writing

Speak is the primary action. Stopping narration creates a draft by default; the composer menu can switch to narration-only. With a draft open, Speak changes revises the selection or whole draft. Typed revision controls collapse out of the writing space. Sources, characters, and memory remain project-scoped.

- Focus mode: Shift-Command-L; global writing search: Shift-Command-F; PDF preview: Command-P. Search includes narration, pending and accepted prose, character names/details, and sources.
- New projects need only a format; the working title is optional.
- AI revisions have Before/After comparison, Keep, and guarded Undo. History checkpoints retain earlier writing; ordinary text editing uses native undo.
- What I’ve learned exposes editable voice/premise, source analysis, remembered examples, directions, and removable preferences.
- Partial recognized transcripts are saved locally during dictation and offered for recovery after restart. Untranscribed audio between recognition updates is not crash-recovered. Recovery is project/scene-specific and does not execute spoken commands.
- Books retain the 6×9 classic layout; other formats use A4 without a separate cover. The exported PDF is the preview data.

Validation: 33 core tests pass; release build and signature verified. Native app checks covered global search, focus mode, project creation sheet, PDF preview, memory removal, and a 3.2-second sample rewrite followed by exact Undo. This is a measured example, not a latency guarantee. Live microphone accuracy, accessibility with VoiceOver, and interrupted-device recovery still need hands-on testing.

## Version 0.9 — a conversation about your writing

Speak is the primary action: describe an idea, stop, and review the draft. A send arrow appears only when there is typed input. Revision dictation is explicitly selected within the draft controls. Continuing while a draft is pending creates a new moment and preserves the earlier draft for review.

The chapter timeline stores narration, change requests, draft versions, acceptance and undo events. Earlier moments can be reopened. New history persists in project backups; legacy projects show their existing narration/drafts without inventing past interactions. Chapter completion requires resolving earlier pending drafts.

The large decorative heading is replaced by a compact chapter bar. The draft editor grows with its content, and prose spacing is tighter. Native QA confirmed request → revised draft ordering and undo (3.3 seconds for the sample revision). 34 core tests pass, including conversation persistence. This remains a developing product: story fidelity and live dictation reliability need broader validation.

## Version 0.10 — reliability hardening

The release adds isolated application workflow tests and HTTP transport fault tests. Unsent narration and feedback persist per moment; a failed save prevents navigation; late or cancelled model replies cannot overwrite another project. Empty cancelled drafts do not become invisible pending drafts. Retry replaces a transcription instead of appending it twice. Native text editors lock while a model operation owns the draft.

Generation accepts only a successful, complete SSE response. Empty, malformed, errored, interrupted, or token-limited output is withheld. Writing modes now use their own generation guidance. Validation rejects unsupported scene changes, unprovided memory loss and reality doubts, and fallback narration is constrained to the viewpoint character. Style samples remain examples of technique, outside story facts. These checks reduce errors; they cannot prove semantic fidelity for arbitrary prose.

Voice capture checkpoints audio plus project/moment destination atomically every five seconds. Sleep pauses capture, device changes finish it, and a failed transcription offers recovery. Recovery does not run spoken commands. Successful capture and cancellation clear the checkpoint. An interrupted session can lose audio after the latest checkpoint. Recordings are capped at twenty minutes; large notes remain saved if they exceed the local drafting limit.

Model files receive checksum verification, cached by expected hash, size, and modification time. Changed files are checked again. Search falls back to lexical retrieval when embeddings fail. Cache keys include the embedding model hash. The library checks SQLite integrity and project identity consistency. Backup recovery imports copies; corrupted original library files are preserved.

PDF rendering runs away from the interface thread, cancels stale previews, and saves only the current finished preview. Invalid imported page settings are rejected. Settings scroll on smaller screens; secondary text has stronger contrast.

Verification commands:

```sh
swift test
swift test --sanitize=address
FOLIO_RUN_MODEL_TESTS=1 swift test --filter LocalModelIntegrationTests
python3 scripts/speech-reliability.py
python3 scripts/smoke-test.py
codesign --verify --deep --strict dist/Syllavane.app
```

Model integration tests opt in because they load installed local weights; the ordinary suite explicitly skips that test. Integration fixtures use temporary libraries. Speech fixtures use synthesized speech and cover names, story narration, revision instructions, two controlled white-noise levels (20 and 10 dB SNR), authentication, and malformed requests. They do not establish accuracy for accents or noisy microphones. The app remains ad-hoc signed; Apple distribution signing and notarization are deferred.

## Version 0.11 — recoverable drafts and approved learning

Rebuilding keeps the existing pending draft until a replacement succeeds. Offline startup, model failure, failed validation, and cancellation preserve the old draft. Failed saves prevent discarding drafts and creating chapters. Saved drafts that fail the deterministic intent/development checks show a direct rebuild action.

Keep change stores an approved before/after rewrite and its request as project-specific style memory. Accepting a revised draft also approves the rewrite. Generated examples are kept separate from author-written corrections and cannot establish character facts. Undo clears the pending example; unapproved and failed requests do not become remembered directions. Pending Keep/Undo decisions survive app reopening. Approved examples are reviewable and removable in What I’ve Learned and are excluded from earlier story moments.

The ordinary suite now passes 77 regression checks, with two opt-in local-model tests skipped. The new installed-writer revision/memory test passed separately: one paragraph revision took 2.29 seconds, and the approved example survived reopening. This is a measured example, not a general speed guarantee. These changes improve recovery and context personalization; they do not establish universal writing fidelity or retrain model weights.

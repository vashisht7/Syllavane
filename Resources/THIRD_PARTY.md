# Open-source components

- Folio application: MIT (see LICENSE).
- llama.cpp v0.6.0: MIT. Source and pinned commit: Resources/engines.json.
- whisper.cpp v1.9.5: MIT, with a local authentication patch in scripts/patch-whisper.py.
- Qwen3-4B-Instruct-2507 Q4_K_M: Apache-2.0. Original model: https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507. Quantized by Bartowski: https://huggingface.co/bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF. Revision and SHA-256 are pinned in models.json.
- all-MiniLM-L6-v2 F16 GGUF: Apache-2.0. Converted by Second State from sentence-transformers/all-MiniLM-L6-v2; revision and SHA-256 in models.json.
- Whisper small.en: MIT. GGML conversion hosted by ggerganov/whisper.cpp; revision and SHA-256 in models.json.
- SQLite: public domain, supplied by macOS.

The application uses Apple's system SwiftUI, AppKit, AVFoundation, PDFKit, and CryptoKit frameworks. These system frameworks are not distributed as open-source dependencies. No Apple Intelligence or hosted AI service is used.

Upstream runtime dependency notices are included under Licenses. Model weights are separately downloaded, verified, and stored in ~/Library/Application Support/Folio/Models. Models are shared by every project.

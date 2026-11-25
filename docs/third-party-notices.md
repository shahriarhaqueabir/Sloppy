# Third-party notices

## whisper.cpp

- Project: https://github.com/ggml-org/whisper.cpp
- License: MIT (https://github.com/ggml-org/whisper.cpp/blob/master/LICENSE)
- Used for: local speech-to-text only. Sloppy invokes `whisper-cli` per utterance and never uploads audio.

## Whisper small model

- File: `runtime/whisper/models/ggml-small.bin`
- Published filename and checksum: https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md
- SHA-1: `55356645c2b361a969dfd0ef2c5a50d530afd8d5`

The checksum is verified by `tools/slop-preflight.ps1`. Release-time license review is a separate gate; this file records provenance, it does not authorize a release.

#!/usr/bin/env python3
"""extract-report.py — split the smoke stream at the LAST literal ===REPORT=== marker.

Contract with smoke-ephemeral.sh (cell.md extraction):

* The last literal occurrence of ``===REPORT===`` splits the stream, even when
  the model appends the marker inline after narration (live q2-D failure mode:
  "...no source-plan channel failed.===REPORT===").
* Leading whitespace/newlines after the marker are trimmed from the extracted
  report.
* Fallbacks: no marker, or a suffix that is empty / only whitespace -> the full
  stream is written unchanged.

The stream is handled as raw bytes so arbitrary model output round-trips
unchanged in the fallback paths.
"""

import sys

MARKER = b"===REPORT==="


def extract(stream: bytes) -> bytes:
    idx = stream.rfind(MARKER)
    if idx == -1:
        return stream  # no marker -> full stream fallback
    suffix = stream[idx + len(MARKER):]
    report = suffix.lstrip()  # trim leading whitespace/newlines
    if not report.strip():
        return stream  # empty (whitespace-only) suffix -> full stream fallback
    return report


def main() -> int:
    if len(sys.argv) > 1:
        with open(sys.argv[1], "rb") as fh:
            stream = fh.read()
    else:
        stream = sys.stdin.buffer.read()
    sys.stdout.buffer.write(extract(stream))
    return 0


if __name__ == "__main__":
    sys.exit(main())

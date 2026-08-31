#!/usr/bin/env python3
"""
vcard_2to3.py

Converts a vCard 2.1 file (e.g. exported from Android's Contacts app) into
vCard 3.0, which Nextcloud Contacts imports far more reliably.

Fixes applied:
  - VERSION:2.1  ->  VERSION:3.0
  - Bare parameter tokens (TEL;HOME:...) -> TYPE= syntax (TEL;TYPE=HOME:...)
  - PHOTO;ENCODING=BASE64;JPEG:...  ->  PHOTO;ENCODING=b;TYPE=JPEG:...
  - Properly unfolds/refolds long lines per the vCard line-length limit

Usage:
    python3 vcard_2to3.py input.vcf output.vcf

If output.vcf is omitted, writes to <input>_v3.vcf next to the input file.
"""

import re
import sys
from pathlib import Path

FOLD_LIMIT = 75  # bytes, per RFC 2426 / RFC 6350 recommendation

# Properties whose bare (non-"TYPE=") parameters should be rewritten as TYPE=...
TYPED_PROPS = ("TEL", "EMAIL", "ADR")


def unfold(text: str) -> list[str]:
    """Undo vCard line folding (CRLF followed by a single space or tab)."""
    text = text.replace("\r\n ", "").replace("\r\n\t", "")
    # Some exporters use bare \n instead of \r\n
    text = text.replace("\n ", "").replace("\n\t", "")
    # Normalize remaining line endings to \r\n, then split
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")
    # Drop trailing blank line(s)
    while lines and lines[-1].strip() == "":
        lines.pop()
    return lines


def fold(line: str, limit: int = FOLD_LIMIT) -> str:
    """Re-fold a logical line so no physical line exceeds `limit` bytes."""
    if len(line.encode("utf-8")) <= limit:
        return line
    parts = []
    remaining = line
    first = True
    while len(remaining.encode("utf-8")) > limit:
        chunk_len = limit if first else limit - 1  # continuation lines lose 1 char to the leading space
        parts.append(remaining[:chunk_len])
        remaining = remaining[chunk_len:]
        first = False
    parts.append(remaining)
    return "\r\n ".join(parts)


def convert_line(line: str) -> str:
    if line == "VERSION:2.1":
        return "VERSION:3.0"

    # TEL;HOME;CELL:... -> TEL;TYPE=HOME;TYPE=CELL:...  (skip if already using TYPE=)
    m = re.match(r"^(" + "|".join(TYPED_PROPS) + r");([A-Za-z0-9,;]+):(.*)$", line)
    if m and "TYPE=" not in m.group(2):
        params = ";".join(f"TYPE={p}" for p in m.group(2).split(","))
        return f"{m.group(1)};{params}:{m.group(3)}"

    # PHOTO;ENCODING=BASE64;JPEG:...  ->  PHOTO;ENCODING=b;TYPE=JPEG:...
    m = re.match(r"^PHOTO;ENCODING=BASE64;([A-Za-z0-9]+):(.*)$", line)
    if m:
        return f"PHOTO;ENCODING=b;TYPE={m.group(1)}:{m.group(2)}"

    return line


def convert(text: str) -> str:
    lines = unfold(text)
    converted = [convert_line(l) for l in lines]
    folded = [fold(l) for l in converted]
    return "\r\n".join(folded) + "\r\n"


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 vcard_2to3.py input.vcf [output.vcf]")
        sys.exit(1)

    in_path = Path(sys.argv[1])
    if len(sys.argv) >= 3:
        out_path = Path(sys.argv[2])
    else:
        out_path = in_path.with_name(in_path.stem + "_v3" + in_path.suffix)

    text = in_path.read_text(encoding="utf-8", errors="replace")

    if "VERSION:2.1" not in text:
        print("Note: no 'VERSION:2.1' found in the input — file may already be "
              "vCard 3.0/4.0, or use unusual line endings. Proceeding anyway.")

    result = convert(text)
    out_path.write_text(result, encoding="utf-8", newline="")

    card_count = result.count("BEGIN:VCARD")
    print(f"Converted {card_count} card(s).")
    print(f"Wrote: {out_path}")


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# Apply local patches to the resolved SwiftTerm checkout (idempotent).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

UTILITIES=".build/checkouts/SwiftTerm/Sources/SwiftTerm/Utilities.swift"

if [[ ! -f "$UTILITIES" ]]; then
  echo "[swiftterm-patches] resolving SwiftTerm…"
  swift package resolve
fi

if [[ ! -f "$UTILITIES" ]]; then
  echo "[swiftterm-patches] Utilities.swift not found — skip" >&2
  exit 0
fi

if grep -q 'isEnclosedAlphanumeric' "$UTILITIES"; then
  exit 0
fi

chmod u+w "$UTILITIES"

python3 <<'PY'
from pathlib import Path

path = Path(".build/checkouts/SwiftTerm/Sources/SwiftTerm/Utilities.swift")
text = path.read_text()

helper = """
    private static func isEnclosedAlphanumeric (_ value: UInt32) -> Bool
    {
        // Enclosed alphanumerics (①②③) and enclosed CJK (㊀) crush in 1 monospace cell.
        return (value >= 0x2460 && value <= 0x24FF)
            || (value >= 0x3200 && value <= 0x32FF)
    }

"""

needle = "    static func columnWidth (rune: UnicodeScalar) -> Int\n"
if needle not in text:
    raise SystemExit("columnWidth anchor not found in SwiftTerm Utilities.swift")

text = text.replace(needle, helper + needle, 1)

insert = """        if isEnclosedAlphanumeric(irune) {
            return 2
        }

"""
anchor = "        if isEastAsianWide(irune) {\n            return 2\n        }\n\n        return 1"
if anchor not in text:
    raise SystemExit("return anchor not found in SwiftTerm Utilities.swift")

text = text.replace(anchor, insert + anchor, 1)
path.write_text(text)
print("[swiftterm-patches] applied enclosed-symbol width patch")
PY
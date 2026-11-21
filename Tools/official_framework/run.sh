#!/bin/bash
# Rebuilds Curriculum/official/ from the two CBSE Learning Framework PDFs.
# Usage: Tools/official_framework/run.sh [work-folder]
# The PDFs are downloaded into their own folders and checked against the hashes below; if a hash differs the
# publisher changed the file, so look at the new version before trusting the extraction.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${1:-${TMPDIR:-/tmp}/litmus-official}"
mkdir -p "$WORK/science" "$WORK/socialscience"
# cbseacademic.nic.in (no "www.") has a valid certificate; the www host does not
curl -sSL -o "$WORK/science/Learning_Standards_Science.pdf" https://cbseacademic.nic.in/cbe/documents/Learning_Standards_Science.pdf
curl -sSL -o "$WORK/socialscience/Learning_Standards_SocialScience.pdf" https://cbseacademic.nic.in/cbe/documents/Learning_Standards_SocialScience.pdf
[ "$(shasum -a 256 "$WORK/science/Learning_Standards_Science.pdf" | cut -d' ' -f1)" = "df4fcc0a81e59e564d2d92d5dc6110652758b3b90f60e893b91113b44e5e4ef4" ] || echo "WARNING: Science PDF hash changed"
[ "$(shasum -a 256 "$WORK/socialscience/Learning_Standards_SocialScience.pdf" | cut -d' ' -f1)" = "5fba5484b8549c0ea35942e2cd36a52dedcc84277e0a2b3d6aaf87e41d7b5499" ] || echo "WARNING: Social Science PDF hash changed"
xcrun swiftc "$ROOT/Tools/official_framework/dump_pdf_lines.swift" -o "$WORK/dump_pdf_lines"
"$WORK/dump_pdf_lines" "$WORK/science/Learning_Standards_Science.pdf" "$WORK/sci_lines.json"
"$WORK/dump_pdf_lines" "$WORK/socialscience/Learning_Standards_SocialScience.pdf" "$WORK/ss_lines.json"
python3 -I "$ROOT/Tools/official_framework/parse_official.py" science "$WORK/sci_lines.json" 24 92 "$WORK/official_science.json"
python3 -I "$ROOT/Tools/official_framework/parse_official.py" socialscience "$WORK/ss_lines.json" 41 130 "$WORK/official_ss.json"
python3 -I "$ROOT/Tools/official_framework/build_tags.py" "$WORK" "$ROOT"

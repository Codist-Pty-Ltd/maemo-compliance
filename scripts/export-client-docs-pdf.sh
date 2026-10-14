#!/usr/bin/env bash
# Export client-facing Markdown documents to PDF (Windows Git Bash).
# Requires: Pandoc (winget install JohnMacFarlane.Pandoc), Microsoft Edge.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT_DIR="$ROOT/docs/client"
PANDOC="${PANDOC:-$HOME/AppData/Local/Pandoc/pandoc.exe}"
EDGE="${EDGE:-/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe}"

if [[ ! -f "$PANDOC" ]]; then
  echo "Pandoc not found at: $PANDOC"
  echo "Install: winget install --id JohnMacFarlane.Pandoc -e"
  exit 1
fi

if [[ ! -f "$EDGE" ]]; then
  echo "Microsoft Edge not found at: $EDGE"
  exit 1
fi

export_one() {
  local md="$1"
  local title="$2"
  local base pdf html
  base="$(basename "$md" .md)"
  html="$CLIENT_DIR/${base}.html"
  pdf="$CLIENT_DIR/${base}.pdf"

  echo "→ $md"
  "$PANDOC" "$md" -o "$html" --standalone --metadata "title=$title"
  "$EDGE" --headless --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$pdf" "file:///$html" 2>/dev/null || true

  if [[ -f "$pdf" ]]; then
    echo "  ✓ $pdf"
  else
    echo "  ✗ Failed to create $pdf"
    exit 1
  fi
}

export_one "$CLIENT_DIR/MAEMO_PRODUCT_SPECIFICATION.md" "Maemo Compliance Product Specification"
export_one "$CLIENT_DIR/MAEMO_ISO_27001_AND_22301_SUPPORT_GUIDE.md" "Maemo ISO 27001 and 22301 Support Guide"

echo ""
echo "Done. PDFs are in docs/client/"

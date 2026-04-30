#!/bin/bash
# PRD compliance checker using Gemini Vision API
# Sends snapshot images + PRD text to Gemini and gets back compliance assessment.
#
# Usage:
#   ./scripts/check_prd_compliance.sh <KMD-XX>           # Check specific PRD
#   ./scripts/check_prd_compliance.sh --all               # Check all PRDs with snapshots
#   ./scripts/check_prd_compliance.sh --snapshots-only    # Check all snapshots against general UI guidelines
#
# Requires: GEMINI_API_KEY in environment (source ~/.zshrc)
# Output: JSON report to stdout, human-readable summary to stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

SNAPSHOT_DIR="Tests/kobaamdTests/__Snapshots__"
PRD_DIR="docs/prd"
REPORT_DIR=".logs/prd-compliance"

# Ensure API key
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    source ~/.zshrc 2>/dev/null || true
fi
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    echo "❌ GEMINI_API_KEY not set" >&2
    exit 1
fi

mkdir -p "$REPORT_DIR"

# -------------------------------------------------------------------
# Helper: encode image to base64
# -------------------------------------------------------------------
encode_image() {
    base64 -i "$1" | tr -d '\n'
}

# -------------------------------------------------------------------
# Helper: call Gemini Vision API with images + text prompt
# -------------------------------------------------------------------
call_gemini_vision() {
    local prompt="$1"
    shift
    local image_files=("$@")

    # Build parts array: text prompt first, then images
    local parts_json
    parts_json=$(cat <<ENDJSON
{"text": $(echo "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}
ENDJSON
)

    for img in "${image_files[@]}"; do
        local b64
        b64=$(encode_image "$img")
        local mime="image/png"
        parts_json="$parts_json, {\"inline_data\": {\"mime_type\": \"$mime\", \"data\": \"$b64\"}}"
    done

    local request_json
    request_json=$(cat <<ENDJSON
{
  "contents": [{"parts": [$parts_json]}],
  "generationConfig": {
    "temperature": 0.2,
    "maxOutputTokens": 4096
  }
}
ENDJSON
)

    curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$request_json" \
        | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r.get("candidates",[{}])[0].get("content",{}).get("parts",[{}])[0].get("text","ERROR: No response"))'
}

# -------------------------------------------------------------------
# Check snapshots against a specific PRD
# -------------------------------------------------------------------
check_prd() {
    local prd_id="$1"
    local prd_file="$PRD_DIR/${prd_id}.md"

    # Find PRD file (try with and without prefix patterns)
    if [[ ! -f "$prd_file" ]]; then
        prd_file=$(find "$PRD_DIR" -name "${prd_id}*" -type f 2>/dev/null | head -1)
    fi
    if [[ -z "$prd_file" || ! -f "$prd_file" ]]; then
        echo "❌ PRD not found for $prd_id" >&2
        return 1
    fi

    local prd_text
    prd_text=$(cat "$prd_file")

    # Collect all snapshot images
    local images=()
    if [[ -d "$SNAPSHOT_DIR" ]]; then
        while IFS= read -r -d '' f; do
            images+=("$f")
        done < <(find "$SNAPSHOT_DIR" -maxdepth 1 -name "*.png" -print0 2>/dev/null)
    fi

    if [[ ${#images[@]} -eq 0 ]]; then
        echo "⚠️  No snapshot images found in $SNAPSHOT_DIR" >&2
        return 1
    fi

    echo "📋 Checking ${#images[@]} snapshots against PRD: $(basename "$prd_file")" >&2

    local prompt
    prompt=$(cat <<'PROMPT_END'
あなたは macOS ネイティブアプリ「kobaamd」（Markdown エディタ）の QA エンジニアです。

以下の PRD（製品要求仕様書）と、アプリの UI スナップショット画像を比較して、PRD 準拠チェックを行ってください。

## チェック観点

1. **UI 構造**: PRD の Section 5 (UI/UX) に記載されたレイアウト・要素が画像に存在するか
2. **受け入れ条件**: PRD の Section 6 (Acceptance Criteria) のうち、視覚的に確認可能な項目が満たされているか
3. **macOS ガイドライン準拠**: ネイティブ感のある UI か（フォント・間隔・色・コントロール）
4. **アクセシビリティ**: テキストの可読性、コントラスト、ボタンサイズ

## 出力フォーマット（JSON）

```json
{
  "prd_id": "KMD-XX",
  "overall_score": 0-100,
  "status": "PASS" | "WARN" | "FAIL",
  "checks": [
    {
      "category": "ui_structure | acceptance | macos_guideline | accessibility",
      "item": "チェック項目",
      "result": "PASS" | "WARN" | "FAIL",
      "detail": "詳細説明"
    }
  ],
  "summary": "全体サマリ（日本語、2-3文）"
}
```

`overall_score` は 80 以上で PASS、60-79 で WARN、60 未満で FAIL としてください。

---

## PRD:

PROMPT_END
)
    prompt="$prompt"$'\n'"$prd_text"

    local result
    result=$(call_gemini_vision "$prompt" "${images[@]}")

    # Save report
    local report_file="$REPORT_DIR/${prd_id}-$(date +%Y%m%d-%H%M%S).md"
    echo "$result" > "$report_file"
    echo "📄 Report saved: $report_file" >&2

    # Extract and display summary
    echo "$result"
}

# -------------------------------------------------------------------
# Check all snapshots against general UI quality guidelines (no PRD)
# -------------------------------------------------------------------
check_snapshots_only() {
    local images=()
    if [[ -d "$SNAPSHOT_DIR" ]]; then
        while IFS= read -r -d '' f; do
            images+=("$f")
        done < <(find "$SNAPSHOT_DIR" -maxdepth 1 -name "*.png" -print0 2>/dev/null)
    fi

    if [[ ${#images[@]} -eq 0 ]]; then
        echo "⚠️  No snapshot images found" >&2
        return 1
    fi

    echo "🔍 Checking ${#images[@]} snapshots against general UI guidelines" >&2

    local prompt
    prompt=$(cat <<'PROMPT_END'
あなたは macOS ネイティブアプリ「kobaamd」（Markdown エディタ）の QA エンジニアです。

以下の UI スナップショット画像を評価してください。各画像について以下の観点でチェックしてください。

## チェック観点

1. **macOS ネイティブ感**: SF Symbols、標準コントロール、ダークモード対応
2. **レイアウト**: 余白の均一性、アライメント、要素の重なり
3. **タイポグラフィ**: フォントサイズの適切さ、階層、可読性
4. **アクセシビリティ**: コントラスト比、タッチターゲットサイズ、テキスト切れ
5. **一貫性**: 画像間でスタイルが統一されているか

## 出力フォーマット（JSON）

```json
{
  "overall_score": 0-100,
  "status": "PASS" | "WARN" | "FAIL",
  "images": [
    {
      "filename": "画像ファイル名（推定）",
      "score": 0-100,
      "issues": [
        {
          "severity": "info" | "warning" | "error",
          "category": "layout | typography | accessibility | consistency | native_feel",
          "detail": "具体的な指摘（日本語）"
        }
      ]
    }
  ],
  "summary": "全体サマリ（日本語、2-3文）"
}
```

`overall_score` は 80 以上で PASS、60-79 で WARN、60 未満で FAIL。
PROMPT_END
)

    local result
    result=$(call_gemini_vision "$prompt" "${images[@]}")

    local report_file="$REPORT_DIR/ui-quality-$(date +%Y%m%d-%H%M%S).md"
    echo "$result" > "$report_file"
    echo "📄 Report saved: $report_file" >&2

    echo "$result"
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------
case "${1:-}" in
    --all)
        echo "🔄 Checking all PRDs with available snapshots..." >&2
        for prd_file in "$PRD_DIR"/KMD-*.md; do
            prd_id=$(basename "$prd_file" .md)
            check_prd "$prd_id" || true
            echo "" >&2
        done
        ;;
    --snapshots-only)
        check_snapshots_only
        ;;
    KMD-*|kmd-*)
        check_prd "$1"
        ;;
    *)
        echo "Usage:" >&2
        echo "  $0 <KMD-XX>           Check specific PRD" >&2
        echo "  $0 --all              Check all PRDs" >&2
        echo "  $0 --snapshots-only   Check snapshots against UI guidelines" >&2
        exit 1
        ;;
esac

#!/bin/bash
# appcast.xml を生成するスクリプト
# Sparkle の EdDSA 署名付き DMG リリース用
#
# 使い方:
#   ./scripts/generate-appcast.sh <version> <dmg_url> <eddsa_signature> <file_length>
#
# 引数:
#   version        — セマンティックバージョン (例: 0.7.0)
#   dmg_url        — GitHub Releases の DMG ダウンロード URL
#   eddsa_signature — Sparkle の sign_update ツールで生成した EdDSA 署名
#   file_length    — DMG ファイルのバイト数
#
# 出力: appcast.xml (リポジトリルートに生成)
set -euo pipefail

VERSION="${1:-}"
DMG_URL="${2:-}"
SIGNATURE="${3:-}"
LENGTH="${4:-}"

if [[ -z "$VERSION" || -z "$DMG_URL" || -z "$SIGNATURE" || -z "$LENGTH" ]]; then
    echo "Usage: $0 <version> <dmg_url> <eddsa_signature> <file_length>"
    echo ""
    echo "Example:"
    echo "  $0 0.7.0 https://github.com/kobaaam/kobaamd/releases/download/v0.7.0/kobaamd.dmg <sig> 12345678"
    exit 1
fi

# 署名のサニティチェック（空白だけ・プレースホルダーを弾く）
TRIMMED_SIGNATURE="$(echo -n "$SIGNATURE" | tr -d '[:space:]')"
if [[ -z "$TRIMMED_SIGNATURE" || "$TRIMMED_SIGNATURE" == "PLACEHOLDER" || "$TRIMMED_SIGNATURE" == "TODO" ]]; then
  echo "Error: <eddsa_signature> is empty or a placeholder. Refusing to generate appcast.xml without a valid Sparkle signature." >&2
  echo "Hint: run \`./bin/sign_update <path-to-dmg>\` (Sparkle xcframework) to obtain the signature." >&2
  exit 1
fi

PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/../appcast.xml"

cat > "$OUTPUT" << XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>kobaamd</title>
        <link>https://github.com/kobaaam/kobaamd</link>
        <description>kobaamd — AI-friendly Markdown editor for macOS</description>
        <language>ja</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:releaseNotesLink>https://github.com/kobaaam/kobaamd/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
            <enclosure
                url="${DMG_URL}"
                sparkle:edSignature="${SIGNATURE}"
                length="${LENGTH}"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
XMLEOF

echo "Generated appcast.xml for version ${VERSION} at ${OUTPUT}"

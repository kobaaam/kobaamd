#!/bin/bash
# TartVM E2E テスト実行スクリプト
#
# VM 起動 → アプリビルド&転送 → XCUITest 実行 → スクショ回収 → VM 破棄 → Gemini Vision PRD チェック
#
# Usage:
#   ./scripts/run_e2e_tests.sh                    # フル E2E（ビルド + テスト + Gemini チェック）
#   ./scripts/run_e2e_tests.sh --skip-gemini      # Gemini チェックをスキップ
#   ./scripts/run_e2e_tests.sh --keep-vm          # テスト後 VM を残す（デバッグ用）
#   ./scripts/run_e2e_tests.sh --screenshots-only # スクショ撮影のみ（XCUITest なし、screencapture 使用）
#
# Prerequisites:
#   - tart CLI installed (brew install cirruslabs/cli/tart)
#   - sshpass installed (brew install esolitos/ipa/sshpass)
#   - Base VM created (./scripts/setup_tart_vm.sh)
#   - GEMINI_API_KEY set (for PRD compliance check)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# --- Configuration ---
BASE_VM="kobaamd-e2e-base"
TEST_VM="kobaamd-e2e-run-$$"  # PID で一意にする
VM_USER="admin"
VM_PASS="admin"
SSH_KEY="$HOME/.ssh/id_ed25519"
SCREENSHOTS_LOCAL="$PROJECT_DIR/.logs/e2e_screenshots"
REPORT_DIR="$PROJECT_DIR/.logs/e2e_reports"
XCRESULT_DIR="$PROJECT_DIR/.logs/e2e_xcresults"
WAIT_TIMEOUT=120

# --- Flags ---
SKIP_GEMINI=false
KEEP_VM=false
SCREENSHOTS_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --skip-gemini) SKIP_GEMINI=true ;;
        --keep-vm) KEEP_VM=true ;;
        --screenshots-only) SCREENSHOTS_ONLY=true ;;
    esac
done

# --- Helper Functions ---
log()   { echo "🧪 [e2e] $*" >&2; }
err()   { echo "❌ [e2e] $*" >&2; }
ok()    { echo "✅ [e2e] $*" >&2; }
warn()  { echo "⚠️  [e2e] $*" >&2; }

timestamp() { date +%Y%m%d-%H%M%S; }

ssh_cmd() {
    local ip="$1"
    shift
    if [ -f "$SSH_KEY" ]; then
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" -q "$VM_USER@$ip" "$@"
    else
        sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -q "$VM_USER@$ip" "$@"
    fi
}

scp_cmd() {
    if [ -f "$SSH_KEY" ]; then
        scp -o StrictHostKeyChecking=no -i "$SSH_KEY" -q "$@"
    else
        sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no -q "$@"
    fi
}

wait_for_ssh() {
    local ip="$1"
    local elapsed=0
    while ! ssh_cmd "$ip" "echo ok" 2>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge $WAIT_TIMEOUT ]; then
            err "SSH タイムアウト (${WAIT_TIMEOUT}s)"
            return 1
        fi
    done
}

cleanup() {
    if [ "$KEEP_VM" = "false" ] && tart list 2>/dev/null | grep -q "$TEST_VM"; then
        log "テスト VM をクリーンアップ中..."
        tart stop "$TEST_VM" 2>/dev/null || true
        sleep 3
        tart delete "$TEST_VM" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- Prerequisite Check ---
log "前提条件チェック..."

if ! command -v tart &>/dev/null; then
    err "tart が見つかりません。brew install cirruslabs/cli/tart"
    exit 1
fi

if ! tart list 2>/dev/null | grep -q "$BASE_VM"; then
    err "ベース VM '$BASE_VM' が見つかりません。先に ./scripts/setup_tart_vm.sh を実行してください"
    exit 1
fi

mkdir -p "$SCREENSHOTS_LOCAL" "$REPORT_DIR" "$XCRESULT_DIR"

# ===================================================================
# Phase 1: ホストでアプリをビルド
# ===================================================================
log "=== Phase 1: アプリビルド ==="
log "swift build 実行中..."
swift build 2>&1 | tail -3
./scripts/post-build.sh 2>&1 | tail -5

APP_BUNDLE=".build/kobaamd.app"
if [ ! -d "$APP_BUNDLE" ]; then
    err ".app バンドルが見つかりません: $APP_BUNDLE"
    exit 1
fi
ok "アプリビルド完了: $APP_BUNDLE"

# ===================================================================
# Phase 2: テスト VM 作成 & 起動
# ===================================================================
log "=== Phase 2: VM 起動 ==="
log "ベース VM からクローン中..."
tart clone "$BASE_VM" "$TEST_VM"
ok "VM クローン完了: $TEST_VM"

log "VM を headless で起動中..."
tart run --no-graphics "$TEST_VM" &
VM_PID=$!

# IP 取得を待機
sleep 15
VM_IP=""
for i in $(seq 1 24); do
    VM_IP=$(tart ip "$TEST_VM" 2>/dev/null || true)
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 5
done

if [ -z "$VM_IP" ]; then
    err "VM IP が取得できません"
    exit 1
fi
log "VM IP: $VM_IP"

log "SSH 接続を待機中..."
wait_for_ssh "$VM_IP"

# Window Server の安定化待ち
log "Window Server 安定化待ち (10s)..."
sleep 10
ok "VM 起動完了"

# ===================================================================
# Phase 3: アプリ転送 & 起動
# ===================================================================
log "=== Phase 3: アプリ転送 ==="

# .app を zip で転送（ディレクトリ転送の信頼性向上）
log ".app バンドルを圧縮中..."
TMPZIP="/tmp/kobaamd-e2e-$$.zip"
(cd .build && zip -r -q "$TMPZIP" kobaamd.app)

log "VM にアプリを転送中..."
scp_cmd "$TMPZIP" "$VM_USER@$VM_IP:~/Desktop/kobaamd.zip"
rm -f "$TMPZIP"

log "VM 内で展開中..."
ssh_cmd "$VM_IP" "cd ~/Desktop && unzip -o -q kobaamd.zip && rm kobaamd.zip"
ok "アプリ転送完了"

# ===================================================================
# Phase 4: テスト実行
# ===================================================================
log "=== Phase 4: テスト実行 ==="

if [ "$SCREENSHOTS_ONLY" = "true" ]; then
    # --- Screenshots Only Mode (XCUITest なし) ---
    log "スクリーンショットモード: アプリを起動してキャプチャ"

    ssh_cmd "$VM_IP" "mkdir -p ~/Desktop/e2e_screenshots"

    # アプリ起動
    ssh_cmd "$VM_IP" "open ~/Desktop/kobaamd.app"
    sleep 5

    # 初期画面キャプチャ
    ssh_cmd "$VM_IP" "screencapture -x ~/Desktop/e2e_screenshots/editor_initial.png"
    log "editor_initial.png captured"

    # メニュー操作: 新規ファイル
    ssh_cmd "$VM_IP" 'osascript -e "
        tell application \"System Events\"
            tell process \"kobaamd\"
                set frontmost to true
                click menu item \"新規\" of menu \"ファイル\" of menu bar item \"ファイル\" of menu bar 1
            end tell
        end tell
    "' 2>/dev/null || warn "メニュー操作失敗（TCC 許可が必要かもしれません）"
    sleep 2
    ssh_cmd "$VM_IP" "screencapture -x ~/Desktop/e2e_screenshots/editor_new_file.png"
    log "editor_new_file.png captured"

    # ヘルプウィンドウ
    ssh_cmd "$VM_IP" 'osascript -e "
        tell application \"System Events\"
            tell process \"kobaamd\"
                set frontmost to true
                click menu item \"kobaamd ヘルプ\" of menu \"ヘルプ\" of menu bar item \"ヘルプ\" of menu bar 1
            end tell
        end tell
    "' 2>/dev/null || warn "ヘルプメニュー操作失敗"
    sleep 2
    ssh_cmd "$VM_IP" "screencapture -x ~/Desktop/e2e_screenshots/help_window.png"
    log "help_window.png captured"

    ok "スクリーンショット撮影完了"

else
    # --- XCUITest Mode ---
    log "XCUITest モード: プロジェクト転送 & xcodebuild test"

    # E2ETests プロジェクトを転送
    if [ -d "$PROJECT_DIR/E2ETests" ]; then
        log "E2ETests プロジェクトを転送中..."
        TESTZIP="/tmp/kobaamd-e2e-tests-$$.zip"
        (cd "$PROJECT_DIR" && zip -r -q "$TESTZIP" E2ETests/)
        scp_cmd "$TESTZIP" "$VM_USER@$VM_IP:~/Desktop/E2ETests.zip"
        rm -f "$TESTZIP"
        ssh_cmd "$VM_IP" "cd ~/Desktop && unzip -o -q E2ETests.zip && rm E2ETests.zip"
        ok "E2ETests 転送完了"

        # VM 内で xcodeproj を生成（VM には Xcode がある）
        log "VM 内で xcodeproj を生成中..."
        ssh_cmd "$VM_IP" "cd ~/Desktop/E2ETests && chmod +x generate_xcodeproj.sh && ./generate_xcodeproj.sh"
        ok "xcodeproj 生成完了"

        # アプリを先に起動
        ssh_cmd "$VM_IP" "open ~/Desktop/kobaamd.app"
        sleep 5

        # xcodebuild test 実行
        log "xcodebuild test 実行中..."
        XCRESULT_NAME="e2e-$(timestamp).xcresult"
        ssh_cmd "$VM_IP" "cd ~/Desktop/E2ETests && \
            xcodebuild test \
                -project kobaamdE2E.xcodeproj \
                -scheme kobaamdE2ETests \
                -destination 'platform=macOS' \
                -resultBundlePath ~/Desktop/$XCRESULT_NAME \
                2>&1" | tee "$XCRESULT_DIR/xcodebuild-$(timestamp).log" || {
            warn "xcodebuild test が失敗しました（ログを確認してください）"
        }

        # xcresult からスクリーンショットを抽出
        log "xcresult からスクリーンショットを抽出中..."
        ssh_cmd "$VM_IP" "
            mkdir -p ~/Desktop/e2e_screenshots
            if [ -d ~/Desktop/$XCRESULT_NAME ]; then
                # xcresulttool で添付ファイルを抽出
                xcrun xcresulttool get --path ~/Desktop/$XCRESULT_NAME \
                    --format json 2>/dev/null | \
                    python3 -c '
import json, sys, subprocess, os
data = json.load(sys.stdin)
def extract_attachments(obj, depth=0):
    if isinstance(obj, dict):
        if obj.get(\"_type\", {}).get(\"_name\") == \"ActionTestAttachment\":
            name = obj.get(\"name\", {}).get(\"_value\", \"unknown\")
            payload_ref = obj.get(\"payloadRef\", {}).get(\"id\", {}).get(\"_value\")
            if payload_ref and name.endswith(\".png\") or \"screenshot\" in name.lower():
                out_path = os.path.expanduser(f\"~/Desktop/e2e_screenshots/{name}.png\")
                subprocess.run([
                    \"xcrun\", \"xcresulttool\", \"get\",
                    \"--path\", os.path.expanduser(f\"~/Desktop/$XCRESULT_NAME\"),
                    \"--id\", payload_ref,
                    \"--output-path\", out_path
                ], check=False)
        for v in obj.values():
            extract_attachments(v, depth+1)
    elif isinstance(obj, list):
        for v in obj:
            extract_attachments(v, depth+1)
extract_attachments(data)
' 2>/dev/null || true
            fi
        " 2>/dev/null || warn "xcresult 抽出に失敗（手動でスクショを確認してください）"

        # xcresult を回収
        log "テスト結果を回収中..."
        scp_cmd -r "$VM_USER@$VM_IP:~/Desktop/$XCRESULT_NAME" "$XCRESULT_DIR/" 2>/dev/null || true
    else
        warn "E2ETests/ ディレクトリが見つかりません。--screenshots-only モードにフォールバック"
        SCREENSHOTS_ONLY=true
    fi

    # スクリーンショットを回収
    ssh_cmd "$VM_IP" "mkdir -p ~/Desktop/e2e_screenshots"
fi

# ===================================================================
# Phase 5: スクリーンショット回収
# ===================================================================
log "=== Phase 5: スクリーンショット回収 ==="

TIMESTAMP=$(timestamp)
DEST="$SCREENSHOTS_LOCAL/$TIMESTAMP"
mkdir -p "$DEST"

scp_cmd -r "$VM_USER@$VM_IP:~/Desktop/e2e_screenshots/*" "$DEST/" 2>/dev/null || true

CAPTURED=$(find "$DEST" -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
if [ "$CAPTURED" -eq 0 ]; then
    warn "スクリーンショットが見つかりませんでした"
else
    ok "$CAPTURED 枚のスクリーンショットを回収: $DEST"
fi

# ===================================================================
# Phase 6: Gemini Vision PRD チェック
# ===================================================================
if [ "$SKIP_GEMINI" = "false" ] && [ "$CAPTURED" -gt 0 ]; then
    log "=== Phase 6: Gemini Vision PRD チェック ==="

    # GEMINI_API_KEY チェック
    if [ -z "${GEMINI_API_KEY:-}" ]; then
        source ~/.zshrc 2>/dev/null || true
    fi

    if [ -z "${GEMINI_API_KEY:-}" ]; then
        warn "GEMINI_API_KEY が未設定。PRD チェックをスキップ"
    else
        log "Gemini Vision API でスクリーンショットを評価中..."

        # Base64 エンコードして Gemini に投げる
        IMAGES_JSON=""
        for img in "$DEST"/*.png; do
            B64=$(base64 -i "$img" | tr -d '\n')
            if [ -n "$IMAGES_JSON" ]; then
                IMAGES_JSON="$IMAGES_JSON, "
            fi
            IMAGES_JSON="${IMAGES_JSON}{\"inline_data\": {\"mime_type\": \"image/png\", \"data\": \"$B64\"}}"
        done

        PROMPT=$(cat <<'PROMPT_END'
あなたは macOS ネイティブアプリ「kobaamd」（Markdown エディタ）の QA エンジニアです。

以下の E2E テストで撮影したスクリーンショットを評価してください。
これらは TartVM 内でアプリを実際に起動し、画面操作して撮影した実際のスクリーンショットです。

## チェック観点

1. **アプリ起動確認**: アプリが正常に起動し、UI が表示されているか
2. **レイアウト健全性**: 要素の重なり、切れ、空白の異常がないか
3. **macOS ネイティブ感**: 標準的な macOS アプリとしての外観（メニューバー、ウィンドウクローム）
4. **テキスト可読性**: フォントサイズ、コントラスト、テキストの切れがないか
5. **機能的整合性**: エディタ画面にエディタが見えるか、ヘルプにヘルプ内容が見えるか

## 出力フォーマット（JSON）

```json
{
  "overall_score": 0-100,
  "status": "PASS" | "WARN" | "FAIL",
  "screenshots": [
    {
      "name": "推定されるスクリーンショット名",
      "score": 0-100,
      "observations": ["観察事項1", "観察事項2"],
      "issues": [
        {
          "severity": "info" | "warning" | "error",
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

        ESCAPED_PROMPT=$(echo "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

        REQUEST_JSON=$(cat <<ENDJSON
{
  "contents": [{"parts": [{"text": $ESCAPED_PROMPT}, $IMAGES_JSON]}],
  "generationConfig": {
    "temperature": 0.2,
    "maxOutputTokens": 4096
  }
}
ENDJSON
)

        RESULT=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$REQUEST_JSON" \
            | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r.get("candidates",[{}])[0].get("content",{}).get("parts",[{}])[0].get("text","ERROR: No response"))')

        REPORT_FILE="$REPORT_DIR/e2e-report-$TIMESTAMP.md"
        echo "$RESULT" > "$REPORT_FILE"
        ok "Gemini レポート保存: $REPORT_FILE"

        # スコア抽出
        SCORE=$(echo "$RESULT" | python3 -c 'import json,sys,re; m=re.search(r"\"overall_score\":\s*(\d+)", sys.stdin.read()); print(m.group(1) if m else "N/A")' 2>/dev/null || echo "N/A")
        STATUS=$(echo "$RESULT" | python3 -c 'import json,sys,re; m=re.search(r"\"status\":\s*\"(\w+)\"", sys.stdin.read()); print(m.group(1) if m else "N/A")' 2>/dev/null || echo "N/A")

        if [ "$STATUS" = "PASS" ]; then
            ok "Gemini 判定: $STATUS (score: $SCORE)"
        elif [ "$STATUS" = "WARN" ]; then
            warn "Gemini 判定: $STATUS (score: $SCORE)"
        else
            err "Gemini 判定: $STATUS (score: $SCORE)"
        fi
    fi
else
    log "Gemini チェックをスキップ"
fi

# ===================================================================
# 完了サマリ
# ===================================================================
echo ""
ok "=============================="
ok "E2E テスト完了"
ok "  スクリーンショット: $DEST"
[ -d "$XCRESULT_DIR" ] && ok "  xcresult: $XCRESULT_DIR"
[ -f "${REPORT_FILE:-}" ] && ok "  Gemini レポート: $REPORT_FILE"
if [ "$KEEP_VM" = "true" ]; then
    warn "VM '$TEST_VM' を残しています（手動で tart delete $TEST_VM）"
fi
ok "=============================="

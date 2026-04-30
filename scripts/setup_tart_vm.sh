#!/bin/bash
# TartVM E2E テスト用ベースイメージのセットアップ
#
# 初回のみ実行。ベースイメージから e2e 用 VM を作成し、
# 自動ログイン・SSH鍵登録・アクセシビリティ許可を設定する。
#
# Usage:
#   ./scripts/setup_tart_vm.sh              # フルセットアップ
#   ./scripts/setup_tart_vm.sh --check      # 既存 VM の状態確認
#
# Prerequisites: brew install cirruslabs/cli/tart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Configuration ---
BASE_IMAGE="ghcr.io/cirruslabs/macos-sequoia-xcode:latest"
VM_NAME="kobaamd-e2e-base"
VM_USER="admin"
VM_PASS="admin"
SSH_KEY="$HOME/.ssh/id_ed25519"
WAIT_TIMEOUT=120  # seconds to wait for SSH

# --- Helper Functions ---
log()  { echo "🔧 [setup] $*" >&2; }
err()  { echo "❌ [setup] $*" >&2; }
ok()   { echo "✅ [setup] $*" >&2; }

wait_for_ssh() {
    local ip="$1"
    local elapsed=0
    log "SSH 接続を待機中 ($ip)..."
    while ! sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -q "$VM_USER@$ip" "echo ok" 2>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge $WAIT_TIMEOUT ]; then
            err "SSH タイムアウト (${WAIT_TIMEOUT}s)"
            return 1
        fi
    done
    ok "SSH 接続確立 (${elapsed}s)"
}

ssh_cmd() {
    local ip="$1"
    shift
    sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no -q "$VM_USER@$ip" "$@"
}

# --- Check Mode ---
if [[ "${1:-}" == "--check" ]]; then
    echo "=== TartVM E2E 環境チェック ==="
    echo ""

    # Tart CLI
    if command -v tart &>/dev/null; then
        ok "Tart CLI: $(tart --version)"
    else
        err "Tart CLI: not installed"
    fi

    # sshpass
    if command -v sshpass &>/dev/null; then
        ok "sshpass: installed"
    else
        err "sshpass: not installed (brew install sshpass or brew install esolitos/ipa/sshpass)"
    fi

    # Base image
    if tart list 2>/dev/null | grep -q "$VM_NAME"; then
        ok "Base VM '$VM_NAME': exists"
    else
        err "Base VM '$VM_NAME': not found"
    fi

    # SSH key
    if [ -f "$SSH_KEY.pub" ]; then
        ok "SSH key: $SSH_KEY.pub"
    else
        err "SSH key: not found at $SSH_KEY.pub"
    fi

    exit 0
fi

# --- Prerequisites Check ---
log "前提条件チェック..."

if ! command -v tart &>/dev/null; then
    err "Tart CLI が見つかりません。brew install cirruslabs/cli/tart でインストールしてください"
    exit 1
fi

if ! command -v sshpass &>/dev/null; then
    log "sshpass をインストール中..."
    brew install esolitos/ipa/sshpass 2>&1 | tail -3
fi

# SSH key
if [ ! -f "$SSH_KEY.pub" ]; then
    log "SSH 鍵を生成中..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q
    ok "SSH 鍵生成完了: $SSH_KEY"
fi

# --- Base Image Check ---
if ! tart list 2>/dev/null | grep -q "$(echo "$BASE_IMAGE" | sed 's|.*/||')"; then
    log "ベースイメージをダウンロード中（初回のみ、20GB+）..."
    log "これには時間がかかります。別のターミナルで作業を続けてください。"
    tart pull "$BASE_IMAGE"
    ok "ベースイメージダウンロード完了"
fi

# --- Create VM ---
if tart list 2>/dev/null | grep -q "$VM_NAME"; then
    log "既存の VM '$VM_NAME' を削除中..."
    tart stop "$VM_NAME" 2>/dev/null || true
    tart delete "$VM_NAME"
fi

log "ベースイメージから '$VM_NAME' をクローン中..."
tart clone "$BASE_IMAGE" "$VM_NAME"
ok "VM クローン完了"

# --- Configure VM Resources ---
log "VM リソースを設定中 (4 CPU, 8GB RAM)..."
tart set "$VM_NAME" --cpu 4 --memory 8192
ok "VM リソース設定完了"

# --- Start VM and Configure ---
log "VM を起動中（GUI モード — 初回セットアップ用）..."
tart run "$VM_NAME" &
VM_PID=$!

# Wait for VM to boot and get IP
sleep 15
VM_IP=""
for i in $(seq 1 20); do
    VM_IP=$(tart ip "$VM_NAME" 2>/dev/null || true)
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 5
done

if [ -z "$VM_IP" ]; then
    err "VM の IP アドレスが取得できません"
    kill $VM_PID 2>/dev/null || true
    exit 1
fi
log "VM IP: $VM_IP"

# Wait for SSH
wait_for_ssh "$VM_IP"

# --- SSH Key Registration ---
log "SSH 公開鍵を VM に登録中..."
ssh_cmd "$VM_IP" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no "$SSH_KEY.pub" "$VM_USER@$VM_IP:~/.ssh/authorized_keys"
ssh_cmd "$VM_IP" "chmod 600 ~/.ssh/authorized_keys"
ok "SSH 鍵登録完了"

# --- Auto Login Setup ---
log "自動ログインを設定中..."
ssh_cmd "$VM_IP" "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser '$VM_USER'" 2>/dev/null || true
ok "自動ログイン設定完了（手動確認推奨）"

# --- Create E2E Screenshots Directory ---
log "スクリーンショット保存ディレクトリを作成中..."
ssh_cmd "$VM_IP" "mkdir -p ~/Desktop/e2e_screenshots"
ok "ディレクトリ作成完了"

# --- Verify Xcode ---
log "Xcode の状態を確認中..."
XCODE_VER=$(ssh_cmd "$VM_IP" "xcodebuild -version 2>/dev/null | head -1" || echo "not found")
log "Xcode: $XCODE_VER"

# --- Verify screencapture ---
log "screencapture の動作確認..."
ssh_cmd "$VM_IP" "screencapture -x ~/Desktop/test_capture.png && rm ~/Desktop/test_capture.png && echo 'screencapture OK'" || true

# --- Shutdown and Save ---
log "VM をシャットダウン中..."
ssh_cmd "$VM_IP" "sudo shutdown -h now" 2>/dev/null || true
sleep 10
kill $VM_PID 2>/dev/null || true
wait $VM_PID 2>/dev/null || true

ok "=============================="
ok "ベース VM '$VM_NAME' のセットアップ完了！"
ok ""
ok "E2E テストの実行:"
ok "  ./scripts/run_e2e_tests.sh"
ok ""
ok "VM を手動で起動（GUI 付き、デバッグ用）:"
ok "  tart run $VM_NAME"
ok ""
ok "TCC アクセシビリティ許可が必要な場合:"
ok "  1. tart run $VM_NAME で GUI 起動"
ok "  2. システム設定 > プライバシーとセキュリティ > アクセシビリティ"
ok "  3. sshd-keygen-wrapper を許可"
ok "=============================="

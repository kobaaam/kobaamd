#!/usr/bin/env bash
# Resolve SPM dependencies before building.
#
# 2026-07-02 (KMD-240): パッチ適用フェーズを廃止。
# readViewportText / readScreenText の API は kobaaam fork の kobaamd-patches
# ブランチに正規ファイルとして取り込み済み。Package.swift の revision ピンで
# 管理するため、このスクリプトは swift package resolve のラッパーとして残す。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

swift package resolve

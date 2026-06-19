---
issue: KMD-memory-fsevents
date: 2026-06-19
wiki_value: high
tags: [memory, fsevents, performance, e1-terminal]
---

# 39GB メモリ膨張 — FSEvents 連鎖の postmortem

## 概要

pj-manager ワークスペースで長時間稼働後、Activity Monitor で kobaamd のメモリフットプリントが **39GB** に到達。Spindump 解析で Wiki `rebuildIndex` ループと FSEvents 連鎖が主因と判明。

## トリガー

- E1 ターミナルが `.kobaamd/transcript.log`（~105MB）へ継続追記
- 各追記が FSEvents を発火
- ファイルツリー reload → `workspaceFilesChanged` → QuickOpen / tags / Wiki 全文インデックスが毎回再実行

## 対策（v0.4.6）

1. FSEvents / インデックス更新を **400ms debounce**
2. `.kobaamd/` をファイルツリー・Wiki・タグ走査から **常時除外**
3. Wiki `setRoot` が **building 中の重複呼び出しを無視**
4. `WorkspaceFolder` の Equatable を `nodesGeneration` ベースに変更（深い `FileNode` 比較回避）

## 教訓

- アプリ内部ディレクトリのログ追記は、ワークスペース全体の FSEvents 購読と相性が悪い
- 「即時ディスク同期」と「重いインデックス再構築」は分離し、後者だけ debounce する
- 運用回避（再起動）と構造修正は別物。Spindump で因果を確認してから P0 を切る
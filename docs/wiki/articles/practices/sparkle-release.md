---
title: Sparkle 署名付きリリース手順
category: practices
tags: [sparkle, security, release, eddsa]
sources: [docs/prd/KMD-27-sparkle-eddsa-public-key.md, docs/prd/KMD-16-auto-updater.md, docs/learnings/2026-04-28-KMD-6.md]
created: 2026-05-01
updated: 2026-05-01
---

# Sparkle 署名付きリリース手順

## Summary

Sparkle 自動アップデートを実運用するための EdDSA 署名付きリリース手順。公開鍵はソース管理に含めず、ビルド時に環境変数から注入し、秘密鍵は Keychain で管理する。

## Content

### なぜ EdDSA 署名検証が必要か

KMD-6 の振り返りでは、Sparkle 導入直後に `SUPublicEDKey` が未設定のままでも開発は進められる一方、配布物の真正性検証が成立していなかった。これが残ると、appcast や DMG の配布経路に対する MITM 攻撃や差し替え配布を利用者側で検知できない。

このため kobaamd では、公開鍵をリリースビルド時に必須化し、appcast 生成でも空署名やプレースホルダーを拒否する。背景は [KMD-6 の学び](../../../learnings/2026-04-28-KMD-6.md) も参照。

### 1回限りのセットアップ

Sparkle の鍵ペアは `generate_keys` で生成する。秘密鍵は標準で macOS Keychain に保存され、公開鍵だけが標準出力に表示される。

例:

```bash
./.build/checkouts/Sparkle/bin/generate_keys
```

このパスにバイナリがない場合は、Sparkle の配布物に含まれる `bin/generate_keys` を使う。実行後に表示された公開鍵を控え、シェル設定に登録する。

```bash
export KOBAAMD_SU_PUBLIC_ED_KEY="YOUR_PUBLIC_KEY"
```

`~/.zshrc` などに追記したあと、新しいシェルを開くか `source ~/.zshrc` を実行して反映する。`Info.plist` の `SUPublicEDKey` は空のまま維持し、`scripts/post-build.sh` が `.app/Contents/Info.plist` へ注入する。

### 各リリースの手順

1. `swift build -c release`
2. `./scripts/post-build.sh release`
3. DMG を作成する
4. `./.build/checkouts/Sparkle/bin/sign_update <dmg>` で署名を取得する
5. `./scripts/generate-appcast.sh <version> <dmg_url> <signature> <length>` で `appcast.xml` を生成する
6. GitHub Releases に成果物をアップロードし、`appcast.xml` を `main` にコミットする

手順 2 では `KOBAAMD_SU_PUBLIC_ED_KEY` が未設定だと `exit 1` で停止する。これは `SUPublicEDKey` なしのリリースを防ぐための安全装置である。手順 3 の DMG 作成は別ドキュメントの手順に従う。

### Keychain エクスポート

マシン乗り換え時は、Keychain Access で Sparkle 用の秘密鍵エントリを探してエクスポートする。移行先ではその秘密鍵を Keychain に取り込み、同じ公開鍵を `KOBAAMD_SU_PUBLIC_ED_KEY` として設定する。秘密鍵ファイルをリポジトリに置かないこと。

### トラブルシュート

`[post-build] ERROR: KOBAAMD_SU_PUBLIC_ED_KEY is not set for release build`
- 環境変数 `KOBAAMD_SU_PUBLIC_ED_KEY` を設定してから、`./scripts/post-build.sh release` を再実行する。

`Refusing to generate appcast.xml without a valid Sparkle signature`
- `generate-appcast.sh` に渡した署名引数が空文字、空白のみ、`PLACEHOLDER`、`TODO` になっていないか確認する。`./.build/checkouts/Sparkle/bin/sign_update <dmg>` を再実行して取得し直す。

Sparkle が「アップデートのインストールに失敗しました」を表示する
- `.app/Contents/Info.plist` に注入された `SUPublicEDKey` が誤っている可能性がある。設定値と `generate_keys` の出力を照合する。

## Related

- docs/prd/KMD-16-auto-updater.md
- docs/prd/KMD-27-sparkle-eddsa-public-key.md

## Sources

- docs/prd/KMD-27-sparkle-eddsa-public-key.md
- docs/prd/KMD-16-auto-updater.md
- docs/learnings/2026-04-28-KMD-6.md

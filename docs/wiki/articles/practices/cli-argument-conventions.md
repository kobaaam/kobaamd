---
title: CLI 引数渡し規約（stdin 経由化と variadic option 回避）
category: practices
tags: [cli, shell, claude-code, codex, stdin, variadic-options, observability, defense-in-depth]
sources:
  - docs/learnings/2026-05-09-KMD-154.md
  - scripts/wiki/lib/section-context-check.sh
created: 2026-05-09
updated: 2026-05-09
---

# CLI 引数渡し規約（stdin 経由化と variadic option 回避）

## Summary

kobaamd の shell スクリプトから外部 CLI（`claude -p` / `codex exec` / 同種の subprocess CLI）を起動する際の引数渡し規約。可変長オプション（variadic option）後の位置引数が貪欲に取り込まれて空文字になる Commander.js 系のバグを恒久回避するため、長文 prompt は **stdin 経由で渡す**ことを標準とし、`printf '%s'` でフォーマットメタ文字も無害化する。KMD-154 で `--allowedTools <tools...> "$prompt"` の罠を踏んで「subagent 経路が約 1 週間サイレント失敗」した事例の再発防止規約。

## Content

### 1. 背景: variadic option 後置の罠（Commander.js）

<!-- llm-context: KMD-150 で導入された Claude Code subagent 経路が KMD-152 の最小権限化以降サイレント失敗していた根本原因。Commander.js の variadic option 仕様の盲点。 -->

`claude -p` / 同種の Node.js / Commander.js ベース CLI における可変長オプション（`--allowedTools <tools...>` など）は、**続く位置引数まで貪欲に取り込む**仕様を持つ。次のような呼び出しは prompt が空になる:

```bash
# NG: $prompt が --allowedTools に取り込まれ、prompt 引数は空。
#     CLI 側は "Error: Input must be provided either through stdin or as a prompt argument" を返すか、
#     入力なしのデフォルト挙動に倒れる。
claude -p \
  --allowedTools "Read" "Bash(jq:*)" "Bash(python3:*)" \
  --output-format text \
  "$prompt"
```

このバグは **shell の構文エラーとしては検出できない**。`bash -n` も問題を出さず、main session の単発確認も「コマンドが組み立てられた」までしか見ない。実際に CLI を叩いて exit code と出力を観測する smoke test を持たない限り、レビュー段階では拾えないクラスのリグレッションになる。

KMD-154 では KMD-150（subagent 経路導入） → KMD-152（最小権限の `--allowedTools` 化）の流れでこの罠に踏み込み、**約 1 週間（5 月初頭〜5 月 8 日）subagent 経路が本番で 0 件成功**だった（エラーメッセージは `/dev/null` 相当の場所に消えていた）。詳細は [[postmortem-patterns]] パターン 12 の「観測機構の自己観測責務」を参照。

### 2. 規約 1: 長文 prompt は stdin で渡す（標準）

<!-- llm-context: 可変長オプション後置の罠を恒久的に塞ぐ stdin 経由化の規約。printf '%s' でフォーマットメタ文字も同時に無害化する。 -->

shell スクリプトから `claude -p` / `codex exec` などの subprocess CLI に **長文 prompt（複数行・特殊文字を含みうるもの）を渡すときは stdin 経由化を標準**とする:

```bash
# OK: variadic option の後ろに位置引数を置かない。
#     prompt は stdin から読まれるため貪欲取り込みの影響を受けない。
printf '%s' "$prompt" | claude -p \
  --allowedTools "Read" "Bash(jq:*)" "Bash(python3:*)" \
  --output-format text \
  --agent kobaamd_lint_section_context
```

この 1 行で得られる効果:

1. **variadic option 後置バグの恒久回避**: 位置引数を置かないため、`--allowedTools <tools...>` がいくら貪欲でも prompt は影響を受けない
2. **フォーマットメタ文字の無害化**: `printf '%s'` は第 1 引数を変換指定子として扱わない。`%`・`\n`・`\\` などが含まれても prompt がそのまま渡る（`printf "$prompt"` は NG）
3. **`ps aux` の argv からプロンプトが消える副次効果**: 長文 prompt は stdin に流れるため、プロセスリストや shell 履歴から prompt 本文が漏出しない

canonical example: `scripts/wiki/lib/section-context-check.sh` の `run_subagent()` 関数（line 175-180 付近）。`claude -p --agent kobaamd_lint_section_context` を `printf '%s' "$prompt" | claude -p ...` で叩いている。新規スクリプトで同種の呼び出しを書くときはこの実装を参照すること。

### 3. 規約 2: 可変長オプションの後ろに位置引数を置かない

<!-- llm-context: stdin に逃がせない短い prompt でも、変数展開の順序で罠を踏まないための位置取り規約。順序を入れ替えるだけの低コスト回避策。 -->

stdin が使えない事情がある場合（`claude -p` の `--print` モードで stdin が別用途に予約されているケースなど）でも、**可変長オプションを位置引数より後ろに置く**ことで罠を回避できる:

```bash
# NG: --allowedTools が "$prompt" を貪欲に取り込む
claude -p --allowedTools "Read" "Bash(jq:*)" "$prompt"

# OK: 位置引数を先に置き、可変長オプションを後ろに回す
claude -p "$prompt" --allowedTools "Read" "Bash(jq:*)"
```

ただしこの順序入れ替え方式は **stdin 経由化に比べてリグレッション耐性が低い**。後続の改修で他の variadic option（`--add-dir <dirs...>` など）が追加された瞬間に同じ罠を踏み直しうる。**新規実装では stdin 経由化（規約 1）を優先**し、順序入れ替えは既存スクリプトの暫定回避や stdin 不可の制約があるときに限る。

### 4. 規約 3: フォーマットメタ文字を含む可能性がある変数は `printf '%s'` で出す

<!-- llm-context: prompt 文字列に `%`・`\n`・`\\` 等の printf メタ文字が含まれる可能性に備えた防御。stdin 経由化と組み合わせて使う。 -->

prompt 文字列にユーザー入力 / wiki 記事本文 / ファイル内容など **任意のテキスト**が混じる可能性があるなら、`printf` の第 1 引数（書式文字列）に変数を直接置かない:

```bash
# NG: $prompt に "%s" や "\\n" が含まれると printf が誤解釈する
printf "$prompt" | claude -p ...

# OK: '%s' を書式文字列にし、変数は引数として渡す
printf '%s' "$prompt" | claude -p ...

# OK: heredoc も同じ意図で使える（変数展開を有効にしたい場合）
cat <<EOF | claude -p ...
$prompt
EOF
```

`printf '%s'` は変換指定子を含まない静的書式文字列なので、prompt にどんな文字列が来ても解釈バグを起こさない。stdin 経由化（規約 1）と組み合わせると、variadic option 後置バグとフォーマット文字バグの両方を一手に塞げる。

### 5. 規約 4: 観測機構変更時は smoke test を同 PR に含める

<!-- llm-context: 引数渡し方式を変える PR は構文チェックでは挙動変化が拾えないため、実際に CLI を 1 ターゲット叩いて exit code を確認する smoke test を AC に必ず含める運用。 -->

`claude -p` / `codex exec` 等の引数渡し方を変更する PR は、**実際に CLI を 1 ターゲット叩いて exit 0 を確認する smoke test を同 PR に同梱**する。`bash -n` 構文チェックも main session の机上レビューも、本クラスのバグを検出できないため。

具体的には PRD AC に次のような項目を 1 行入れる:

> AC: `scripts/wiki/lib/section-context-check.sh --file docs/wiki/articles/practices/wiki-reference-policy.md` を実行し、subagent 経路で exit 0 を返すこと（mock claude を使った成功 / 失敗パスの手動検証で代替可、ただし PR description に実行ログを貼ること）

KMD-152（最小権限化）にこの AC が無かったために KMD-154 まで 1 週間検出されなかった事実を踏まえ、引数渡し / 観測機構変更 / pipeline-driver 系の PR では smoke test 同梱を必須化する。`kobaamd_create_prd` の Workflow に「観測機構 / CLI 引数渡し変更を検出したら smoke test AC を提案」を追加することで PRD 段階から再発防止する。

詳細は [[postmortem-patterns]] パターン 18「観測機構の変更には観測機構自体の smoke test を初手で含める」を参照。

### 6. 規約 5: CI guard で variadic option 後置パターンを lint する（KMD-172 で実装予定）

<!-- llm-context: 規約 1〜4 が運用で守られなかったときの最終防衛線。CI / pre-commit で `claude -p ... --allowedTools ... "$var"` パターンを正規表現検出する自動 guard。 -->

人間 / AI のレビュー漏れに備えて、`scripts/`・`.claude/` 配下の shell script 全件に対して **variadic option 後置パターンを正規表現で検出する CI guard** を入れる（KMD-172 で実装）。検出対象:

- `claude -p` / `codex exec` の引数列の中で `--allowedTools` / `--add-dir` / `--mcp-config` / 他の `<...>` 可変長系オプションの後ろに、引用符付き変数（`"$..."`）が位置引数として置かれているケース
- `printf "$var"` のような書式文字列に変数を直接置く誤用パターン

将来的には `claude --help` の出力から variadic option を動的に検出して lint ルールを生成することも検討（CLI 仕様変更追従性のため）。CI guard は規約 1〜4 を守れなかった場合の最終防衛線であり、**規約自体の代替ではない**。

## Related

- [[postmortem-patterns]] — パターン 12（観測機構の自己観測責務）/ パターン 18（観測機構変更時の smoke test 必須化）/ パターン 22（stdin 経由化）の根拠
- [[wiki-reference-policy]] — §1.2 で Claude Code subagent 経由の Haiku 起動を規定。本記事の canonical example（`section-context-check.sh`）の上位文脈
- [[security-hardening]] — シェルクォート規約・入力バリデーションの全体方針との接続
- [[subagent-prompt-design]] — subagent 起動時の `--allowedTools` allowlist 設計との関係

## Sources

- docs/learnings/2026-05-09-KMD-154.md
- scripts/wiki/lib/section-context-check.sh（canonical example: `run_subagent()` 関数の `printf '%s' "$prompt" | claude -p ...`）
- KMD-150（[KB2] section-context-missing lint を Claude Code subagent (Haiku) 経由に置換）
- KMD-152（[KB2-followup] section-context-check の subagent を最小権限 allowlist 化、本バグの混入元）
- KMD-154（[KB2-followup] 2 経路の判定差分検証 + subagent 経路の CLI 引数バグ修正）
- KMD-172（[KB2-followup] CI guard で variadic option 後置パターンを lint、本記事の規約 5 の実装予定先）

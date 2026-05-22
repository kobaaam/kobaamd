#!/usr/bin/env bash
# Codex/Gemini-only autonomous pipeline entrypoint.
#
# This script is called by scripts/launchd/run_bundle.sh. It must never invoke
# Claude Code or Anthropic APIs. Claude-era command/agent files may be read only
# as reference specs and translated into Codex/Gemini-backed shell work.

set -euo pipefail

BUNDLE="${1:?Usage: $0 <bundle_name>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$REPO_ROOT/.logs"
PROMPT_FILE="$LOG_DIR/.${BUNDLE}.codex-prompt.md"

mkdir -p "$LOG_DIR"
cd "$REPO_ROOT"

# launchd has a small environment. Import PATH and selected secrets without
# sourcing the whole zshrc in this process. Do not print secret values.
eval "$(zsh -lc 'printf "export PATH=%q\n" "$PATH"' 2>/dev/null)" || true
for key in LINEAR_API_KEY OPENAI_API_KEY GEMINI_API_KEY GH_TOKEN; do
  if [ -z "${!key:-}" ]; then
    value="$(zsh -lic "printf %s \"\${$key:-}\"" 2>/dev/null || true)"
    if [ -n "$value" ]; then
      export "$key=$value"
    fi
  fi
done

# Codex exec runs child shell commands in its own sandbox, where macOS keychain
# backed `gh auth status` may be unavailable even when the parent login shell is
# authenticated. Export an in-memory token from the parent keychain path so child
# `gh` calls can authenticate without printing or persisting the token.
if [ -z "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  value="$(zsh -lic 'gh auth token 2>/dev/null' 2>/dev/null || true)"
  if [ -n "$value" ]; then
    export GH_TOKEN="$value"
  fi
fi

case "$BUNDLE" in
  kobaamd_pipeline_active)
    BUNDLE_GOAL="Run one autonomous active-pipeline cycle: synchronize state, handle Reviewed/in Review/Human in Review work, recover halted work, and if WIP is clear select at most one Todo issue to implement through PR creation."
    DEFAULT_CODEX_MODEL="${KOBAAMD_CODEX_MODEL_ACTIVE:-gpt-5.4}"
    ;;
  kobaamd_pipeline_daily)
    BUNDLE_GOAL="Run the daily maintenance pipeline: archive stale Done issues when appropriate, detect stale work, sync GitHub-facing state, and write concise status comments or logs."
    DEFAULT_CODEX_MODEL="${KOBAAMD_CODEX_MODEL_MAINTENANCE:-gpt-5.4-mini}"
    ;;
  kobaamd_pipeline_weekly)
    BUNDLE_GOAL="Run the weekly pipeline using Codex and Gemini only: research candidate improvements, summarize changelog/status, run deterministic token-usage retro, and use that retro to propose prompt/model-budget/process improvements without invoking Claude."
    DEFAULT_CODEX_MODEL="${KOBAAMD_CODEX_MODEL_MAINTENANCE:-gpt-5.4-mini}"
    ;;
  *)
    BUNDLE_GOAL="Run the requested kobaamd autonomous bundle using Codex and Gemini only."
    DEFAULT_CODEX_MODEL="${KOBAAMD_CODEX_MODEL_DEFAULT:-gpt-5.4-mini}"
    ;;
esac

if [ -z "${CODEX_EXEC_MODEL:-}" ]; then
  export CODEX_EXEC_MODEL="$DEFAULT_CODEX_MODEL"
fi

cat > "$PROMPT_FILE" <<EOF
You are Codex running unattended from launchd for the kobaamd repository.

Bundle: ${BUNDLE}
Goal: ${BUNDLE_GOAL}
Model budget mode: conserve Codex usage. Use the smallest useful live-state reads and shell-driven actions; avoid broad codebase/doc sweeps unless they directly block the next action.

Hard constraints:
- Do not run \`claude\`, \`claude -p\`, Claude Code subagents, Anthropic API calls, or any command that depends on ANTHROPIC_API_KEY.
- Use only Codex, local shell tools, GitHub CLI, Linear via \`scripts/linear/lq.sh\`, and Gemini when LLM research/review is needed.
- Treat \`.claude/agents/*.md\` and \`.claude/commands/*.md\` as read-only reference specifications. Translate their workflow into direct shell/Codex/Gemini steps.
- Prefer \`AGENTS.md\` or \`agent.md\` if present. If they are absent, use \`CLAUDE.md\` only as a compatibility pointer and rely on this prompt plus repository scripts.
- Do not read entire large documents, generated files, or long logs. Use \`rg\`, \`tail\`, and targeted \`sed -n\` ranges; summarize rather than pasting long diffs/logs back into the conversation.
- Do not source \`~/.zshrc\` wholesale. If environment variables are missing, import only the needed key with \`zsh -lic 'printf %s "\$VAR"'\` and never print secret values.
- Never commit or log secrets. Redact API keys, tokens, emails when writing docs or PR bodies.

Autonomy policy for this launchd run:
- Normal pipeline writes are allowed: Linear issue transitions/comments through \`scripts/linear/lq.sh\`, commits on feature branches, pushing feature branches, and creating PRs.
- Linear issue/comment creation is allowed for PRDs, carve-outs, health findings, and quota/rate-limit blocked reports.
- Before any GitHub write or PR/merge flow, run \`gh auth status\`. If GitHub auth is invalid, do not attempt \`git push\`, \`gh pr create\`, or \`gh pr merge\`; leave a Linear comment or log entry with the exact blocked reason and stop that branch cleanly.
- Merging is allowed without human confirmation only for PRs whose Linear issue is already \`Reviewed\` or has an explicit Human-in-Review approval comment. Before merging, run the translated \`kobaamd_merge_pr\` safety checks: locate the PR, verify it is mergeable, run available checks/build verification, then use \`gh pr merge <num> --squash --delete-branch\`.
- If merge safety checks fail, do not ask for confirmation. Move the issue back to \`In Progress\` when appropriate, leave a Linear comment with the failure, and continue/exit cleanly.
- Before Linear writes, use \`LQ_DRY_RUN=1\` when practical to validate payload shape.
- Never push directly to \`main\`, never force-push, never create release tags, never run release/notary workflows, and never use destructive git reset/checkout cleanup.
- When translating legacy \`kobaamd_merge_pr\`, do not follow its old post-merge instruction to commit README changes directly on \`main\`. If README/docs updates are needed after merge, create a follow-up branch/PR or Linear issue instead.
- Do not run Tart VM/E2E, \`brew install\`, launchd install/uninstall, release signing/notary, \`git tag\`, \`gh release\`, or Linear archive unless a human has explicitly approved that class of action.
- Run wiki lint in Codex/Gemini-only mode. If a legacy workflow asks for Claude/Anthropic section-context lint, skip that rule or use a Gemini replacement; do not call Claude/Anthropic.
- If a step requires human judgment, secrets, GUI confirmation, release credentials, or destructive action, leave a Linear comment/log entry and stop that branch of work.
- Keep WIP to one implementation issue unless the repository policy explicitly says otherwise.

Recommended execution shape:
1. Read current repo state: \`git status --short --ignored\`, \`git branch --show-current\`.
2. Read only the relevant sections of \`AGENTS.md\` / \`agent.md\` / \`docs/ai-handoff.md\` if needed; do not load all of them by default.
3. Re-check Linear/PR state live; do not trust stale snapshots.
4. For ${BUNDLE}, read targeted sections of the corresponding \`.claude/commands/${BUNDLE}.md\` only when a workflow detail is unclear.
5. Execute the smallest useful autonomous cycle end-to-end.
6. Run relevant verification. Note that \`swift test\` may be a no-op in this environment; record that risk in PR/test plans.
7. Summarize actions taken, files changed, commands run, and any blocked items.

Return a concise final report.
EOF

export CODEX_RUN_CONTEXT="$BUNDLE"
# The autonomous pipeline must reach Linear/GitHub/Gemini from inside Codex.
# workspace-write blocks outbound DNS/network in Codex exec, so default this
# launchd entrypoint to full access. The prompt above remains the policy gate
# for disallowed actions such as force-push, release, notary, or destructive git.
export CODEX_EXEC_SANDBOX="${CODEX_EXEC_SANDBOX:-danger-full-access}"
export CODEX_EXEC_CD="$REPO_ROOT"

"$SCRIPT_DIR/run.sh" < "$PROMPT_FILE"

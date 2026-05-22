# Autopilot Sandbox Audit

Last updated: 2026-05-15

This document classifies legacy `.claude/commands` and `.claude/agents` workflows for Codex/Gemini-only autopilot. Codex may read legacy files as workflow specs, but must not execute Claude/Anthropic paths.

## Allowed

| Workflow | Allowed operations | Notes |
|---|---|---|
| `kobaamd_implement_code` | feature branch, commit, feature branch push, PR create, Linear transition/comment | No direct `main` push. Use Codex implementation. |
| `kobaamd_fix_pr_comments` | commit/push to existing PR branch, Linear transition/comment | No force push. |
| `kobaamd_rework_issue` | PRD/doc updates, Codex implementation, branch push, Linear comment/transition | Human-question branches should comment and stop. |
| `kobaamd_review_pr` | PR diff review, Gemini review, Linear comment/transition | Clean approval may move to `Reviewed`; concerns go to `Human in Review` or `In Progress`. |
| `kobaamd_review_prd` / `kobaamd_create_prd` | Gemini research, PRD docs, Linear transition/comment | Redact secrets before writing PRD logs. |
| `kobaamd_research_create_ticket` | Gemini research, Linear issue create | Allowed for backlog PRD-lite creation. |
| `kobaamd_carve_concerns` | Linear issue create/comment/transition | Allowed when concern is auto-carveable or human has approved carve-out. |
| `kobaamd_validate_build` | `swift build`, `swift test`, debug `post-build.sh`, Linear build comment | Skip Tart E2E unless explicitly approved. |
| `kobaamd_review_security` | Static diff/security review, Linear comment | No release/signing actions. |
| `kobaamd_report_status` / `summarize_changelog` / `detect_stale` / `snapshot_state` | Read-only summaries plus Linear comments/logs | Safe in `workspace-write`. |

## Conditionally Allowed

| Workflow | Condition |
|---|---|
| `kobaamd_merge_pr` | Allowed only for Linear `Reviewed` issues or explicit Human-in-Review approval translated to `Reviewed`. Use `gh pr merge --squash --delete-branch` after safety checks. Do not follow legacy README direct-to-main commit step. |
| `kobaamd_update_wiki` / `review_postmortem` | Allowed on feature branches/PRs. If docs need follow-up after merge, create a branch/PR or Linear issue. |
| `scripts/post-build.sh` | Allowed for debug verification. Release usage requires human approval. |

## Skip Or Replace

| Workflow | Reason | Replacement |
|---|---|---|
| `scripts/wiki/ask.sh` old Anthropic path | Requires `ANTHROPIC_API_KEY` | Replaced with Gemini-backed implementation. |
| `scripts/wiki/lint.sh` rule 4 section-context route | Legacy default used Claude subagent / Anthropic | Rule 4 is skipped by default in Codex/Gemini autopilot. Use Gemini replacement later if needed. |
| `scripts/wiki/lib/section-context-check.sh` | Calls `claude -p` or Anthropic legacy API | Do not invoke from autopilot. |
| `.claude/agents/kobaamd_lint_section_context.md` | Claude Haiku subagent | Spec reference only. |

## Human Approval Required

| Operation | Reason |
|---|---|
| `kobaamd_archive_done` / Linear archive | Strong state mutation. Allow only after explicit policy approval, e.g. Done older than N days. |
| Tart VM / E2E scripts | VM clone/run/delete, GUI, SSH, `osascript`, `xcrun`. |
| `brew install`, global package installs | Persistent local environment mutation. |
| launchd install/uninstall/bootstrap/bootout | OS state mutation. |
| release/tag/appcast/notary/signing | Release credentials and irreversible external effects. |
| direct `main` push, force push, destructive git cleanup | Project safety. |

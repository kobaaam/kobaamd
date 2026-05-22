import { execSync, spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import { phase, log, agent, costUsd } from "./lib/workflow.mjs";

function parseArgs(argv) {
  const args = { execute: false, codex: true, promoteCount: 5 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--execute") args.execute = true;
    else if (argv[i] === "--no-codex") args.codex = false;
    else if (argv[i] === "--promote") args.promoteCount = Number(argv[++i]);
  }
  return args;
}
const ARGS = parseArgs(process.argv.slice(2));
log(`mode: ${ARGS.execute ? "EXECUTE (live)" : "DRY-RUN"}  codex=${ARGS.codex}  promote_count=${ARGS.promoteCount}`);

function lq(cmd) {
  return execSync(`./scripts/linear/lq.sh ${cmd}`, { encoding: "utf-8" });
}
function lqJson(cmd) {
  return JSON.parse(lq(cmd));
}
function gh(cmd) {
  try {
    return execSync(`gh ${cmd}`, { encoding: "utf-8" });
  } catch (e) {
    return null;
  }
}
function slugify(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30);
}
function sortByPriority(issues) {
  return [...issues].sort((a, b) => {
    const pa = a.priority === 0 || a.priority == null ? 99 : a.priority;
    const pb = b.priority === 0 || b.priority == null ? 99 : b.priority;
    return pa - pb;
  });
}

const metrics = { steps: [], side_effects: [], totals: { input: 0, output: 0, cost: 0 } };
function record(name, model, usage, cost, elapsed_ms, extra = {}) {
  const row = {
    name,
    model,
    input_tokens: usage?.input_tokens ?? 0,
    output_tokens: usage?.output_tokens ?? 0,
    cost_usd: Number((cost ?? 0).toFixed(6)),
    elapsed_ms,
    ...extra,
  };
  metrics.steps.push(row);
  metrics.totals.input += row.input_tokens;
  metrics.totals.output += row.output_tokens;
  metrics.totals.cost += cost ?? 0;
  log(`  ${name} [${model}] in=${row.input_tokens} out=${row.output_tokens} cost=$${row.cost_usd.toFixed(6)} ${elapsed_ms}ms`);
}
function recordSideEffect(op, detail) {
  metrics.side_effects.push({ op, detail, ts: new Date().toISOString() });
  log(`  [side-effect] ${op}: ${detail}`);
}

const SONNET = "claude-sonnet-4-6";
const HAIKU = "claude-haiku-4-5-20251001";

// ============================================================
// Step 0b: status integrity (no LLM)
// ============================================================
phase("Step 0b: status integrity (no LLM)");
const inprog = lqJson(`issue.list --team KMD --state "In Progress" --limit 20`);
const inreview = lqJson(`issue.list --team KMD --state "in Review" --limit 20`);
const humanreview = lqJson(`issue.list --team KMD --state "Human in Review" --limit 20`);
const reviewed = lqJson(`issue.list --team KMD --state Reviewed --limit 20`);
let todos = lqJson(`issue.list --team KMD --state Todo --limit 50`);
const draft = lqJson(`issue.list --team KMD --state draft --limit 20`);
log(`In Progress=${inprog.length} in Review=${inreview.length} Human in Review=${humanreview.length} Reviewed=${reviewed.length} Todo=${todos.length} draft=${draft.length}`);

// ============================================================
// Step 0d (NEW): Backlog auto-promote when Todo is empty
// ============================================================
phase(`Step 0d: Backlog auto-promote (if Todo empty)`);
if (todos.length === 0) {
  const backlog = lqJson(`issue.list --team KMD --state Backlog --limit 250`);
  const promote = sortByPriority(backlog).slice(0, ARGS.promoteCount);
  log(`Todo is empty. Promoting top ${promote.length} backlog issues by priority...`);
  for (const i of promote) {
    log(`  -> ${i.identifier} (P${i.priority ?? "none"}): ${i.title}`);
    if (ARGS.execute) {
      lq(`issue.transition ${i.identifier} Todo`);
      recordSideEffect("issue.transition", `${i.identifier}: Backlog -> Todo`);
    }
  }
  todos = ARGS.execute ? lqJson(`issue.list --team KMD --state Todo --limit 50`) : promote;
} else {
  log(`Todo has ${todos.length} issue(s), promotion not triggered`);
}

// ============================================================
// Step 0b': no-op early return guard
// ============================================================
phase("Step 0b': no-op guard");
const conflictingRaw = gh(`pr list --json number,mergeable --jq '[.[] | select(.mergeable == "CONFLICTING")] | length'`);
const conflicting = Number((conflictingRaw ?? "0").trim() || "0");
const guardPass =
  reviewed.length === 0 &&
  humanreview.length === 0 &&
  inreview.length === 0 &&
  conflicting === 0 &&
  draft.length === 0 &&
  (inprog.length >= 1 || todos.length === 0);
log(`guard: reviewed=${reviewed.length} human=${humanreview.length} in_review=${inreview.length} conflicting=${conflicting} draft=${draft.length} in_progress=${inprog.length} todo=${todos.length} → ${guardPass ? "EARLY RETURN" : "PROCEED"}`);

if (!guardPass) {
  // ============================================================
  // Phase A: review_pr (SDK) for open PRs (up to 3)
  // ============================================================
  phase("Phase A: review_pr (Sonnet) for open PRs");
  const prsRaw = gh(`pr list --state open --json number,title,headRefName,additions,deletions --limit 5`);
  const prs = prsRaw ? JSON.parse(prsRaw) : [];
  log(`open PRs: ${prs.length}`);
  const PR_SYSTEM = `You are kobaamd_review_pr (SDK simulation). Strict reviewer persona separate from the implementer.
Criteria: Swift naming, missing tests, perf/memory, PRD AC alignment.
Clean APPROVE → Reviewed; concerns or [BREAKING] → Human in Review.`;
  for (const pr of prs.slice(0, 3)) {
    const start = Date.now();
    const r = await agent({
      prompt: `PR #${pr.number}: "${pr.title}" branch=${pr.headRefName} (+${pr.additions} / -${pr.deletions}). Verdict & 1-line reason.`,
      schema: { verdict: "APPROVE|REQUEST_CHANGES|HUMAN_REVIEW", reason: "string <=120 chars" },
      model: SONNET,
      systemText: PR_SYSTEM,
      maxTokens: 200,
    });
    record(`review_pr#${pr.number}`, "sonnet-4.6", r.usage, costUsd(r.usage, SONNET), Date.now() - start, {
      verdict: r.parsed?.verdict,
      reason: r.parsed?.reason,
    });
  }

  // ============================================================
  // Phase B: pick highest-priority Todo and process 1 issue
  // ============================================================
  const sortedTodos = sortByPriority(todos);
  const target = sortedTodos[0];
  if (target) {
    log(`target: ${target.identifier} (P${target.priority ?? "none"}): ${target.title}`);

    // ----- step 6: create_prd -----
    phase(`Phase B step 6: create_prd for ${target.identifier}`);
    const PRD_SYSTEM = `You are kobaamd_create_prd (SDK simulation). Output a concise but actionable PRD with all sections.`;
    let start = Date.now();
    const prd = await agent({
      prompt: `Draft PRD for ${target.identifier} "${target.title}". Sections:
- Background (why this matters)
- Goal (1 sentence)
- Scope (in/out)
- Acceptance Criteria (3-5 bullets, testable)
- Risks (1-2 with mitigation)
- Implementation hints (Swift files / functions to touch, if obvious from title)`,
      schema: {
        background: "string <=300 chars",
        goal: "string <=120 chars",
        scope_in: "string[]",
        scope_out: "string[]",
        acceptance_criteria: "string[] (3-5 items, testable)",
        risks: "string[]",
        impl_hints: "string[]",
      },
      model: SONNET,
      systemText: PRD_SYSTEM,
      maxTokens: 1500,
    });
    record(`create_prd:${target.identifier}`, "sonnet-4.6", prd.usage, costUsd(prd.usage, SONNET), Date.now() - start);

    let prdMd = "";
    if (prd.parsed && !prd.parsed._parse_error) {
      const p = prd.parsed;
      prdMd =
        `# ${target.identifier}: ${target.title}\n\n` +
        `## Background\n${p.background ?? ""}\n\n` +
        `## Goal\n${p.goal ?? ""}\n\n` +
        `## Scope\n\n**In:**\n${(p.scope_in ?? []).map((x) => `- ${x}`).join("\n")}\n\n**Out:**\n${(p.scope_out ?? []).map((x) => `- ${x}`).join("\n")}\n\n` +
        `## Acceptance Criteria\n${(p.acceptance_criteria ?? []).map((x) => `- ${x}`).join("\n")}\n\n` +
        `## Risks\n${(p.risks ?? []).map((x) => `- ${x}`).join("\n")}\n\n` +
        `## Implementation Hints\n${(p.impl_hints ?? []).map((x) => `- ${x}`).join("\n")}\n`;

      if (ARGS.execute) {
        const prdFile = `/tmp/prd-${target.identifier}.md`;
        await fs.writeFile(prdFile, prdMd);
        lq(`issue.update ${target.identifier} --body @${prdFile}`);
        recordSideEffect("issue.update", `${target.identifier}: PRD written to description (${prdMd.length} chars)`);
      }
    }

    // ----- step 7: review_prd -----
    phase(`Phase B step 7: review_prd`);
    start = Date.now();
    const rprd = await agent({
      prompt: `Review this PRD for ${target.identifier}:\n\n${prdMd}\n\nVerdict + reason.`,
      schema: { verdict: "PASS|REQUEST_REVISION", reason: "string <=200 chars" },
      model: SONNET,
      systemText: `You are kobaamd_review_prd (SDK simulation, separate persona). Be skeptical: missing AC, ambiguous scope, untested risks. PASS only if AC are testable and scope is unambiguous.`,
      maxTokens: 300,
    });
    record(`review_prd:${target.identifier}`, "sonnet-4.6", rprd.usage, costUsd(rprd.usage, SONNET), Date.now() - start, {
      verdict: rprd.parsed?.verdict,
    });

    if (rprd.parsed?.verdict !== "PASS") {
      log(`PRD review = ${rprd.parsed?.verdict}; continuing anyway (1-cycle PoC, no revision loop yet)`);
    }

    // ----- step 8: assign_work (priority-aware) -----
    phase("Phase B step 8: assign_work (priority-aware)");
    start = Date.now();
    const aw = await agent({
      prompt: `WIP=1 gate. In Progress count: ${inprog.length}. Todo (sorted by priority):
${sortedTodos.slice(0, 5).map((t) => `- ${t.identifier} (P${t.priority ?? "none"}): ${t.title}`).join("\n")}

Decide PROCEED or BLOCKED. If PROCEED, the next issue is the highest-priority Todo (P1 best, P0/null worst).`,
      schema: { decision: "PROCEED|BLOCKED", next_issue: "KMD-XX", reason: "string <=120 chars" },
      model: HAIKU,
      systemText: `kobaamd_assign_work (SDK simulation). WIP=1 rule: BLOCKED if In Progress > 0. Pick highest-priority Todo otherwise.`,
      maxTokens: 200,
    });
    record(`assign_work`, "haiku-4.5", aw.usage, costUsd(aw.usage, HAIKU), Date.now() - start, {
      decision: aw.parsed?.decision,
      next: aw.parsed?.next_issue,
    });

    // ----- step 9-10: implement_code via Codex CLI -----
    if (ARGS.execute && ARGS.codex && aw.parsed?.decision === "PROCEED") {
      phase(`Phase B step 9-10: implement_code via Codex (target=${target.identifier})`);

      lq(`issue.transition ${target.identifier} "In Progress"`);
      recordSideEffect("issue.transition", `${target.identifier}: Todo -> In Progress`);

      const branch = `feature/${target.identifier}-${slugify(target.title)}`;
      try {
        execSync(`git checkout -b ${branch} 2>/dev/null || git checkout ${branch}`, { stdio: "pipe" });
        recordSideEffect("git.branch", `checkout: ${branch}`);
      } catch (e) {
        log(`branch checkout failed: ${e.message}`);
      }

      const codexPrompt = `# ${target.identifier}: ${target.title}

## PRD
${prdMd}

## Task
Implement this issue end-to-end. Produce minimal, correct Swift code following the existing project conventions in this repository. Touch only files that are necessary. After making changes, ensure \`swift build\` passes (you can run it). Do not commit; the wrapper handles commit / push.

## Constraints
- Follow Swift conventions in Sources/.
- Add tests in Tests/ if the change is non-trivial.
- Do not create new top-level documents unless explicitly part of AC.
- Keep the change minimal and focused.`;

      log(`spawning codex (timeout 25 min)...`);
      const codexStart = Date.now();
      const codexResult = spawnSync("./scripts/codex/run.sh", {
        input: codexPrompt,
        encoding: "utf-8",
        timeout: 25 * 60 * 1000,
        maxBuffer: 100 * 1024 * 1024,
      });
      const codexElapsed = Date.now() - codexStart;
      log(`codex finished in ${(codexElapsed / 1000).toFixed(1)}s, exit=${codexResult.status}, signal=${codexResult.signal ?? "none"}`);
      metrics.codex = {
        elapsed_ms: codexElapsed,
        exit: codexResult.status,
        signal: codexResult.signal,
        stdout_len: codexResult.stdout?.length ?? 0,
        stderr_len: codexResult.stderr?.length ?? 0,
      };

      if (codexResult.status !== 0) {
        log(`codex failed; rolling back Linear to Todo`);
        lq(`issue.transition ${target.identifier} Todo`);
        recordSideEffect("issue.transition", `${target.identifier}: In Progress -> Todo (codex failure rollback)`);
      } else {
        const diff = execSync("git status --short", { encoding: "utf-8" });
        if (!diff.trim()) {
          log("no changes from codex; rolling back to Todo");
          lq(`issue.transition ${target.identifier} Todo`);
          recordSideEffect("issue.transition", `${target.identifier}: In Progress -> Todo (no diff)`);
        } else {
          log(`codex produced changes:\n${diff}`);
          try {
            execSync(`swift build 2>&1 | tail -30`, { stdio: "pipe" });
            log("swift build OK");
          } catch (e) {
            log(`swift build FAILED:\n${e.stdout?.toString().slice(-2000) ?? e.message}`);
          }
          const commitMsg = `${target.identifier}: ${target.title}`.replace(/"/g, '\\"');
          execSync(`git add -A && git commit -m "${commitMsg}"`, { stdio: "pipe" });
          execSync(`git push -u origin ${branch}`, { stdio: "pipe" });
          recordSideEffect("git.push", `${branch} pushed`);

          const prBody = `Closes ${target.identifier}\n\n${prd.parsed?.background ?? target.title}`;
          const prBodyFile = `/tmp/pr-body-${target.identifier}.md`;
          await fs.writeFile(prBodyFile, prBody);
          const prUrl = execSync(
            `gh pr create --title "[${target.identifier}] ${target.title.replace(/"/g, '\\"')}" --body-file ${prBodyFile}`,
            { encoding: "utf-8" }
          ).trim();
          log(`PR created: ${prUrl}`);
          recordSideEffect("gh.pr_create", prUrl);

          lq(`issue.transition ${target.identifier} "in Review"`);
          recordSideEffect("issue.transition", `${target.identifier}: In Progress -> in Review`);
        }
      }
    } else if (ARGS.execute && !ARGS.codex) {
      log("execute mode but --no-codex set; skipping implement_code");
    }
  } else {
    log("no Todo to process (post-promote)");
  }
}

// ============================================================
// Summary
// ============================================================
phase("Summary");
const summary = {
  execute_mode: ARGS.execute,
  steps: metrics.steps,
  side_effects: metrics.side_effects,
  totals: {
    input_tokens: metrics.totals.input,
    output_tokens: metrics.totals.output,
    cost_usd: Number(metrics.totals.cost.toFixed(6)),
    step_count: metrics.steps.length,
  },
  codex: metrics.codex,
};
console.log(JSON.stringify(summary, null, 2));

const ts = new Date().toISOString().replace(/[:.]/g, "-");
const mdPath = `artifacts/pipeline-workflow-run-${ts}.md`;
let md = `# pipeline_active workflow run (SDK PoC) — ${ts}\n\n`;
md += `- mode: ${ARGS.execute ? "EXECUTE" : "DRY-RUN"}\n`;
md += `- steps: ${summary.totals.step_count}\n`;
md += `- total input: ${summary.totals.input_tokens}\n`;
md += `- total output: ${summary.totals.output_tokens}\n`;
md += `- total cost: $${summary.totals.cost_usd}\n`;
if (metrics.codex) md += `- codex: exit=${metrics.codex.exit} elapsed_ms=${metrics.codex.elapsed_ms}\n`;
md += `\n## Per-step (LLM)\n\n| step | model | input | output | cost USD | latency ms | note |\n|---|---|--:|--:|--:|--:|---|\n`;
for (const s of metrics.steps) {
  const note = s.verdict ?? s.decision ?? "";
  md += `| ${s.name} | ${s.model} | ${s.input_tokens} | ${s.output_tokens} | ${s.cost_usd.toFixed(6)} | ${s.elapsed_ms} | ${note} |\n`;
}
md += `\n## Side effects (Linear / git / gh)\n\n`;
for (const se of metrics.side_effects) md += `- \`${se.op}\`: ${se.detail}\n`;
await fs.mkdir("artifacts", { recursive: true });
await fs.writeFile(mdPath, md);
log(`written: ${mdPath}`);

await fs.mkdir(".logs", { recursive: true });
await fs.appendFile(
  ".logs/pipeline_workflow_run.log",
  `${new Date().toISOString()} mode=${ARGS.execute ? "exec" : "dry"} steps=${summary.totals.step_count} in=${summary.totals.input_tokens} out=${summary.totals.output_tokens} cost=$${summary.totals.cost_usd} side_effects=${metrics.side_effects.length}\n`,
);

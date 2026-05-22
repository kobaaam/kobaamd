import { execSync } from "node:child_process";
import fs from "node:fs/promises";
import { phase, log, agent, costUsd, PRICING } from "./lib/workflow.mjs";

function lqJson(cmd) {
  return JSON.parse(execSync(`./scripts/linear/lq.sh ${cmd}`, { encoding: "utf-8" }));
}

phase("Fetch backlog issues");
const issues = lqJson(`issue.list --team KMD --state Backlog --limit 250`);
log(`fetched ${issues.length} backlog issues`);

if (issues.length === 0) {
  console.log(JSON.stringify({ error: "backlog is empty" }, null, 2));
  process.exit(0);
}

const summary = issues
  .map((i) => `- ${i.identifier} (P${i.priority ?? "?"}, updated=${i.updatedAt?.slice(0, 10)}): ${i.title}`)
  .join("\n");

const SYSTEM = `You are a product engineer triaging the kobaamd backlog.
Strategic goal: migrate pipeline_active off claude -p onto a self-hosted Anthropic SDK + workflow runner so we control caching, Batch API, and model mixing.
Linear priority: 1=Urgent, 2=High, 3=Medium, 4=Low (0=none).
Newer issues may reflect current reality better than old ones.
Pick exactly 5 issues that should be tackled next based on impact, feasibility, and strategic alignment.`;

const PROMPT = `Backlog (${issues.length} items):
${summary}

Select exactly 5 issues to tackle next. For each, give a short rationale (<=80 chars).`;

const SCHEMA = {
  selected: [{ identifier: "KMD-XX", rationale: "string (<=80 chars)" }],
  overall_rationale: "string (<=160 chars)",
};

const MODELS = [
  { id: "claude-opus-4-7", label: "opus-4.7" },
  { id: "claude-sonnet-4-6", label: "sonnet-4.6" },
  { id: "claude-haiku-4-5-20251001", label: "haiku-4.5" },
];

phase("Run 3 models");
const results = [];
for (const m of MODELS) {
  log(`running ${m.label}...`);
  const start = Date.now();
  const r = await agent({
    prompt: PROMPT,
    schema: SCHEMA,
    model: m.id,
    systemText: SYSTEM,
    maxTokens: 1024,
  });
  const elapsed_ms = Date.now() - start;
  const cost = costUsd(r.usage, m.id) ?? 0;
  results.push({
    model: m.label,
    model_id: m.id,
    elapsed_ms,
    usage: r.usage,
    cost_usd: Number(cost.toFixed(6)),
    selected: r.parsed?.selected ?? null,
    overall_rationale: r.parsed?.overall_rationale ?? null,
    _parse_error: r.parsed?._parse_error ?? null,
    _raw: r.parsed?._parse_error ? r.parsed?._raw : undefined,
  });
}

phase("Compare");
function row(r) {
  return {
    model: r.model,
    elapsed_ms: r.elapsed_ms,
    input_tokens: r.usage.input_tokens,
    output_tokens: r.usage.output_tokens,
    cost_usd: r.cost_usd,
    n_selected: r.selected?.length ?? 0,
  };
}
const table = results.map(row);
console.log(JSON.stringify({ backlog_size: issues.length, table, results }, null, 2));

const ts = new Date().toISOString().replace(/[:.]/g, "-");
const mdPath = `artifacts/prioritize-backlog-${ts}.md`;
let md = `# Prioritize Backlog Comparison (${ts})\n\n`;
md += `- backlog size: ${issues.length}\n`;
md += `- shared system prompt: ${SYSTEM.length} chars\n\n`;
md += `## Cost & latency\n\n| model | input | output | latency (ms) | cost (USD) | parse ok |\n|---|--:|--:|--:|--:|:--:|\n`;
for (const r of results) {
  md += `| ${r.model} | ${r.usage.input_tokens} | ${r.usage.output_tokens} | ${r.elapsed_ms} | ${r.cost_usd.toFixed(6)} | ${r._parse_error ? "❌" : "✅"} |\n`;
}
md += `\n## Selections per model\n\n`;
for (const r of results) {
  md += `### ${r.model}\n\n`;
  if (r._parse_error) {
    md += `parse error: ${r._parse_error}\n\n\`\`\`\n${r._raw ?? ""}\n\`\`\`\n\n`;
    continue;
  }
  md += `**overall**: ${r.overall_rationale ?? "(none)"}\n\n`;
  for (const s of r.selected ?? []) md += `- **${s.identifier}**: ${s.rationale}\n`;
  md += `\n`;
}

md += `## Overlap analysis\n\n`;
const sets = results.map((r) => new Set((r.selected ?? []).map((s) => s.identifier)));
const allPicks = new Set(sets.flatMap((s) => [...s]));
md += `| issue | opus | sonnet | haiku |\n|---|:--:|:--:|:--:|\n`;
for (const id of [...allPicks].sort()) {
  const ck = (s) => (s.has(id) ? "✓" : "");
  md += `| ${id} | ${ck(sets[0])} | ${ck(sets[1])} | ${ck(sets[2])} |\n`;
}

await fs.mkdir("artifacts", { recursive: true });
await fs.writeFile(mdPath, md);
log(`comparison written: ${mdPath}`);

await fs.mkdir(".logs", { recursive: true });
const logLine = `${new Date().toISOString()} backlog=${issues.length} ` +
  results.map((r) => `${r.model}:in=${r.usage.input_tokens},out=${r.usage.output_tokens},cost=$${r.cost_usd}`).join(" ") + "\n";
await fs.appendFile(".logs/pipeline_prioritize_backlog.log", logLine);

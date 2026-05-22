import { execSync } from "node:child_process";
import fs from "node:fs/promises";
import { phase, log, agent, costUsd, PRICING } from "./lib/workflow.mjs";

function parseArgs(argv) {
  const args = { dryRun: false, days: 7 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--dry-run") args.dryRun = true;
    else if (argv[i] === "--days") args.days = Number(argv[++i]);
  }
  return args;
}

const ARGS = parseArgs(process.argv.slice(2));

function lqJson(cmd) {
  return JSON.parse(execSync(`./scripts/linear/lq.sh ${cmd}`, { encoding: "utf-8" }));
}

phase("Fetch Done issues");
const issues = lqJson(`issue.list --team KMD --state Done --limit 250`);
log(`fetched ${issues.length} Done issues`);

const threshold = new Date(Date.now() - ARGS.days * 86400 * 1000);
const stale = issues.filter((i) => new Date(i.updatedAt) < threshold);
log(`${stale.length} stale (older than ${ARGS.days} days)`);

if (stale.length === 0) {
  console.log(JSON.stringify({ issues_processed: 0, archivable: 0 }, null, 2));
  process.exit(0);
}

const TAXONOMY = `You classify Linear issues for archival in the kobaamd project.
Categories:
- ARCHIVE: state is Done, no recent activity beyond N days, safe to archive permanently.
- KEEP: state is Done but title suggests ongoing utility, has open dependencies, or is referenced as a milestone.
- NEEDS_REVIEW: title or metadata is ambiguous; classification is not clearly ARCHIVE or KEEP.

Linear free plan has a 250-issue cap, so archiving stale Done issues is the default.`;

phase("Pass1: Haiku 4.5 classify");
const HAIKU = "claude-haiku-4-5-20251001";
const SONNET = "claude-sonnet-4-6";
const pass1 = [];
let p1u = { input: 0, output: 0, cache_read: 0, cache_create_5m: 0 };
let p1Cost = 0;

for (const i of stale) {
  const prompt = `Issue: ${i.identifier} "${i.title}" (state=${i.state?.name}, priority=${i.priority}, updatedAt=${i.updatedAt})`;
  const r = await agent({
    prompt,
    schema: { class: "ARCHIVE|KEEP|NEEDS_REVIEW", evidence: "string (<=100 chars)", confidence: "high|medium|low" },
    model: HAIKU,
    cache: "ephemeral",
    systemText: TAXONOMY,
    maxTokens: 200,
  });
  pass1.push({ identifier: i.identifier, ...(r.parsed ?? {}), _usage: r.usage });
  p1u.input += r.usage.input_tokens ?? 0;
  p1u.output += r.usage.output_tokens ?? 0;
  p1u.cache_read += r.usage.cache_read_input_tokens ?? 0;
  p1u.cache_create_5m += r.usage.cache_creation?.ephemeral_5m_input_tokens ?? 0;
  p1Cost += costUsd(r.usage, HAIKU) ?? 0;
}
log(`Pass1 usage: in=${p1u.input} out=${p1u.output} cache_read=${p1u.cache_read} cache_create=${p1u.cache_create_5m} cost=$${p1Cost.toFixed(6)}`);

phase("Pass2: Sonnet 4.6 refute low-confidence (3-vote)");
const lowConf = pass1.filter((r) => r.confidence === "low" || r.class === "NEEDS_REVIEW" || !r.class);
log(`${lowConf.length} candidates need refute`);
const pass2 = [];
let p2u = { input: 0, output: 0, cache_read: 0, cache_create_5m: 0 };
let p2Cost = 0;

for (const r of lowConf) {
  const issue = stale.find((i) => i.identifier === r.identifier);
  const votes = [];
  for (let v = 0; v < 3; v++) {
    const prompt = `Re-classify ${issue.identifier} "${issue.title}" (updatedAt=${issue.updatedAt}). Prior call gave class=${r.class} evidence="${r.evidence}". Be skeptical.`;
    const res = await agent({
      prompt,
      schema: { class: "ARCHIVE|KEEP|NEEDS_REVIEW", evidence: "string (<=100 chars)" },
      model: SONNET,
      cache: "ephemeral",
      systemText: TAXONOMY,
      maxTokens: 200,
    });
    votes.push(res.parsed ?? {});
    p2u.input += res.usage.input_tokens ?? 0;
    p2u.output += res.usage.output_tokens ?? 0;
    p2u.cache_read += res.usage.cache_read_input_tokens ?? 0;
    p2u.cache_create_5m += res.usage.cache_creation?.ephemeral_5m_input_tokens ?? 0;
    p2Cost += costUsd(res.usage, SONNET) ?? 0;
  }
  const tally = {};
  for (const v of votes) tally[v.class] = (tally[v.class] ?? 0) + 1;
  const [winner] = Object.entries(tally).sort((a, b) => b[1] - a[1])[0] ?? ["NEEDS_REVIEW"];
  pass2.push({ identifier: r.identifier, class: winner, votes });
}
log(`Pass2 usage: in=${p2u.input} out=${p2u.output} cost=$${p2Cost.toFixed(6)}`);

phase("Pass3: emit TSV + archive");
const overrides = new Map(pass2.map((r) => [r.identifier, r.class]));
const final = pass1.map((r) => ({
  identifier: r.identifier,
  class: overrides.get(r.identifier) ?? r.class ?? "NEEDS_REVIEW",
  evidence: r.evidence ?? "",
}));
const archivable = final.filter((r) => r.class === "ARCHIVE");

const tsvLines = ["identifier\tclass\tevidence"];
for (const r of final) tsvLines.push(`${r.identifier}\t${r.class}\t${(r.evidence ?? "").replace(/\t/g, " ")}`);
const ts = new Date().toISOString().replace(/[:.]/g, "-");
const tsvPath = `artifacts/archive-done-${ts}.tsv`;
await fs.mkdir("artifacts", { recursive: true });
await fs.writeFile(tsvPath, tsvLines.join("\n") + "\n");
log(`TSV: ${tsvPath} (ARCHIVE=${archivable.length} other=${final.length - archivable.length})`);

if (!ARGS.dryRun) {
  for (const r of archivable) {
    execSync(`./scripts/linear/lq.sh issue.archive ${r.identifier}`, { stdio: "inherit" });
  }
  log(`archived ${archivable.length} issues`);
} else {
  log(`dry-run: would archive ${archivable.length} issues`);
}

const summary = {
  dry_run: ARGS.dryRun,
  days: ARGS.days,
  issues_total_done: issues.length,
  issues_stale: stale.length,
  archivable: archivable.length,
  pass1: { model: HAIKU, ...p1u, cost_usd: Number(p1Cost.toFixed(6)) },
  pass2: { model: SONNET, refuted: lowConf.length, ...p2u, cost_usd: Number(p2Cost.toFixed(6)) },
  total_cost_usd: Number((p1Cost + p2Cost).toFixed(6)),
  tsv: tsvPath,
};
console.log(JSON.stringify(summary, null, 2));

await fs.mkdir(".logs", { recursive: true });
const logLine = `${new Date().toISOString()} stale=${stale.length} archivable=${archivable.length} p1_in=${p1u.input} p1_out=${p1u.output} p2_in=${p2u.input} p2_out=${p2u.output} total_cost=$${(p1Cost + p2Cost).toFixed(6)} dry_run=${ARGS.dryRun}\n`;
await fs.appendFile(".logs/pipeline_archive_done.log", logLine);

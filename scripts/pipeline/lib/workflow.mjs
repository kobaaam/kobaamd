import Anthropic from "@anthropic-ai/sdk";
import fs from "node:fs/promises";

const client = new Anthropic();

const AGENT_CAP = 980;
let agentCount = 0;

export function resetAgentCount() {
  agentCount = 0;
}

export function getAgentCount() {
  return agentCount;
}

export function phase(name) {
  process.stderr.write(`\n=== ${name} ===\n`);
}

export function log(msg) {
  process.stderr.write(`[${new Date().toISOString()}] ${msg}\n`);
}

export async function pipeline(items, fn) {
  const out = [];
  for (const item of items) out.push(await fn(item));
  return out;
}

export async function parallel(fns, { concurrency = 8 } = {}) {
  if (agentCount + fns.length > AGENT_CAP) {
    throw new Error(`agent cap would be exceeded: ${agentCount} + ${fns.length} > ${AGENT_CAP}`);
  }
  const results = new Array(fns.length);
  let next = 0;
  const limit = Math.max(1, Math.min(concurrency, fns.length));
  const worker = async () => {
    while (true) {
      const i = next++;
      if (i >= fns.length) return;
      results[i] = await fns[i]();
    }
  };
  await Promise.all(Array.from({ length: limit }, worker));
  return results;
}

function stripFrontmatter(raw) {
  if (!raw.startsWith("---\n")) return raw;
  const end = raw.indexOf("\n---\n", 4);
  if (end < 0) return raw;
  return raw.slice(end + 5);
}

export async function agent({
  prompt,
  schema = null,
  model = "claude-haiku-4-5-20251001",
  cache = null,
  systemFromFile = null,
  systemText = null,
  maxTokens = 1024,
}) {
  if (agentCount >= AGENT_CAP) {
    throw new Error(`agent cap exceeded: ${agentCount} >= ${AGENT_CAP}`);
  }
  agentCount++;

  let system = systemText;
  if (systemFromFile) {
    const raw = await fs.readFile(systemFromFile, "utf-8");
    system = stripFrontmatter(raw);
  }

  const params = { model, max_tokens: maxTokens, messages: [] };
  if (system) {
    const block = { type: "text", text: system };
    if (cache === "ephemeral") block.cache_control = { type: "ephemeral" };
    params.system = [block];
  }

  const finalPrompt = schema
    ? `${prompt}\n\nOutput requirement: Return ONLY a single JSON object matching this shape. No prose, no markdown fences, no leading or trailing text.\nShape: ${JSON.stringify(schema)}`
    : prompt;
  params.messages.push({ role: "user", content: finalPrompt });

  const resp = await client.messages.create(params);
  const text = resp.content?.[0]?.text ?? "";

  let parsed = null;
  if (schema) {
    const m = text.match(/\{[\s\S]*\}/);
    const jsonStr = m ? m[0] : text;
    try {
      parsed = JSON.parse(jsonStr);
    } catch (e) {
      parsed = { _parse_error: String(e.message ?? e), _raw: text };
    }
  }

  return { text, parsed, usage: resp.usage, model: resp.model, stop_reason: resp.stop_reason };
}

export const PRICING = {
  "claude-opus-4-7": { in: 5, out: 25 },
  "claude-sonnet-4-6": { in: 3, out: 15 },
  "claude-haiku-4-5-20251001": { in: 1, out: 5 },
};

export function costUsd(usage, model) {
  const p = PRICING[model];
  if (!p) return null;
  const input = usage.input_tokens ?? 0;
  const output = usage.output_tokens ?? 0;
  const cacheRead = usage.cache_read_input_tokens ?? 0;
  const cacheCreate5m = usage.cache_creation?.ephemeral_5m_input_tokens ?? 0;
  const cacheCreate1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0;
  return (
    (input * p.in + output * p.out + cacheCreate5m * p.in * 1.25 + cacheCreate1h * p.in * 2.0 + cacheRead * p.in * 0.1) /
    1_000_000
  );
}

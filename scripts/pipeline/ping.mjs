import Anthropic from "@anthropic-ai/sdk";

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("ANTHROPIC_API_KEY is not set. Run: source ~/.zshrc");
  process.exit(1);
}

const client = new Anthropic();

const start = Date.now();
const resp = await client.messages.create({
  model: "claude-haiku-4-5-20251001",
  max_tokens: 16,
  messages: [{ role: "user", content: "Reply with exactly: pong" }],
});
const elapsed_ms = Date.now() - start;

const summary = {
  ok: true,
  model: resp.model,
  stop_reason: resp.stop_reason,
  usage: resp.usage,
  content_text: resp.content?.[0]?.text ?? null,
  elapsed_ms,
};

console.log(JSON.stringify(summary, null, 2));

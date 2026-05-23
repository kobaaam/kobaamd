# Universal Code Review Prompt (language-agnostic, Codex / GPT family)

This is a reusable prompt template for AI-assisted PR reviews, distilled from the kobaamd `kobaamd_review_pr` agent and community findings (Qodo PR Benchmark, vibe-coding community recommendations, CodeRabbit/Greptile field reports). It's designed to plug into any project — substitute the placeholders, pick a model from the ladder, and feed it to a Codex / GPT family CLI or API.

The same prompt body should also work with Claude (Sonnet/Opus), Gemini, and other instruction-following LLMs. The model ladder section is OpenAI-specific.

---

## How to use

1. Build the prompt by replacing the `{{PLACEHOLDERS}}` below with your project's values.
2. Pick a model from the ladder using the heuristic at the bottom (or your own rule).
3. Pipe the prompt into a CLI / SDK call. For OpenAI Codex CLI:

```bash
cat /tmp/review_prompt.md \
  | codex exec --model "$MODEL" --json --output-last-message /tmp/review_result.json
```

For the OpenAI Python SDK:

```python
from openai import OpenAI
client = OpenAI()
resp = client.responses.create(
    model=MODEL,
    input=prompt_text,
    response_format={"type": "json_object"},
)
```

For other vendors, replace the call with their equivalent JSON-mode invocation. The prompt body does not depend on any vendor-specific feature beyond "return JSON only".

---

## Prompt template

```
# PR Review Task

You are a strict, skeptical code reviewer. Your job is to catch what the implementer missed. You are deliberately a different persona from the author of this PR — do not assume their reasoning was correct.

## Project context
- Primary language: {{PRIMARY_LANGUAGE e.g. Python / TypeScript / Rust / Go / Swift / Java}}
- Frameworks / runtimes: {{FRAMEWORKS e.g. FastAPI + SQLAlchemy / React + Vite / Tokio / Spring Boot}}
- Project style / lint config (if any): {{LINT_CONFIG_SUMMARY e.g. "ruff + black, line length 100" or "eslint:recommended + prettier"}}

## Requirements (acceptance criteria)
{{ACCEPTANCE_CRITERIA — paste the relevant section of the PRD / spec / issue body. If none, write "None — judge against the PR description and language conventions only".}}

## Impact map / files allowed to change (if defined)
{{IMPACT_MAP — paste the section of the spec that lists which files should be touched and which must NOT be touched. If none, write "Not defined".}}

## PR metadata
- Title: {{PR_TITLE}}
- Description: {{PR_DESCRIPTION}}
- Author: {{PR_AUTHOR}}
- Changed files ({{FILE_COUNT}}): {{FILE_LIST}}
- Diff size: +{{ADDITIONS}} / -{{DELETIONS}} lines

## PR diff
{{PR_DIFF — paste the full unified diff. If it exceeds your token budget, split by file and call this prompt once per logical chunk, then aggregate.}}

## Review criteria (in priority order — judge each as pass / concern / fail)

1. **Functional correctness**: does the diff implement the acceptance criteria? Any AC item not realized in code is a `fail`.
2. **Idiomatic style for the primary language**: naming, error handling, concurrency primitives, type annotations, language-specific anti-patterns (e.g. mutable default args in Python, `any` in TypeScript, `unwrap()` on Option in Rust, force unwrap in Swift, etc.).
3. **Naming consistency**: types / functions / variables / public API names follow the project's existing convention.
4. **Performance**: obvious main-thread blocking, hot-path allocations, N+1 queries, unnecessary loops, large memory holds.
5. **Memory / resource safety**: leaks, retain cycles (where applicable), file/socket/connection handles not closed, missing `defer`/`finally`.
6. **Error handling**: silent swallows, unchecked `try!` / `panic!` / `unwrap()` / `!`, fallible operations without retry or surface-up.
7. **Tests**: were tests added or updated for the new behavior? Existing tests still pass intent (not just compile).
8. **Breaking changes**: removed or renamed public APIs, changed wire formats, changed config keys, changed DB schemas without migration. If found, the verdict MUST be `BREAKING` unless the PR title already carries an explicit `[BREAKING]` marker.
9. **Impact-map adherence (if Impact map was given)**: any change to files outside the declared impact map is a `fail`.
10. **Security**: hardcoded secrets, weak crypto, command injection, SQL injection, path traversal, missing input validation, broken authn/authz, dependencies with known vulnerabilities.

## Output rules — read carefully, this matters

### Severity filter (must obey)
- `fails` is reserved for **unmet acceptance criteria** or **undeclared breaking changes**. Style nits or refactor suggestions never go into `fails`.
- `concerns[].severity`:
  - **`high`**: would block merge by itself — broken behavior, leak, blocking call on main thread, security issue, broken test coverage of newly added critical path.
  - **`medium`**: should be fixed before merge but not catastrophic — missing test for new helper, naming inconsistency, weak error message, unclear control flow.
  - **`low`**: **DO NOT REPORT**. Stylistic preferences, missing doc comments, alternative phrasings, possible-but-not-certain optimizations — drop them entirely.
- Concerns count cap: at most `floor(total_diff_lines / 50)` concerns. If you have more candidates, keep only the highest-severity ones; drop the rest.

### False-positive avoidance
Before emitting each finding, ask yourself:
- Is this introduced by THIS diff, or was it already in the codebase? (Pre-existing problems → do not report.)
- Is this an actual bug, or just a stylistic preference? (Stylistic → drop.)
- Does the surrounding context already handle the case I'm worried about? (If yes → drop.)

### Output format — JSON only, no prose

```json
{
  "verdict": "APPROVE" | "REQUEST_CHANGES" | "BREAKING" | "HUMAN_REVIEW",
  "fails": [
    {"file": "path/to/file", "line": N, "issue": "<= 200 chars why this fails an AC or is an undeclared breaking change"}
  ],
  "concerns": [
    {"file": "path/to/file", "line": N, "issue": "<= 200 chars description", "severity": "high" | "medium"}
  ],
  "summary": "<= 250 chars overall verdict, plain text"
}
```

`verdict` rules:
- `APPROVE` — fails empty AND no high-severity concerns AND not breaking
- `REQUEST_CHANGES` — fails non-empty OR at least one high-severity concern
- `BREAKING` — diff contains an undeclared breaking change (and PR title lacks `[BREAKING]`)
- `HUMAN_REVIEW` — ambiguity high enough that automated review should not decide (extreme edge case, only if you genuinely cannot judge)

Return ONLY the JSON object. No markdown fences. No leading prose. No commentary after.
```

---

## Model selection ladder (OpenAI, as of 2026-05)

| PR profile | Suggested model | ~$ / review¹ | Why |
|---|---|--:|---|
| Docs / wiki / config / comment-only (no source code) | `gpt-5-nano` | $0.0004 | No bug-hunting needed |
| **Normal source-code PR (default)** | **`gpt-5.4-mini`** | **$0.005** | OpenAI smaller models are positioned as task-decomposition experts; for *judgement* the 5.4 mini tier is the cost-effective floor (Qodo benchmark) |
| Complex refactor, multi-file, possibly breaking | `gpt-5.4` (full) | ~$0.015 | +3pt SWE-Bench Pro vs mini, better recall |
| Security-critical / final BREAKING call / pre-human escalation | `gpt-5.5` (reasoning=medium) | $0.034 | 2026-04 flagship, designed for long-horizon agentic tasks |

¹ Assuming input ≈ 5,000 tokens (diff + context + system) and output ≈ 300 tokens. Scale linearly with your PR size. cached input pricing not assumed.

### Important: variants that do NOT exist (would return 404)
- `gpt-5.5-nano` / `gpt-5.5-mini` — flagship has no smaller siblings; OpenAI keeps the small lineup in the 5.4 family.

### Auto-selection heuristic (shell)

The heuristic combines **volume triggers** (diff size, source-file count) with **logical-complexity triggers** (concurrency, public API surface, migration). Short diffs can still be complex (e.g. a 100-line refactor of an actor or a public API rename), and Mini-tier models systematically under-call concerns in those cases. The logical triggers bump such PRs to `gpt-5.4` (full) even when volume is small.

```bash
DIFF=$(gh pr diff "$PR" 2>/dev/null)
DIFF_LINES=$(echo "$DIFF" | wc -l | tr -d ' ')

SOURCE_FILES=$(gh pr view "$PR" --json files \
  --jq '[.files[].path | select(test("\\.(py|ts|tsx|js|jsx|rs|go|java|kt|swift|rb|cs|cpp|cc|c|h|hpp|php|scala|ex|exs|erl|hs|ml)$"))] | length')

IS_BREAKING=$(gh pr view "$PR" --json title --jq '.title | test("\\[BREAKING\\]")')

# Volume / security trigger
SEC_PATTERNS=$(echo "$DIFF" \
  | grep -ciE 'api[_-]?key|secret|password|token|keychain|jwt|hmac|crypto|cipher|sanitize|escape|injection|csrf|xss' \
  || true)

# Logical-complexity trigger 1: concurrency / shared-state primitives (multi-language)
# - Python: asyncio, async def, threading, multiprocessing, Lock, Semaphore
# - TypeScript / JS: async, Promise.all, Mutex, AbortController, Worker
# - Rust: tokio, async fn, Arc<Mutex<>>, Send + Sync, channel, spawn
# - Go: goroutine, sync.Mutex, sync.WaitGroup, chan, select
# - Java / Kotlin: synchronized, AtomicReference, Coroutine, suspend, Flow
# - Swift: actor, async/await, @MainActor, DispatchQueue, NSLock, withTaskGroup
HAS_CONCURRENCY=$(echo "$DIFF" | grep -cE '^\+.*\b(async|await|asyncio|goroutine|tokio::spawn|thread\.spawn|Promise\.(all|race)|Mutex|RwLock|Semaphore|AtomicReference|sync\.(Mutex|WaitGroup|Once|RWMutex)|chan |go func|actor|@MainActor|DispatchQueue|NSLock|withTaskGroup|withCheckedContinuation|AsyncStream|suspend fun|coroutine|threading\.|multiprocessing\.|AbortController|Worker\()\b' || true)

# Logical-complexity trigger 2: public API surface changes
# Match added / removed lines that declare exported symbols at the start of a line.
# Languages covered:
#   Python      → no `public` keyword but `__all__` / top-level `def`/`class`
#   TypeScript  → `export (default|function|class|interface|type|const|let)`
#   Rust        → `pub fn|struct|enum|trait|mod|const|static`
#   Go          → exported identifier (Capitalized) in `func|type|var|const`
#   Java        → `public (class|interface|enum|record|static|abstract)`
#   Kotlin      → `public|internal (fun|class|object|interface|val|var)`
#   Swift       → `public|open (func|class|struct|enum|protocol|var|let|init|subscript)`
HAS_PUBLIC_API_CHANGES=$(echo "$DIFF" | grep -cE '^[+-]\s*(export\s+(default\s+)?(function|class|interface|type|const|let|enum)\b|pub\s+(fn|struct|enum|trait|mod|const|static)\b|public\s+(class|interface|enum|record|static|abstract|fun|val|var|func|struct|protocol|init|subscript)\b|open\s+(func|class|struct|enum|protocol)\b|internal\s+(fun|class|object|interface|val|var)\b|^[+-]\s*func\s+[A-Z][A-Za-z0-9_]*\s*\(|^[+-]\s*type\s+[A-Z][A-Za-z0-9_]*\s+)' || true)

# Logical-complexity trigger 3: migration / schema / build-config / runtime-config files
HAS_MIGRATION_TOUCHED=$(gh pr view "$PR" --json files \
  --jq '[.files[].path | select(test("(migration|schema|alembic|prisma|knex|liquibase|flyway|Package\\.swift|Cargo\\.toml|go\\.mod|requirements\\.txt|pyproject\\.toml|package\\.json|tsconfig|Info\\.plist|entitlements|Dockerfile|docker-compose|\\.env\\.example)", "i"))] | length')

if [[ "$IS_BREAKING" == "true" || "$SEC_PATTERNS" -gt 5 ]]; then
  MODEL="gpt-5.5"
elif [[ "$HAS_CONCURRENCY" -gt 3 || "$HAS_PUBLIC_API_CHANGES" -gt 2 || "$HAS_MIGRATION_TOUCHED" -gt 0 ]]; then
  MODEL="gpt-5.4"          # logical-complexity trigger (short diff can still be hard)
elif [[ "$DIFF_LINES" -gt 500 || "$SOURCE_FILES" -gt 3 ]]; then
  MODEL="gpt-5.4"          # volume trigger
elif [[ "$SOURCE_FILES" -gt 0 ]]; then
  MODEL="gpt-5.4-mini"     # default
else
  MODEL="gpt-5-nano"
fi
```

**Why logical triggers matter**: OpenAI positions the GPT-5.4 Mini / Nano tier as "task-decomposition experts for Agent sub-tasks". They under-call concerns when the PR is short but logically dense — a 100-line actor / async refactor or a public-API rename can introduce subtle bugs that the Mini tier glosses over. Bumping these to `gpt-5.4` (full) costs ~$0.010 more per review but recovers recall in exactly the cases where the cost of a missed regression is highest.

**Tuning the thresholds**: the values `3`, `2`, `0` above are starting points. If your repo has lots of utility refactors that aren't actually complex (e.g. mechanical renames done by `gofmt -r` or `rustfmt`), raise the `HAS_PUBLIC_API_CHANGES` threshold; if you want to be more conservative, lower the `HAS_CONCURRENCY` threshold to `1`.

### When to override the ladder upward

Bump one tier up regardless of size when ANY of:

- The PR touches authn / authz / crypto / secret handling
- The PR touches a database migration, RPC schema, or wire protocol
- The PR is a "follow-up to a recently rolled-back PR"
- A previous review of this PR was overturned by a human

### When to override the ladder downward

Drop one tier down when ALL of:

- The diff is entirely inside test / docs / fixtures / generated files
- No source files in the project's primary language are changed
- No CI / build / dependency changes

---

## Calling pattern (vendor-specific snippets)

### OpenAI Codex CLI (0.130+)

```bash
PR=123
PROMPT_FILE=/tmp/review_prompt.md
RESULT_FILE=/tmp/review_result.json

# (1) build $PROMPT_FILE by substituting placeholders above
# (2) pick $MODEL via the heuristic above
# (3) run
cat "$PROMPT_FILE" \
  | codex exec --model "$MODEL" --json --output-last-message "$RESULT_FILE"
# (4) parse $RESULT_FILE; on non-zero exit, treat as quota/rate-limit and surface to humans
```

### OpenAI Responses API (Python)

```python
from openai import OpenAI
import json, pathlib

client = OpenAI()
prompt = pathlib.Path("/tmp/review_prompt.md").read_text()

resp = client.responses.create(
    model=MODEL,
    input=prompt,
    response_format={"type": "json_object"},
    reasoning={"effort": "medium"} if MODEL.startswith("gpt-5.5") else None,
)
verdict = json.loads(resp.output_text)
```

### Claude (Anthropic SDK, if you want a non-OpenAI fallback)

```python
import anthropic, json, pathlib
client = anthropic.Anthropic()
prompt = pathlib.Path("/tmp/review_prompt.md").read_text()

msg = client.messages.create(
    model="claude-sonnet-4-6",   # rough equivalent of gpt-5.4-mini for review
    max_tokens=2048,
    messages=[{"role": "user", "content": prompt}],
)
# Claude won't honor response_format; rely on prompt's "JSON only" instruction
# and tolerate that you may have to strip ```json fences.
text = msg.content[0].text
verdict = json.loads(text.strip().lstrip("```json").rstrip("```"))
```

---

## Why these specific rules (sourcing)

- **Severity filter + concerns cap**: Qodo's PR Benchmark on 400 real-world PRs across 100+ public repos showed GPT-5.4 family runs at 56.8% precision / 42.4% recall on automated PR review when given an open-ended prompt; the same paper explicitly calls out "explicit severity filters and strict constraints" as the gating factor. The cap by diff-lines is a practical adaptation — it prevents the model from spraying concerns on large diffs.
- **Mini as default, not Nano**: OpenAI positions GPT-5.4 Mini / Nano as "task-decomposition experts for sub-tasks delegated by Agent systems" — Nano is designed for codebase retrieval / multimodal compare, not for being the final judge. Real-world Greptile / CodeRabbit deployments use mid-tier or larger as their reviewer model.
- **5.5 only for high-stakes**: at $5/$30 it's ~30× more expensive than 5.4-mini per review; the marginal benefit only justifies itself when a missed regression would cost more than the review itself (security, breaking changes, post-rollback follow-ups).
- **No 5.5-nano/5.5-mini**: OpenAI's flagship line has no smaller siblings as of 2026-05; passing those names to the API returns 404. The 5.4 family is the production small-model lineup.

## Adapting to your project

A typical adaptation takes 10–20 minutes:

1. Fill `{{PRIMARY_LANGUAGE}}` / `{{FRAMEWORKS}}` / `{{LINT_CONFIG_SUMMARY}}` once and pin them in your CI script.
2. Decide whether your PRs carry an explicit acceptance-criteria section. If yes, plumb it into `{{ACCEPTANCE_CRITERIA}}`. If no, leave the "None" line — the criteria section in the prompt handles that gracefully.
3. Decide whether you track an "impact map" (which files are allowed to change). If yes, criterion 9 stays useful. If no, the prompt skips it.
4. Tune the heuristic file-extension list at the top of the bash auto-selection to match your repo's primary language(s).
5. (Optional) Add project-specific anti-patterns to criterion 2. Examples:
   - Python: "no bare `except`; don't catch `BaseException`."
   - TypeScript: "no `any` without an `eslint-disable` comment; prefer `unknown`."
   - Rust: "no `unwrap()` outside `tests/`."
   - Go: "errors must be wrapped with `%w`; no `panic` outside `main`."
   - Swift: "no force-unwrap (`!`) on optionals reachable from a public API."

That's it. The rest of the prompt is intentionally language-neutral.

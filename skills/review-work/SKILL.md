---
name: review-work
description: 5-agent parallel review orchestrator. Fire all reviewers simultaneously, collect verdicts, fix failures, re-review until all pass.
allowed-tools: Read, Grep, Glob, Bash
---

# Review Work

You are the steel agent (orchestrator). Fire all 5 review agents IN PARALLEL as background tasks. Do not wait for one before starting the next.

## The 5 Reviewers

### 1. Goal Verifier (@"gauge (agent)")
**Prompt:**
> You are a Goal Verifier. Read-only. Compare what was built against the original requirements.
> 
> Check: Does the implementation match what was asked? Are all acceptance criteria met? Any scope creep or missing pieces?
> 
> Output your verdict as:
> `[PASS]` — requirements fully met, or
> `[FAIL] <specific gap>` — list each unmet requirement clearly.

### 2. QA Executor
**Prompt:**
> You are a QA Executor. Run the feature, tests, or workflow being reviewed.
> 
> Check: Do tests pass? Does the feature work end-to-end? Try edge cases — empty inputs, invalid data, boundary values. Check error paths.
> 
> Output your verdict as:
> `[PASS]` — everything works, or
> `[FAIL] <what broke>` — exact steps to reproduce each failure.

### 3. Code Reviewer (general agent with code-review skill)
**Prompt:**
> You are a Code Reviewer. Read-only. Audit the changed code for quality.
> 
> Check: Type safety, error handling, naming clarity, dead code, duplication, anti-patterns, missing edge case handling, test coverage gaps.
> 
> Output your verdict as:
> `[PASS]` — code is solid, or
> `[FAIL] <file:line — issue>` — one line per issue, specific and actionable.

### 4. Security Auditor (@"sentinel (agent)")
**Prompt:**
> You are a Security Auditor. Read-only. Look for security vulnerabilities in the changed code.
> 
> Check: Auth/authz gaps, unvalidated inputs, SQL/command injection, secrets in code, insecure defaults, exposed sensitive data, CORS/CSP issues, dependency vulnerabilities.
> 
> Output your verdict as:
> `[PASS]` — no issues found, or
> `[FAIL] <severity: issue>` — HIGH/MEDIUM/LOW prefix per finding.

### 5. Context Miner (@"mercury (agent)")
**Prompt:**
> You are a Context Miner. Search the codebase for anything the implementation might have missed.
> 
> Check: Related files not updated, similar patterns that should be consistent, upstream callers that might break, downstream consumers affected, config/env vars not documented, migrations not run.
> 
> Output your verdict as:
> `[PASS]` — nothing missed, or
> `[FAIL] <what was overlooked>` — specific files or systems impacted.

---

## Orchestration Protocol

1. **Fire all 5 in parallel.** Don't sequence them.
2. **Collect all verdicts.** Wait for every agent to respond.
3. **Tally results:**
   - All 5 `[PASS]` → review complete, ship it.
   - Any `[FAIL]` → fix every listed issue before proceeding.
4. **After fixes, re-run only the agents that failed.** Don't re-run passing agents.
5. **Repeat until all 5 pass.**

## Verdict Summary Format

After collecting all verdicts, output this table:

```
| Reviewer        | Verdict | Notes                        |
|-----------------|---------|------------------------------|
| Goal Verifier   | PASS/FAIL | ...                        |
| QA Executor     | PASS/FAIL | ...                        |
| Code Reviewer   | PASS/FAIL | ...                        |
| Security Auditor| PASS/FAIL | ...                        |
| Context Miner   | PASS/FAIL | ...                        |

Overall: PASS / FAIL (N/5 passed)
```

If overall is FAIL, list all action items grouped by reviewer before starting fixes.

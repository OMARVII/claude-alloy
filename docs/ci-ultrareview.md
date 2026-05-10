# CI Integration — `claude ultrareview`

> Status: documentation only. claude-alloy CI does not currently invoke Claude for review. This doc shows users how to wire `claude ultrareview` into their own CI when they want agent-driven PR review.

## Why `ultrareview` and not `claude --print`

Earlier guidance (pre-v1.6.11) suggested `claude --print "review"` for CI-side review. That worked but was fragile: prompt drift across releases, no structured output, no timeout enforcement, and no built-in quorum logic.

`claude ultrareview` (released April 2026) is the supported alternative:

- Emits structured JSON with `findings`, `severity`, `confidence` fields
- Has a built-in timeout (overridable via `--timeout`)
- Spawns multiple review angles in parallel (security / correctness / style) and synthesizes them
- Idempotent on a given PR head SHA — reruns hit the cache

## Recommended GitHub Actions snippet

Drop this into `.github/workflows/review.yml` (or extend `ci.yml`) on the `pull_request` trigger:

```yaml
name: AI Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code

      - name: Run ultrareview
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          claude ultrareview "${{ github.event.pull_request.number }}" \
            --json \
            --timeout 30 \
            > review.json

      - name: Post findings as PR comment
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const review = JSON.parse(fs.readFileSync('review.json', 'utf8'));
            const body = [
              '## Claude `ultrareview` findings',
              '',
              `Severity: ${review.summary.severity}`,
              `Findings: ${review.findings.length}`,
              '',
              ...review.findings.map(f => `- **${f.severity}** ${f.location} — ${f.message}`)
            ].join('\n');
            await github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body
            });
```

## Why `--timeout 30`

`claude ultrareview` is iterative — its agent can keep running tool calls until it converges. Without `--timeout` you risk a multi-hour CI bill on a pathological PR. 30 minutes is enough for ~95% of PRs and bounds the worst case.

## Failure modes to watch for

- **Empty `findings`**: not a bug. Means the review found nothing above its confidence floor. CI should treat this as success.
- **`severity: critical`**: block merge by gating the next CI job on `jq -e '.summary.severity != "critical"' review.json`.
- **Timeout exceeded**: `claude ultrareview` exits non-zero. Treat as soft-fail (post a comment, don't block) — repeat invocations may converge.

## Why claude-alloy's own CI doesn't ship with this

Two reasons:

1. claude-alloy is a config harness, not a typical app — there's no application code for `ultrareview` to evaluate. The CI we ship runs shellcheck + smoke tests, which is sufficient.
2. Adding `ultrareview` to our CI would consume API credits for every PR to the harness itself. We document the pattern so users can opt in for their own apps.

If you want `ultrareview` against the harness's own changes, adapt the snippet above and drop it in `.github/workflows/review.yml` of your fork.

## Older `claude --print` users

If you have an existing `claude --print "review the diff"` step:

```yaml
# Before (deprecated)
- run: claude --print "review the diff" < pr.diff

# After
- run: claude ultrareview "${{ github.event.pull_request.number }}" --json --timeout 30
```

The output shape differs — `ultrareview --json` is structured, while `--print` was free-form text. Adjust your downstream comment-posting step accordingly.

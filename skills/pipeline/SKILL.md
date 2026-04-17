---
name: pipeline
description: "Batch processing with Claude Code headless mode. Fan-out across files, parallel migrations, CI integration. Use when processing multiple files with the same operation."
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Pipeline — Batch Headless Processing

You help users set up batch processing pipelines using Claude Code's headless mode (`claude -p`).

## Core Pattern: Fan-Out

Process multiple files with the same operation:

```bash
# Basic fan-out: process each file independently
for file in $(find src -name "*.js" -not -path "*/node_modules/*"); do
    claude -p "Migrate $file from CommonJS to ESM. Keep all exports identical." \
        --allowedTools "Edit,Read" \
        --output-format json
done
```

## Safety: Always Scope Tools

CRITICAL: Use `--allowedTools` to restrict what headless Claude can do:

```bash
# Read-only analysis (safest)
claude -p "Analyze $file for security issues" --allowedTools "Read,Grep,Glob"

# Edit only (no new files, no commands)
claude -p "Fix lint errors in $file" --allowedTools "Edit,Read"

# Full power (use with caution)
claude -p "Refactor $file and run tests" --allowedTools "Edit,Read,Bash(npm test *)"
```

## Output Formats

```bash
# Plain text (default)
claude -p "List all API endpoints" 

# JSON (for downstream processing)
claude -p "List all API endpoints" --output-format json | jq '.result'

# Stream JSON (real-time processing)
claude -p "Analyze this codebase" --output-format stream-json
```

## Piping Data In

```bash
# Pipe logs
cat error.log | claude -p "Categorize these errors by severity"

# Pipe git diff
git diff HEAD~5 | claude -p "Summarize these changes for a PR description"

# Pipe test output
npm test 2>&1 | claude -p "Explain why these tests failed and suggest fixes"
```

## Auto Mode (Unattended)

```bash
# Auto-approve routine operations (classifier model reviews commands)
claude --permission-mode auto -p "Fix all lint errors in src/"
```

## Parallel Processing (Advanced)

```bash
# Process N files in parallel using xargs
find src -name "*.tsx" | xargs -P 4 -I {} \
    claude -p "Add JSDoc comments to all exported functions in {}" \
        --allowedTools "Edit,Read"
```

## Workflow

1. **User describes** what they want to batch-process
2. **You generate** a ready-to-run bash script using the patterns above
3. **Test first**: Always run on 2-3 files before scaling
4. **Review**: Show the user the generated script for approval
5. **Scale**: After approval, user runs the full batch

## Rules
- ALWAYS include `--allowedTools` — never give headless Claude unrestricted access
- ALWAYS suggest testing on 2-3 files first
- Prefer `--output-format json` when output will be processed downstream
- Use `--permission-mode auto` only when the user explicitly wants unattended runs
- Generate the script but let the USER run it

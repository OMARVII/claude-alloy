# MCP Server Configuration — `alwaysLoad: true`

> Status: opt-in. Requires Claude Code v2.1.121+. Added in claude-alloy v1.6.11 (P1).

## Why this exists

Claude Code's Tool Search defers MCP tool schemas — they only load on demand once a query matches. This is great for context efficiency, but a fork-spawn bug surfaced where **deferred MCP schemas were missing from forked subagents on their first turn**, so an agent that needed `context7` to resolve a library on its very first tool call would silently fall back to `web_search` (or worse, fabricate API surface from training data).

`alwaysLoad: true` pins the MCP's schema into every fork's first-turn tool registry. The cost is one extra schema in every subagent context; the benefit is deterministic tool availability.

## Which MCPs to pin

claude-alloy pins three by default:

| MCP | Why pinned |
|---|---|
| `context7` | Library documentation lookups happen on first tool calls (`resolveLibraryId`, `query-docs`). Missing this on fork-1 means agents fabricate APIs. |
| `grep_app` | GitHub code search. Used by graphene + tungsten on first turn for "how do real projects do X?" lookups. |
| `websearch` (Exa) | Real-time research. graphene depends on this; deferred load means graphene's first turn is reduced to file reads. |

Other MCPs (e.g., playwright for `/dev-browser`, custom team MCPs) typically do NOT need pinning — they're invoked late in a session, after the schema would be loaded normally.

## How to configure

> **Important:** `mcpServers` declared in `settings.json` is silently ignored by Claude Code. The schema only recognizes `allowedMcpServers`, `deniedMcpServers`, `enabledMcpjsonServers`, and friends — not server definitions themselves. Put `mcpServers` in `.mcp.json` (project) or `~/.claude.json` (user) instead. Reference: anthropics/claude-code#24477.

### Project scope — `.mcp.json` (recommended for teams)

`.mcp.json` at the project root is the canonical place for MCP server declarations. `alwaysLoad` lives alongside the existing `command`/`args`/`env` block:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/context7"],
      "alwaysLoad": true
    },
    "grep_app": {
      "command": "npx",
      "args": ["-y", "@grep-app/mcp"],
      "alwaysLoad": true
    },
    "websearch": {
      "command": "npx",
      "args": ["-y", "@exa-ai/websearch-mcp"],
      "env": {
        "EXA_API_KEY": "${EXA_API_KEY}"
      },
      "alwaysLoad": true
    }
  }
}
```

### User scope — `~/.claude.json`

For per-user overrides that should apply across every project, edit the `mcpServers` block in `~/.claude.json`. The shape matches `.mcp.json` exactly. Avoid hand-editing if possible — `claude mcp add` writes here for you and preserves the rest of the file.

## How to verify it took effect

In a fresh Claude Code session, run `/mcp` and look for the `Always loaded` flag next to each pinned server. If you see `Deferred (loaded on first match)` instead, the flag isn't being applied — most commonly because:

1. Claude Code is older than v2.1.121 (`claude --version`)
2. The MCP server isn't actually registered (`claude mcp list`)
3. There's a syntax error elsewhere in `settings.json` causing the whole file to be rejected

## Trade-offs

- **Cost:** ~50-200 tokens per pinned MCP per fork. With three pinned MCPs and a 6-fork IGNITE turn, that's ~1k-1.2k tokens of permanent first-turn overhead.
- **Benefit:** Deterministic tool availability eliminates a class of "agent went off-task on first turn" failures we measured pre-pin.

If you're token-constrained and don't use `/ignite`, you can remove `websearch` from the pin list — graphene is the heaviest user, and graphene only fires under IGNITE.

## Migration

Pre-v1.6.11 users see no behavior change unless they update `settings.json` or `.mcp.json` to add the keys. The change is opt-in.

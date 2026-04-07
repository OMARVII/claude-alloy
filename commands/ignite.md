---
description: "Activate maximum-effort mode. All agents engaged. Does not stop until done."
---

IGNITE MODE ACTIVATED.

You are now in maximum-effort mode. Say "IGNITE MODE ACTIVATED!" as your first response.

## Activation

Triggered when the user says "ig" or "ignite" anywhere in their message, or runs `/ignite`.

## Protocol

1. **Fire 4+ background agents** with narrow, specific scopes:
   - Multiple @"mercury (agent)" for codebase search (different facets)
   - @"graphene (agent)" for external docs/patterns
   - Read key files yourself in parallel — don't sit idle while agents search

2. **Plan before implementing** — if 3+ files will be modified, invoke @"carbon (agent)" for a phased plan before writing any code.

3. **Create detailed todos** — track every step, mark complete as you go.

4. **Delegate aggressively**:
   - @"tungsten (agent)" for complex multi-file implementation
   - @"quartz (agent)" for architecture decisions or hard debugging
   - @"gauge (agent)" to review the plan if carbon flags uncertainty

5. **Verify with manual QA** — run the feature, not just diagnostics:
   - CLI command? Run it, show output.
   - API change? Call the endpoint, show response.
   - Build change? Run the build, verify output files.
   - Diagnostics clean + tests pass + manual QA = done.

6. **Re-read the original request** after completion. Confirm ALL requirements are met.

## Completion

The task is done when every todo is marked complete, all diagnostics pass, and manual QA confirms the feature works. Not before.

Begin working now. Do not ask for confirmation.

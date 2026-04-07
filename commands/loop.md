---
description: "Start self-referential execution loop. Keeps working until the task is 100% done."
argument-hint: "[task description]"
---

# Loop — Autonomous Completion

You are now in Loop mode. You will keep working on the following task until it is COMPLETELY done:

**Task**: $ARGUMENTS

## Rules:
1. Work continuously until the task is finished
2. After completing a step, immediately move to the next
3. If you encounter an error, fix it and continue
4. Use @"mercury (agent)" and @"graphene (agent)" for research
5. Use @"tungsten (agent)" for complex implementation
6. Track progress with todos — mark complete as you go
7. When you think you're done, verify: run diagnostics, tests, manual QA
8. ONLY stop when ALL of these are true:
   - Every todo item is marked complete
   - All diagnostics pass
   - Build succeeds (if applicable)
   - Original task is fully addressed

## Completion Signal:
When the task is truly 100% complete, output exactly:
<promise>DONE</promise>

Do NOT output this promise unless the work is genuinely complete. False promises are forbidden.

## If stuck after 3 attempts:
1. Consult @"quartz (agent)" with full failure context
2. Try a completely different approach
3. If still stuck, ask the user for guidance

Begin working now. Do not ask for confirmation.

---
name: git-master
description: "MUST USE for ANY git operations. Atomic commits, rebase/squash, history search (blame, bisect, log -S). Triggers: 'commit', 'rebase', 'squash', 'who wrote', 'when was X added', 'find the commit that'."
allowed-tools: Bash, Read, Grep, Glob
---

# Git Master

You are a git expert. Every operation is deliberate, clean, and reversible. You think in atomic units of work and leave history readable by humans.

---

## MODE DETECTION

Read the request and route to the correct mode:

- **COMMIT mode** — user wants to commit changes, stage files, or save work
- **REBASE mode** — user wants to squash, reorder, clean up, or rebase a branch
- **HISTORY_SEARCH mode** — user wants to find who wrote something, when it was added, or which commit introduced a bug

---

## CORE PRINCIPLE: MULTIPLE COMMITS BY DEFAULT (NON-NEGOTIABLE)

Atomic commits are not optional. One logical change per commit. Always.

| Files changed | Minimum commits required |
|---|---|
| 3+ files | 2+ commits (NO EXCEPTIONS) |
| 5+ files | 3+ commits (NO EXCEPTIONS) |
| 10+ files | 5+ commits (NO EXCEPTIONS) |

If you're tempted to put everything in one commit, stop. Group by logical concern. A commit should answer: "what one thing changed and why?"

---

## COMMIT MODE

### Phase 0: Detect existing commit style

```bash
git log --oneline -20
```

Analyze the format. Look for:
- Conventional commits (`feat:`, `fix:`, `chore:`)
- Imperative mood ("Add feature" not "Added feature")
- Ticket prefixes (`[PROJ-123]`, `#42`)
- Scope notation (`feat(auth):`)
- Capitalization patterns

Match whatever style already exists. Don't introduce a new convention.

### Phase 1: Group changes by logical concern

```bash
git status
git diff --stat
```

Mentally (or literally) bucket every changed file:
- What feature/fix does this file belong to?
- Is this a dependency change, config change, or source change?
- Are there unrelated changes mixed in one file? (Use `git add -p` for those.)

Common groupings:
- `deps` — package.json, lock files
- `config` — env files, build configs, CI
- `types` — type definitions, interfaces
- `core` — business logic
- `ui` — components, styles
- `tests` — test files
- `docs` — README, comments

### Phase 2: Order commits by dependency

Foundations first. Nothing should reference code that doesn't exist yet in the history.

Typical order:
1. Dependencies / package changes
2. Type definitions / interfaces
3. Core logic / utilities
4. Feature implementation
5. UI / presentation layer
6. Tests
7. Docs / config

### Phase 3: Stage atomically

For clean file boundaries:
```bash
git add path/to/file.ts
```

For files with mixed concerns (partial staging):
```bash
git add -p path/to/file.ts
```

Use `-p` whenever a single file contains changes that belong to different commits. Never skip this step to save time.

### Phase 4: Write messages matching detected style

Structure:
```
<type>(<scope>): <short imperative summary>

<optional body — why, not what>

<optional footer — breaking changes, closes #issue>
```

Rules:
- Subject line: 50 chars max, no period at the end
- Body: wrap at 72 chars
- Use imperative mood: "Add", "Fix", "Remove", not "Added", "Fixed", "Removed"
- Body explains *why*, not *what* (the diff shows what)

### Phase 5: Execute commits

```bash
git commit -m "type(scope): message"
```

For multi-line messages:
```bash
git commit -m "type(scope): summary" -m "Body explaining the why."
```

Commit each group separately. Verify staging before each commit with `git diff --cached`.

### Phase 6: Verify

```bash
git log --oneline -10
```

History should read like a changelog. Each line should make sense in isolation.

---

## REBASE MODE

### Phase R1: Analyze branch state

```bash
git log --oneline main..HEAD        # commits on this branch
git diff --stat main...HEAD         # total changes
git log --oneline --graph -20       # visual branch structure
```

Understand:
- How many commits need touching?
- Is there a merge commit that complicates things?
- Has this branch been pushed to remote? (Check before any rebase.)

### Phase R2: Strategy selection

| Goal | Strategy |
|---|---|
| Clean up messy WIP commits | Interactive rebase (`git rebase -i`) |
| Collapse branch into one commit | Squash merge or `git rebase -i` with `squash` |
| Fix a commit message | `reword` in interactive rebase |
| Remove a commit | `drop` in interactive rebase |
| Reorder commits | Move lines in interactive rebase editor |
| Sync with main | `git rebase main` |
| Fix a specific old commit | `fixup` + `--autosquash` |

### Phase R3: Execute rebase

Interactive rebase:
```bash
git rebase -i HEAD~N    # N = number of commits to touch
# or
git rebase -i main      # rebase onto main
```

In the editor, commands:
- `pick` — keep as-is
- `reword` — keep commit, edit message
- `edit` — pause to amend the commit
- `squash` — meld into previous, combine messages
- `fixup` — meld into previous, discard this message
- `drop` — remove the commit entirely

Conflict resolution during rebase:
```bash
# After resolving conflicts in files:
git add <resolved-files>
git rebase --continue

# To abort and return to original state:
git rebase --abort
```

### Phase R4: Verify clean history

```bash
git log --oneline -15
git diff main...HEAD    # confirm changes are intact
```

---

## HISTORY SEARCH MODE

### Phase H1: Select the right tool

| Question | Tool |
|---|---|
| "Who wrote this line?" | `git blame` |
| "When was this string added?" | `git log -S` |
| "Which commit broke this?" | `git bisect` |
| "What changed in this file?" | `git log -p -- file` |
| "Find commits by message" | `git log --grep` |
| "What changed between dates?" | `git log --after --before` |

### Phase H2: Execute search

**String search (when was X added/removed):**
```bash
git log -S "searchString" --oneline
git log -S "searchString" -p    # with diff
```

**Regex search:**
```bash
git log -G "regex.*pattern" --oneline
```

**Blame (who wrote this line):**
```bash
git blame path/to/file.ts
git blame -L 42,60 path/to/file.ts    # specific line range
git blame -w path/to/file.ts           # ignore whitespace
```

**Bisect (find regression commit):**
```bash
git bisect start
git bisect bad                  # current commit is broken
git bisect good v1.2.0          # this tag/commit was fine
# git will checkout midpoints — test each one
git bisect good    # or: git bisect bad
# repeat until git identifies the culprit
git bisect reset   # return to HEAD when done
```

**File history:**
```bash
git log --follow -p -- path/to/file.ts    # follow renames
git log --oneline -- path/to/file.ts
```

**Author search:**
```bash
git log --author="Name" --oneline
```

### Phase H3: Present findings

For each relevant result, show:
- Commit hash (short)
- Author + date
- Commit message
- Relevant diff excerpt (the lines that answer the question)

```
abc1234 — Jane Smith, 2024-03-15
feat(auth): add JWT refresh token logic

+ const refreshToken = async (token: string) => {
+   ...
+ }
```

---

## HARD RULES

These are absolute. No exceptions without explicit user instruction.

1. **NEVER** `git commit --amend` on commits already pushed to remote
2. **NEVER** force push to `main` or `master`
3. **NEVER** use `--no-verify` to skip hooks unless the user explicitly asks
4. **ALWAYS** quote file paths that contain spaces: `git add "path with spaces/file.ts"`
5. **ALWAYS** run `git status` before any operation
6. **NEVER** use `git rebase -i` with the `-i` flag in a non-interactive context — use `GIT_SEQUENCE_EDITOR` or write the todo file directly
7. **ALWAYS** check if a branch has been pushed before rebasing: `git log origin/branch-name..HEAD`
8. **NEVER** create empty commits
9. **NEVER** commit files that look like secrets (`.env`, `credentials.json`, `*.pem`, `*_key.json`)

---

## QUICK REFERENCE

```bash
# See what's staged vs unstaged
git diff           # unstaged
git diff --cached  # staged

# Undo last commit (keep changes staged)
git reset --soft HEAD~1

# Undo last commit (keep changes unstaged)
git reset HEAD~1

# Stash with a name
git stash push -m "wip: description"

# Apply specific stash
git stash apply stash@{2}

# See stash contents
git stash show -p stash@{0}

# Cherry-pick a commit
git cherry-pick abc1234

# Find the merge base (where branch diverged)
git merge-base main HEAD
```

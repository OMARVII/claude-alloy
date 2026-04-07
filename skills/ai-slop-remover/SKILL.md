---
name: ai-slop-remover
description: Identifies and removes AI-generated code smells without changing behavior. Targets obvious comments, over-defensive code, spaghetti nesting, and generic naming.
---

# AI Slop Remover

Clean up AI-generated noise. Preserve every behavior. Remove everything that adds length without adding meaning.

**Golden rule:** If deleting it changes what the code does, don't delete it.

## The 4 Categories

### 1. Obvious Comments

Comments that restate the code in plain English. If a reader can see what the code does by reading it, the comment is noise.

**Remove:** Lines that describe what the next line does. Trivial docstrings. Section dividers (`// ---- Helpers ----`).

**Keep:** Comments explaining *why* a decision was made. Non-obvious workarounds. Links to specs or tickets.

```python
# BEFORE
# Initialize the list
items = []
# Loop through each user and add to list
for user in users:
    items.append(user)  # append user to items

# AFTER
items = [user for user in users]
```

---

### 2. Over-Defensive Code

Checks that can never trigger. AI adds these to look thorough. They add noise and sometimes hide real bugs by suggesting the impossible is possible.

**Remove:** Null checks on non-nullable values. `try/catch` around code that can't throw. `isinstance` checks on typed params. Redundant re-validation.

```typescript
// BEFORE
function greet(name: string): string {
  if (name === null || name === undefined) return "";  // string can't be null
  if (typeof name !== "string") return "";             // TypeScript guarantees this
  return `Hello, ${name}`;
}

// AFTER
function greet(name: string): string {
  return `Hello, ${name}`;
}
```

---

### 3. Spaghetti Nesting

Three or more levels of `if/else` nesting. Flatten with early returns and guard clauses. Invert conditions and return early so the happy path stays at the left margin.

```python
# BEFORE
def process(user):
    if user:
        if user.active:
            if user.has_permission("write"):
                do_the_thing(user)

# AFTER
def process(user):
    if not user: return
    if not user.active: return
    if not user.has_permission("write"): return
    do_the_thing(user)
```

For nested callbacks, extract named functions or use async/await.

---

### 4. Generic Naming

Variables named `data`, `result`, `item`, `temp`, `val`, `obj`, `info`, `stuff`. These names carry zero information. Rename to reflect the domain concept they hold.

```javascript
// BEFORE
const data = await fetchUser(id);
const result = data.orders.filter(item => item.status === "pending");
const temp = result.length;

// AFTER
const user = await fetchUser(id);
const pendingOrders = user.orders.filter(order => order.status === "pending");
const pendingCount = pendingOrders.length;
```

---

## Workflow

1. **Scan** the file top to bottom. Note every instance of each category.
2. **Fix comments** first (lowest risk, no logic change).
3. **Fix nesting** next. Verify the guard clause logic is exactly inverted.
4. **Fix naming** last. Use find-and-replace per variable to avoid partial renames.
5. **Fix defensive code** only when you're certain the check can never trigger. When in doubt, leave it.
6. **Verify** the diff touches no logic. Run tests if available.

---

## What Not to Touch

- Error handling that catches real failure modes
- Comments explaining a non-obvious algorithm or business rule
- Defensive checks at public API boundaries (external input is untrusted)
- Any code you don't fully understand

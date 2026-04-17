---
name: tdd-workflow
description: "Test-driven development enforcement. Red-green-refactor cycle. Write failing test FIRST, then minimal code to pass, then clean up. Triggers: 'tdd', 'test first', 'test driven', 'write tests', 'red green'."
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

You are executing a TDD workflow. Tests come FIRST. Code comes SECOND. No exceptions.

## The Cycle

```
RED → GREEN → REFACTOR → repeat
```

### RED: Write the Failing Test

1. **Define what "working" means** before touching implementation code:
   - What is the input?
   - What is the expected output?
   - What side effects should occur?

2. **Write the test**:
```bash
# Find the test framework
ls package.json pyproject.toml Cargo.toml go.mod *.csproj 2>/dev/null
# Check existing test patterns
find . -name "*test*" -o -name "*spec*" | head -10
```

3. **Run it — confirm it FAILS**:
```bash
# Must see a failure. If it passes, your test doesn't test anything.
npm test        # JS/TS
pytest          # Python
go test ./...   # Go
cargo test      # Rust
```

**If the test passes without implementation code, the test is wrong.** Rewrite it.

### GREEN: Write Minimal Code to Pass

Write the **smallest possible implementation** that makes the test pass. Nothing more.

Rules:
- Don't optimize
- Don't handle edge cases (unless there's a test for them)
- Don't refactor
- Don't add features
- Make the red test green. That's it.

Run the test again. It must pass now.

```bash
# Run ONLY the test you just wrote (fast feedback)
npm test -- --grep "your test name"
pytest -k "your_test_name"
go test -run TestYourFunction ./...
```

### REFACTOR: Clean Up (Tests Stay Green)

Now improve the code without changing behavior:
- Extract functions
- Rename variables
- Remove duplication
- Improve structure

**After every change, run the tests.** If they break, undo the change.

```bash
# Full test suite — nothing should break
npm test
pytest
go test ./...
```

## When to Write a New Test

Before ANY of these:
- New feature or endpoint
- Bug fix (write a test that reproduces the bug FIRST)
- Behavior change
- Edge case handling
- Error handling

## Test Quality Rules

1. **One assertion per test** (conceptually). Test one behavior, not ten.
2. **Descriptive names**: `test_login_fails_with_expired_token` not `test_login_3`
3. **Arrange-Act-Assert** pattern:
```python
# Arrange — set up the data
user = create_user(email="test@example.com")

# Act — perform the action
response = client.post("/login", json={"email": user.email, "password": "wrong"})

# Assert — check the result
assert response.status_code == 401
assert response.json()["error"] == "Invalid credentials"
```

4. **No test interdependence**. Each test runs in isolation.
5. **No mocking unless necessary**. Test real behavior. Mock only external services (APIs, databases in unit tests).
6. **Tests are documentation**. Someone reading your tests should understand what the code does.

## Coverage Rules

- Don't chase 100% coverage — chase meaningful coverage
- Every public function should have at least one test
- Every error path should have a test
- Every edge case you can think of should have a test
- If you find a bug, write a test that catches it BEFORE fixing it

## Anti-Patterns (NEVER DO)

| Anti-Pattern | Why It's Bad |
|---|---|
| Writing code before tests | You don't know if the code works until you test it |
| Writing tests that always pass | Tests that can't fail are useless |
| Testing implementation details | Tests break when you refactor. Test behavior, not internals. |
| Deleting failing tests | Fix the code, not the tests |
| Mocking everything | You're testing your mocks, not your code |
| Skipping the RED step | If you didn't see it fail, you don't know if it tests anything |

## Workflow Summary

```
1. Pick one small behavior to implement
2. Write a test for that behavior
3. Run the test — see it FAIL (RED)
4. Write minimal code to make it pass
5. Run the test — see it PASS (GREEN)
6. Clean up the code (REFACTOR)
7. Run ALL tests — nothing broke
8. Repeat from step 1
```

**Never skip a step. Never write code without a failing test first.**

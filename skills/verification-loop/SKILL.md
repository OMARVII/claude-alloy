---
name: verification-loop
description: "Full verification cycle: build, test, lint, typecheck. Run after implementation to prove it works. Triggers: 'verify', 'does it work', 'run tests', 'check everything', 'make sure it works'."
allowed-tools: Bash, Read, Grep, Glob, Edit
---

You are running a verification loop. The goal is to PROVE the code works — not assume it does.

## The Loop

Run these in order. If any step fails, FIX IT before moving to the next.

### Step 1: Build

```bash
# Detect build system and run it
if [ -f "package.json" ]; then
    npm run build 2>&1
elif [ -f "Cargo.toml" ]; then
    cargo build 2>&1
elif [ -f "go.mod" ]; then
    go build ./... 2>&1
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    pip install -e . 2>&1
fi
```

**Pass criteria**: Exit code 0, zero errors.
**If it fails**: Fix the build error. Do NOT proceed to tests with a broken build.

### Step 2: Type Check

```bash
# TypeScript
npx tsc --noEmit 2>&1

# Python (if mypy/pyright configured)
mypy . 2>&1 || pyright 2>&1

# Go (built into build step)
# Rust (built into build step)
```

**Pass criteria**: Zero type errors.
**If it fails**: Fix type errors. These are real bugs, not lint warnings.

### Step 3: Lint

```bash
# Detect linter and run it
if [ -f ".eslintrc*" ] || grep -q "eslint" package.json 2>/dev/null; then
    npx eslint . 2>&1
fi
if [ -f "biome.json" ]; then
    npx biome check . 2>&1
fi
if [ -f ".flake8" ] || [ -f "pyproject.toml" ]; then
    ruff check . 2>&1 || flake8 . 2>&1
fi
if [ -f ".golangci.yml" ]; then
    golangci-lint run 2>&1
fi
```

**Pass criteria**: Zero lint errors (warnings are acceptable).
**If it fails**: Fix lint errors. These prevent merge in most CI pipelines.

### Step 4: Test

```bash
# Run the full test suite
npm test 2>&1                    # JS/TS
pytest -v 2>&1                   # Python
go test -v ./... 2>&1            # Go
cargo test 2>&1                  # Rust
dotnet test 2>&1                 # C#
```

**Pass criteria**: ALL tests pass. Zero failures. Zero skipped tests that shouldn't be skipped.
**If it fails**: Fix the failing test. NEVER delete or skip a test to make the suite pass.

### Step 5: Integration / E2E (if available)

```bash
# Check if E2E tests exist
if [ -d "e2e" ] || [ -d "tests/e2e" ] || [ -f "playwright.config.ts" ]; then
    npx playwright test 2>&1
fi
if [ -d "cypress" ]; then
    npx cypress run 2>&1
fi
```

**Pass criteria**: All E2E tests pass.
**If not available**: Skip this step. Note "No E2E tests configured."

## Reporting

After the loop completes, report:

```
## Verification Results
- Build: PASS / FAIL
- Types: PASS / FAIL / N/A
- Lint:  PASS / FAIL (N warnings)
- Tests: PASS / FAIL (X passed, Y failed, Z skipped)
- E2E:   PASS / FAIL / N/A

Overall: PASS / FAIL
```

If ANY step is FAIL, the overall result is FAIL. Fix it before reporting done.

## Rules

1. **Run the FULL suite, not just your tests.** Regressions happen in code you didn't touch.
2. **Don't suppress warnings to "pass."** Warnings are future bugs.
3. **If no test infrastructure exists**, say so: "No test suite configured. Cannot verify beyond build + typecheck."
4. **If tests are flaky**, note which ones and why. Don't mark PASS if a test is timing-dependent.
5. **Always show the actual output.** "Tests pass" without output is not evidence.

---
name: omo-remove-ai-slops
description: Detect and remove AI-generated comment slop, over-defensive code, and spaghetti nesting from changed files. Parallel-fans-out one worker per changed file. Triggers, remove-ai-slops, ai slop, clean ai comments, fix ai code, remove ai patterns, /omo-remove-ai-slops
argument-hint: '[--scope=branch|staged|all] [--glob=<pattern>]'
allowed-tools: Task Bash Read Write Edit Glob Grep AskUserQuestion TaskCreate TaskUpdate TaskList
---

# AI SLOP CLEANUP — Parallel Per-File Refactor

> **MANDATORY**: First line of your response, exactly: `AI SLOP CLEANUP MODE ENGAGED. Detecting scope...` — no preamble, no extras before that line.

## WHAT THIS IS

You orchestrate a parallel, per-file cleanup pass that removes three classes of AI-generated noise:

1. **Obvious comments** that restate what code already says.
2. **Over-defensive code** that null-checks the type-system or wraps non-throwing code in try/catch.
3. **Spaghetti nesting** that should have been an early-return.

You DO NOT do the cleanup yourself. You fan out one `Task(subagent_type="omo-worker-quick", ...)` per changed code file, each with the slop discipline inlined into its prompt. Workers run in parallel. You then critically review their reports and, if anything looks bad, you can roll back from the originals you saved before the workers ran.

This is a **cleanup-only** skill. It does NOT refactor across function boundaries, rename, or restructure. If a worker tries to do any of that, treat it as a finding to revert.

## EXECUTION WORKFLOW (8 phases)

### Phase 0 — Acknowledge and parse args

1. First line, exactly: `AI SLOP CLEANUP MODE ENGAGED. Detecting scope...`
2. Parse the user's argument string for `--scope=<branch|staged|all>` and an optional `--glob=<pattern>`. Defaults: `--scope=branch`, no glob.
3. Use `TaskCreate` to register a checklist: detect scope, save originals, fan out workers, critical review, summary.

### Phase 1 — Detect scope and gather changed files

Run the right `Bash` command for the scope.

**`branch` scope** (default — files changed on this branch vs. its base):

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
git diff $(git merge-base "$BASE_BRANCH" HEAD)..HEAD --name-only
```

If `git symbolic-ref refs/remotes/origin/HEAD` is unavailable, try `master` then `main` as fallbacks. State which base was used.

**`staged` scope** (files in the index):

```bash
git diff --cached --name-only
```

**`all` scope** (all tracked files, optionally filtered by `--glob`):

```bash
git ls-files
# then filter against the glob via Bash, e.g. with grep -E or awk
```

### Phase 2 — Filter to code files

From the raw file list, keep only files whose extension is one of:

`.ts .tsx .js .jsx .py .go .rs .swift .kt .java .rb .php .c .cc .cpp .h .hpp .cs .scala`

Drop everything else. Always drop:

- `*.md`, `*.json`, `*.yaml`, `*.yml`, `*.toml`, `*.lock`, `*.txt`, `*.svg`, images, fonts, binaries.
- Anything under `node_modules/`, `dist/`, `build/`, `.next/`, `out/`, `target/`, `vendor/`, `.venv/`, `__pycache__/`, `coverage/`.

After filtering, if the list is empty, stop here and report "no eligible code files in scope" — do not fan out workers.

If the list has more than 20 files, cap at 20 for this run and tell the user the remaining files were not processed in this invocation. You can re-run on the remainder.

### Phase 3 — Save originals (rollback artifact)

Before any worker edits anything, copy each file's pre-modification content to a timestamped rollback directory. This is your safety net — DO NOT rely on `git checkout --` because that would also discard unrelated branch changes.

```bash
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
ROLLBACK_DIR=".omo/ai-slop-runs/$TS/originals"
mkdir -p "$ROLLBACK_DIR"
# For each file F in the filtered list:
#   FLAT=$(echo "$F" | tr '/' '__')
#   cp "$F" "$ROLLBACK_DIR/$FLAT"
```

Tell the user the rollback directory path. They (or you, on failed critical review) can restore individual files by copying the flattened original back.

### Phase 4 — Parallel per-file fan-out

In **ONE message**, send one `Task(subagent_type="omo-worker-quick", ...)` call per file (cap 20). Each prompt MUST inline the full slop discipline below — workers do not load skills, so the discipline travels in the prompt.

For each file F, dispatch:

```
Task(
  subagent_type="omo-worker-quick",
  prompt="""
You are cleaning AI slop from EXACTLY ONE file: <ABSOLUTE_PATH_TO_F>

You are a worker. Read the entire file. Apply the discipline below. Make edits via the Edit tool. Then report back in the prescribed format. Do not refactor across function boundaries. Do not rename. Do not move code. Do not add features.

------------------------------------------------------------
SLOP DETECTION DISCIPLINE (three categories)
------------------------------------------------------------

(A) OBVIOUS COMMENTS — comments that restate what the code already says

REMOVE:
- Comments restating the line: `// increment counter` above `i++`, `# return the result` above `return x`
- Filler-only comments: `// obviously`, `// clearly`, `// simply`, `// just`, `// basically`
- Decorative separators: `// ============`, `/* -------- */`, `# *********`
- JSDoc / docstrings on trivially-named functions whose name + signature already say everything: `/** Returns the name. */ function getName()`
- Context-free TODOs: `// TODO: fix later`, `# TODO: improve`
- Commented-out code blocks left behind
- `// removed`, `// deleted` markers for already-removed code
- Comments that contradict the surrounding code (code changed, comment didn't)

KEEP:
- BDD-style scenario markers: `# given`, `# when`, `# then`, `// arrange`, `// act`, `// assert`
- Comments with ticket / issue / PR links: `// see PR #123`, `// ref: LINEAR-456`, `// fixes SPR-1234`
- Non-obvious WHY: `// must run before X because Y races otherwise`
- Type-assertion / unsafe-cast justifications: `// safe — input validated upstream by Zod schema`
- License headers
- Public-API JSDoc on functions exported from the package
- Regex explanations
- Comments that match a clear in-repo style (other files use the same pattern)

(B) OVER-DEFENSIVE CODE

REMOVE:
- Defensive null checks on values the type system already guarantees non-null
- `if (x !== null && x !== undefined && x.attr !== null) ...` when `x` is typed non-nullable
- `try/catch` around code that demonstrably cannot throw (dict literal access, pure arithmetic on numbers)
- Optional chaining `?.` on values typed non-nullable
- `isinstance()` / `typeof` checks for statically typed parameters
- `?? defaultValue` wrapping framework-guaranteed values
- Default values for required parameters that are immediately validated
- Re-exports of unused items
- Backward-compat shims with no consumer

KEEP:
- Validation at system boundaries: user input, external API responses, file reads, env vars, message bus payloads
- Error handling for I/O: fs, network, subprocess, parse, JSON.parse on untrusted input
- Auth / authz / audit checks even if "the route is protected"
- Null checks for nullable DB fields
- Assertions in test code that pin type expectations

(C) SPAGHETTI NESTING (2+ levels deep)

REFACTOR:
- Nested `if (a) { if (b) { if (c) { ... } } }` → early-return guards (`if (!a) return; if (!b) return; ...`)
- `else { if (...) { ... } }` → `else if (...)`
- Nested loops with conditionals that could be a single comprehension / filter
- Complex chained ternary `a ? b : (c ? d : e)` → explicit if/else block

KEEP nesting when:
- The shape carries meaning (state-machine transition table, decision tree where flattening obscures intent)
- Flattening would lose clarity — e.g. parallel `if`s with shared cleanup
- Existing code in the same file uses the nesting style intentionally and consistently

------------------------------------------------------------
SAFETY RULES (NEVER violate)
------------------------------------------------------------

1. NEVER remove error handling for I/O (fs, network, subprocess, parse).
2. NEVER simplify validation for user input or external data.
3. NEVER remove a comment that contains a ticket number, URL, or "WHY" rationale.
4. NEVER remove auth/authz/audit checks — even "the route is already protected" is not your call.
5. NEVER refactor across function boundaries. This skill is cleanup, not architecture.
6. NEVER remove TODOs with assignees or context — only context-free placeholders.
7. NEVER change a function signature, rename anything, or move code between files.
8. NEVER remove type hints / annotations.
9. NEVER remove BDD scenario markers (#given / #when / #then / arrange / act / assert).
10. When in doubt: SKIP. False negatives (leaving slop in) are strictly better than false positives (breaking code).

------------------------------------------------------------
4-STEP PROCESS
------------------------------------------------------------

Step 1 — Read & analyze the WHOLE file (not just changed lines). Identify every candidate with line number.

Step 2 — For EACH candidate, run the safety check:
  - "If I remove this and I'm wrong, what breaks?"
  - "Is there any chance this is at a system boundary?"
  - "Is there any chance the code can actually throw / be null at runtime?"
  - If you can't answer all three with high confidence, skip the candidate.

Step 3 — Execute the surviving changes via the Edit tool. One logical change per Edit call where possible.

Step 4 — Report back in the EXACT format below.

------------------------------------------------------------
REPORT FORMAT (return this verbatim shape)
------------------------------------------------------------

File: <ABSOLUTE_PATH_TO_F>
Removed: <N> items
  - L<line>: <category A|B|C> — <one-line description of what was removed and why safe>
  - L<line>: ...
Kept (looked like slop, preserved for safety): <K> items
  - L<line>: <reason — which safety rule applied>
Risks: <0-3 items>
  - <any concern about the changes>

If the file is already clean, set Removed: 0 and Kept: 0 and Risks: 0 and write a one-line note "no slop found".
"""
)
```

**Critical**: send ALL Task calls in a single message, not sequentially. This is the parallel-fan-out idiom for Claude Code.

### Phase 5 — Collect worker reports

Wait for all worker `Task` calls to return. As reports come back, append them to your internal notes. Do not modify files yourself in this phase.

If a worker fails to return, note it and continue — you will mention it in the summary. Do not re-fire failed workers automatically; ask the user if they want a retry.

### Phase 6 — Critical review

Walk through every worker report against this checklist. Use `Grep` / `Read` against the modified files to spot-check claims.

**Safety**
- For each "Removed" item: does it look like it could have been at a system boundary? If yes, restore the original from `.omo/ai-slop-runs/<TS>/originals/`.
- Did any worker remove a `try`/`catch`? Run `Grep` against the original to confirm the catch wasn't load-bearing.
- Did any worker remove a comment containing `TODO`, `LINEAR-`, `SPR-`, `GH-`, `http`, `https`, `fix`, `bug`? If yes, restore.
- Did any worker remove BDD markers (`given`/`when`/`then`)? If yes, restore.

**Behavior**
- Did any worker change a function name, signature, or move code? That's out of scope — restore.
- Did any worker remove a line that wasn't a comment, a defensive check, or nested control flow? If yes, restore.

**Quality**
- Are the per-file rationales coherent? A worker that says "removed null check on x" but the original had no null check on x is hallucinating — restore.
- Does the "Kept" list show real safety reasoning, or did the worker just refuse to do anything? If everything was kept, that's fine; if everything was removed with no Kept items on a non-trivial file, double-check.

**Restore procedure** for any file that fails review:

```bash
TS=<the timestamp from Phase 3>
F=<the file path>
FLAT=$(echo "$F" | tr '/' '__')
cp ".omo/ai-slop-runs/$TS/originals/$FLAT" "$F"
```

### Phase 7 — Summary

End the run with a structured summary, and tell the user where the rollback directory lives so they can do their own audit.

```
## AI Slop Cleanup Summary

Scope: <branch | staged | all>
Base branch (if branch scope): <name>
Files considered: <N>
Files processed: <M>
Files skipped (filter): <K>

Total items removed across all files: <X>
Total items kept-for-safety: <Y>
Files restored during critical review: <Z>

Rollback directory: .omo/ai-slop-runs/<TS>/originals/
  (copy any flattened file back to its original path to undo this run for that file)

Per-file detail:
- <path>: <removed> removed, <kept> kept[, restored]
- ...
```

If any worker report had a non-empty Risks section, surface those at the top of the summary so the user sees them immediately.

## ANTI-PATTERNS — do not do these

| Anti-pattern | Why it's wrong |
|---|---|
| Cleaning files yourself instead of fanning out workers | Defeats parallelism and loses the per-file safety boundary |
| Skipping Phase 3 (originals copy) | No rollback path if a worker over-deletes |
| Using `git checkout -- <file>` to roll back | Discards pre-existing branch changes that are not slop-related |
| Sending Task calls sequentially | Wastes the parallel fan-out idiom; turns a 30-second run into 10 minutes |
| Letting a worker handle more than one file | Worker prompt explicitly rejects multiple files; one file per Task call |
| Removing BDD markers, ticket links, or WHY comments | Violates the discipline; restore immediately |
| Re-firing workers in a loop until "everything is clean" | This is cleanup, not optimization. One pass is enough. |
| Running on non-code files (.md, .json, .yaml) | Filter in Phase 2 exists for a reason |
| Capping above 20 parallel Tasks | Causes contention and rate limits; cap is hard |

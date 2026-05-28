---
name: omo-init-deep
description: Hierarchical CLAUDE.md generator. Fans out parallel exploration agents to map the codebase, scores subdirectories, and writes a root CLAUDE.md plus per-directory CLAUDE.md files. Useful for project onboarding. Triggers: init-deep, generate CLAUDE.md, codebase init, hierarchical agents.md, /omo-init-deep
argument-hint: '[--create-new] [--max-depth=N]'
allowed-tools: Task Bash Read Write Edit Glob Grep AskUserQuestion TaskCreate TaskUpdate TaskList
---

# INIT-DEEP — Hierarchical CLAUDE.md Generator

Generate a root `CLAUDE.md` plus per-directory `CLAUDE.md` files for the subdirectories that earn one. The result is a hierarchical knowledge base: top-level orientation at the root, focused local context in each scored subdirectory, no duplication.

> **Naming note**: upstream omo writes `AGENTS.md`. In Claude Code we write `CLAUDE.md` (matches `/init` and the user's existing convention). Wherever upstream said `AGENTS.md`, write `CLAUDE.md`.

## USAGE

```
/omo-init-deep                    # Update mode: modify existing + create new where warranted
/omo-init-deep --create-new       # Read existing → delete all → regenerate from scratch
/omo-init-deep --max-depth=2      # Cap directory depth to walk (default: 3)
```

If existing `CLAUDE.md` files are present anywhere in the tree AND `--create-new` was NOT specified, that is fine — you operate in **update mode**: read them, preserve hand-written context, only modify where stale or missing. If the user clearly wants a clean regenerate but did not pass `--create-new`, **stop and tell them** to re-run with `--create-new`, or delete the existing files first. Do not silently overwrite hand-edited docs.

## WORKFLOW (4 PHASES)

Use `TaskCreate` once at the start to register one todo per phase, plus one todo per subdirectory `CLAUDE.md` you intend to write. Mark `in_progress` → `completed` as you go so the user sees progress.

```
TaskCreate([
  { content: "Phase 1 — Discovery: fan out explore agents + bash analysis", priority: "high" },
  { content: "Phase 2 — Score subdirectories and decide CLAUDE.md locations", priority: "high" },
  { content: "Phase 3 — Generate root + per-dir CLAUDE.md files", priority: "high" },
  { content: "Phase 4 — Review and deduplicate", priority: "medium" }
])
```

---

### Phase 1 — Discovery + Analysis (concurrent)

**Fire 6 background `omo-explore` agents in parallel — in ONE message.** Do not wait for them; the main turn runs bash analysis concurrently.

```
Task(subagent_type="omo-explore", description="Project structure", prompt="Map the top-level project structure. Identify primary language(s), framework(s), build system, and any monorepo layout (workspaces, packages/, apps/). REPORT deviations from standard layouts for that language/framework. Absolute paths in findings.")
Task(subagent_type="omo-explore", description="Entry points", prompt="Find entry points: main.py / src/index.ts / cmd/*/main.go / bin/* / package.json scripts / README files. List each with absolute path and a one-line role.")
Task(subagent_type="omo-explore", description="Code conventions", prompt="Find code-style conventions: naming (camelCase vs snake_case vs PascalCase), file organization patterns (feature folders vs layer folders), formatter config (.prettierrc, ruff.toml, .editorconfig), linter config (.eslintrc, pyproject.toml [tool.ruff], golangci.yml). Quote the project-specific rules; ignore defaults.")
Task(subagent_type="omo-explore", description="Anti-patterns", prompt="Find anti-patterns and forbidden practices in the codebase. Grep for 'DO NOT', 'NEVER', 'DEPRECATED', 'TODO', 'FIXME', 'HACK', 'XXX' in comments and existing docs. List the forbidden patterns and any active tech-debt callouts with file:line citations.")
Task(subagent_type="omo-explore", description="Build & CI", prompt="Find build and CI configuration: Makefile, justfile, Taskfile, .github/workflows/*, .gitlab-ci.yml, Dockerfile, docker-compose.*, Procfile, fly.toml, vercel.json. Report the non-default targets and CI jobs.")
Task(subagent_type="omo-explore", description="Test patterns", prompt="Find test patterns: test framework (jest/vitest/pytest/go test/etc.), test file locations (alongside source vs __tests__ vs tests/), naming conventions (*.test.ts vs *_test.go vs test_*.py), and any unique test infrastructure (custom fixtures, snapshot dirs, golden files).")
```

While those run, in the **same** turn, do bash analysis. Bundle these into one `Bash` call where reasonable:

```bash
# Structural snapshot
find . -type d \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .next -o -name venv -o -name __pycache__ \) -prune -o -type d -print | head -200

# File count + depth
find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/build/*' | wc -l
find . -type d -not -path '*/node_modules/*' -not -path '*/.git/*' | awk -F/ '{print NF-1}' | sort -rn | head -1

# Files per directory (top 30)
find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -30

# Existing CLAUDE.md / AGENTS.md files
find . -type f \( -name CLAUDE.md -o -name AGENTS.md \) -not -path '*/node_modules/*'

# Monorepo signal
ls -1 package.json pnpm-workspace.yaml turbo.json nx.json go.work Cargo.toml 2>/dev/null
ls -1d packages apps services workspaces 2>/dev/null
```

For each existing `CLAUDE.md` / `AGENTS.md` found, `Read` it. Preserve hand-written context (especially anti-patterns, gotchas, command lists) — those typically encode operational knowledge that exploration cannot recover.

**Dynamic agent spawning** based on project scale. After the bash snapshot above is back, recompute and spawn ADDITIONAL `omo-explore` agents in a second parallel wave if any of these thresholds are crossed:

| Signal | Threshold | Add agents |
|---|---|---|
| Source files | > 1000 | +1 per 100 distinct source-bearing subdirs |
| Tree depth | > 5 | +2 for deep-module sweep |
| Monorepo (workspaces / packages / apps dirs) | any | +1 per top-level workspace |
| Large files (> 500 LOC) | > 10 files | +1 for complexity hotspots |
| Multiple primary languages | > 1 | +1 per additional language |

The base math is roughly: ~1 additional explore agent per 100 source files spread across distinct sub-modules. Cap the total at ~20 agents — beyond that, returns diminish. Each added agent gets a focused prompt (one workspace, one hotspot file cluster, one language tree).

Wait for all explore returns. Merge findings into a single in-memory `DISCOVERY` summary you will reference in Phase 2. Mark the Phase 1 todo `completed`.

---

### Phase 2 — Scoring & Location Decision

For every subdirectory in the tree (up to `--max-depth`, default 3), compute a weighted score and decide whether it gets its own `CLAUDE.md`.

**Scoring matrix:**

| Signal | Weight | Source |
|---|---|---|
| File count in this dir (recursive) | ×3 | bash |
| Direct subdirectory count | ×2 | bash |
| Code-to-total ratio (source files / all files) | ×2 | bash |
| Unique patterns or conventions vs siblings | ×1 | explore agents |
| Module boundary indicator (`package.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`, `index.ts`, `__init__.py`) | ×2 | bash |
| Symbol density (approx functions/classes per LOC) | ×2 | `Grep` for `function`/`class`/`def`/`func` per LOC |
| Export count (approximate, from `index.*` or module barrels) | ×2 | `Grep` `^export ` / `__all__` |
| Reference centrality (incoming references from other files) | ×3 | `Grep` for the dir name or its index path |

Approximate the LSP-derived signals (symbol density, exports, centrality) with `Grep`. They are heuristics, not precise — that is fine; the matrix is robust to noisy individual signals.

**Decision thresholds:**

- **Root (`.`) ALWAYS gets a `CLAUDE.md`.** No exceptions.
- **Score > 15** → create.
- **Score 8–15** → create only if the directory represents a **distinct domain** (a clearly different concern from its siblings; for example `src/auth/` next to `src/billing/` are distinct domains, but `src/utils/strings/` next to `src/utils/dates/` likely are not).
- **Score < 8** → skip; the parent's `CLAUDE.md` covers it.

Respect `--max-depth=N` if provided — never propose a `CLAUDE.md` deeper than N levels under root.

Build a list:

```
CLAUDE_LOCATIONS = [
  { path: ".", type: "root" },
  { path: "src/hooks", score: 22, reason: "high file count + centrality" },
  { path: "src/api", score: 14, reason: "distinct domain from src/components" },
  ...
]
```

If you have `CLAUDE.md` files at locations NOT in this list (and `--create-new` was not specified), keep them — do not delete user-curated docs.

Mark Phase 2 todo `completed`.

---

### Phase 3 — Generate

#### Step 3a — Root CLAUDE.md first

Generate the root `CLAUDE.md` **before** the subdirectory files, because subdirs reference and rely on root conventions. Target 50–150 lines. Required sections:

```markdown
# <Project Name>

## OVERVIEW
<1–2 paragraphs: what this project does, primary stack, top-level architecture in one sentence.>

## STRUCTURE
<Top-level directory tree with one-line role per dir. ASCII tree.>

```
project/
├── src/             # <role>
├── packages/        # <role>
├── scripts/         # <role>
└── ...
```

## WHERE TO LOOK
<Quick-reference task → location table. The 8–15 most common tasks.>

| Task | Location | Notes |
|---|---|---|
| Editing UI components | `src/components/` | shadcn/ui + Tailwind |
| Adding an API endpoint | `src/api/` | REST handlers |
| ... | ... | ... |

## CODE MAP — high-traffic modules
<Top 20 most-edited files in the last 90 days. Generate via:>
<`git log --since='90 days ago' --name-only --pretty=format: | sort | uniq -c | sort -rn | head -20`>

| File | Edits (90d) | Role |
|---|---|---|
| `src/foo/bar.ts` | 47 | <role> |
| ... | ... | ... |

## CONVENTIONS
<Project-specific naming, formatting, file organization, import style.>
<Only deviations from the language/framework defaults. Skip the obvious.>

## ANTI-PATTERNS
<Things to avoid in THIS codebase. Pulled from Phase 1 explore agent for "DO NOT / NEVER / DEPRECATED" and from existing CLAUDE.md / AGENTS.md content.>

## UNIQUE STYLES
<Non-obvious patterns specific to this repo — code patterns that deviate from typical conventions for the stack. Often the most valuable section.>

## COMMANDS
<Key shell commands the dev runs daily.>

```bash
make up        # <what it does>
make test      # <what it does>
make lint      # <what it does>
```

<Verify each command actually exists via `Bash` before listing it. Hallucinated commands are the worst possible failure mode for this file.>

## NOTES
<Anything else load-bearing. Gotchas. Environmental requirements. External dependencies.>
```

**CODE MAP rule (replaces upstream LSP-based CODE MAP)**: upstream omo populated this section from `lsp_workspace_symbols`. We do not have LSP. Instead use git heat — the 20 most-edited files over the last 90 days. These are the files a new contributor will land in. Run:

```bash
git log --since='90 days ago' --name-only --pretty=format: 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -20
```

For each of the 20 files, write a one-line role. Skip the table only if the repo has fewer than ~10 source files OR no git history.

Write the root file with `Write` if it does not exist; with `Edit` if it does (preserve hand-edited sections by reading first and replacing only stale content).

#### Step 3b — Subdirectory CLAUDE.mds in parallel

In **ONE message**, spawn a parallel `Task(subagent_type="omo-worker-default", ...)` for each non-root entry in `CLAUDE_LOCATIONS`. Each subdir file is 30–80 lines. Required sections:

```markdown
# <subdir path>

## WHAT'S HERE
<1–2 paragraphs: this subdir's purpose, what concerns it owns, how it fits the broader project.>

## KEY FILES

| File | Role |
|---|---|
| `index.ts` | <role> |
| `useFoo.ts` | <role> |
| ... | ... |

## LOCAL PATTERNS
<Anything specific to THIS subdir that deviates from project-wide conventions. If nothing deviates, write "Inherits project conventions." and skip.>

## DON'T
<Anti-patterns specific to THIS area. If none, omit the section entirely.>
```

**NEVER repeat content from the root.** No project overview, no global commands, no global conventions. Subdir files are local-only.

Dispatch prompt template for each subdir worker:

```
Write CLAUDE.md at <absolute-path-to-dir>/CLAUDE.md.

Directory: <path>
Selection reason: <score + reason>
Max length: 30–80 lines.

REQUIRED SECTIONS:
- WHAT'S HERE (1–2 paragraphs)
- KEY FILES (table of file → role)
- LOCAL PATTERNS (anything specific to this subdir that deviates from project-wide; omit if no deviation)
- DON'T (anti-patterns specific to this area; omit if none)

HARD RULES:
- Do not repeat content from the root CLAUDE.md at <absolute-path-to-root>/CLAUDE.md (read it first).
- No placeholder text ("TODO", "TBD", "fill in later"). If you cannot fill a section confidently, omit it.
- Cite real files only; verify each with Read or Glob before writing.
- Telegraphic style. No filler. No "this directory contains X" — say what X is and why it matters.
- Use Write tool. Absolute file path.

After writing, return a one-line confirmation with the path and line count.
```

Wait for all returns. Mark Phase 3 todo `completed`.

---

### Phase 4 — Review & Deduplicate

After all files are written:

1. **Re-read every generated `CLAUDE.md`** (use `Bash`: `find . -name CLAUDE.md -type f -not -path '*/node_modules/*'` then `Read` each).
2. **Detect cross-file duplication**: content that appears in the root AND in a subdir → keep in root only; remove from subdir.
3. **Detect placeholders**: any `TODO`, `TBD`, `<...>`, "fill in later", "to be determined", or empty section → re-spawn the relevant `omo-worker-default` with explicit instruction `MUST NOT leave placeholders. If a section cannot be filled confidently, omit it entirely.`
4. **Verify file count matches plan**: re-run `find . -name CLAUDE.md -type f -not -path '*/node_modules/*' | wc -l` and confirm it equals `len(CLAUDE_LOCATIONS)` plus any pre-existing files you preserved.
5. **Trim oversized files**: root > 150 lines or subdir > 80 lines → re-spawn with tighter target.

Mark Phase 4 todo `completed`.

---

## FINAL REPORT

End the run with a structured summary, then print the root `CLAUDE.md` contents inline to the conversation so the user can review without opening files:

```
=== init-deep complete ===

Mode: <update | create-new>
Files created: <N>
Files updated: <M>
Files preserved (no change): <K>
Total time: <approx>

Hierarchy:
  ./CLAUDE.md (root, <N> lines)
  ├── src/hooks/CLAUDE.md (<N> lines)
  ├── src/api/CLAUDE.md (<N> lines)
  └── ...

--- ROOT CLAUDE.md ---
<paste full contents>
```

---

## ANTI-PATTERNS

Avoid these failure modes. They are why init-deep runs go wrong.

- **Writing a `CLAUDE.md` in a directory the user will never edit.** Vendor dirs, generated code, build output — score them to skip. Just because a dir has files does not mean it deserves docs.
- **Copy-pasting code into the docs.** Link to file paths instead (`see src/auth/middleware.ts`). Code rots; references survive.
- **Including time-decay info.** "Recent changes", "TODOs", "current refactor in progress" all belong in git history or issue trackers, not in a `CLAUDE.md`. Write for the reader six months from now.
- **Hallucinating commands the project does not have.** Before you list `make foo` or `pnpm bar`, verify with `Bash` that the target exists in the Makefile or `package.json`. A wrong command in `CLAUDE.md` is worse than no command.
- **Static agent count.** Phase 1 dynamic spawning matters — a 5000-file monorepo needs more explore agents than a 50-file utility. Use the threshold table.
- **Sequential phases when they could be parallel.** Phase 1 explore agents and bash analysis run concurrently. Phase 3 subdir writers all run in one parallel wave. Do not serialize.
- **Repeating root content in subdirs.** The whole value of a hierarchy is local-only context per node. If a subdir's `CLAUDE.md` would say things any project would say, skip the file.
- **Generic content.** Anything that applies to "any TypeScript project" or "any Python project" is filler — remove it. The reader has internet access for generic info.
- **Verbose prose.** Telegraphic style: tables, lists, one-line roles. Save paragraphs for the OVERVIEW sections only.
- **Overwriting hand-edited docs without permission.** If `--create-new` was not specified, preserve existing content — read, merge, do not blast.

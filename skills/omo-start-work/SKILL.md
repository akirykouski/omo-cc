---
name: omo-start-work
description: Kick off work on a Prometheus-generated plan. Discovers .omo/plans/, resumes active boulder.json if present, optionally creates a git worktree for isolated work. Triggers: start work, resume plan, start-work, /omo-start-work
argument-hint: '[plan-name] [--worktree <path>]'
allowed-tools: Task Bash Read Write Edit Glob Grep AskUserQuestion TaskCreate TaskUpdate TaskList
---

# START-WORK — Resume or kick off a Prometheus plan

You are starting an omo work session. This skill **finds-or-creates** a Prometheus-generated plan, optionally drops you into a git worktree, decomposes the plan into granular sub-tasks, and hands off to the ultrawork execution loop. It does NOT itself plan — `omo-prometheus` does that. It does NOT itself implement — the ultrawork workflow does that. This is the **kickoff**.

## ARGUMENTS

```
/omo-start-work [plan-name] [--worktree <path>]
```

- `plan-name` (optional) — exact or partial match of a plan file under `.omo/plans/`. If omitted, the skill auto-selects (one plan → take it; many plans → ask the user).
- `--worktree <path>` (optional) — absolute path to a git worktree to run inside. If the worktree exists, the skill records it in `boulder.json`. If it does not exist, the skill creates it via `git worktree add`. If omitted, work happens in the current project directory.

## WORKFLOW

Register a checklist with `TaskCreate` for the steps below so the user sees progress.

```
TaskCreate([
  { content: "Find available plans + check active boulder state", priority: "high" },
  { content: "Decide which plan to resume / start", priority: "high" },
  { content: "Worktree setup (if --worktree was passed)", priority: "high" },
  { content: "Write/update .omo/boulder.json", priority: "high" },
  { content: "Read plan file + decompose into granular tasks", priority: "high" },
  { content: "Hand off to ultrawork execution loop", priority: "high" }
])
```

---

### Step 1 — Find available plans

```bash
find .omo/plans -type f -name '*.md' 2>/dev/null
```

If `.omo/plans/` does not exist or is empty: tell the user there are no Prometheus-generated plans yet, suggest they run `omo-hyperplan` or invoke `omo-prometheus` directly, and stop. Do not proceed.

For each found plan, capture:
- absolute path
- modified time (`stat -f %m <path>` on macOS, `stat -c %Y <path>` on Linux)
- progress (count `- [x]` vs total checkbox lines via `Grep`)

### Step 2 — Check for active boulder state

```
Read .omo/boulder.json (if it exists)
```

The boulder file tracks the in-flight plan(s). Schema:

```json
{
  "active_plan": "/absolute/path/to/plan.md",
  "started_at": "ISO-8601",
  "session_ids": ["<opaque-id-1>", "<opaque-id-2>"],
  "plan_name": "<plan-name>",
  "worktree_path": "/absolute/path/or/null",
  "status": "active"
}
```

Older boulder files may contain a list of works, each with its own `status: active | paused | complete`. Handle both shapes — single object or `{ "works": [...] }`.

### Step 3 — Decision logic

Apply in order:

1. **Multiple active works** in `boulder.json` (i.e. more than one entry with `status: active` or `paused`):
   - Use `AskUserQuestion` to ask which to resume. Options: each active plan's name + one "start a new plan" option (capped at 4 options total — show the 3 most recent + "start new" if there are >3).
   - On selection, treat as if the user invoked `/omo-start-work <selected-plan>`.

2. **Exactly one active work** AND no `plan-name` arg:
   - Auto-resume that single active work. No question to the user.

3. **No active plan, or all complete**:
   - If exactly ONE plan file in `.omo/plans/` → auto-select it.
   - If MULTIPLE plan files → use `AskUserQuestion` to pick (max 4 options; if more, show the 3 most-recently-modified + a "Other" option that lists the rest in the conversation).

4. **`plan-name` arg provided**:
   - Match against plan file names (exact match first, then `glob`-style partial). If unique match → use it. If multiple matches → `AskUserQuestion` to disambiguate. If no match → tell the user and list available plans.

### Step 4 — Worktree setup

**Only run this step if `--worktree <path>` was explicitly passed AND `worktree_path` is not already set in `boulder.json`.** Otherwise skip.

```bash
git worktree list --porcelain
```

If the target path is already a registered worktree → record it in `boulder.json` and proceed.

Otherwise create it. The branch defaults to a new branch derived from the plan name unless the user specifies otherwise:

```bash
git worktree add <absolute-path> <branch-or-HEAD>
```

All subsequent work happens **inside that worktree directory**. If you cannot chdir (Claude Code sessions cannot truly cd), always use absolute paths under the worktree path for every Read/Edit/Write/Bash call.

### Step 5 — Write / update `.omo/boulder.json`

We do not have a hook in Claude Code that injects a session id (unlike upstream omo). Generate an opaque session id yourself:

```bash
date -u +"%Y%m%dT%H%M%SZ"
```

That timestamp string is the session id (suffix it with a short random hex if you want extra uniqueness: `printf "%sT%s" "$(date -u +%Y%m%dT%H%M%SZ)" "$(openssl rand -hex 3)"`). It is opaque to the system; only needs to be unique across resumes.

Write boulder.json:

```json
{
  "active_plan": "/absolute/path/to/plan.md",
  "started_at": "2026-05-28T20:14:33Z",
  "session_ids": ["20260528T201433Z-a4f8b2"],
  "plan_name": "fix-login-bug",
  "worktree_path": "/absolute/path/or/null",
  "status": "active"
}
```

If resuming, append the new session id to `session_ids` rather than overwriting. Always write boulder.json BEFORE starting work — if the session crashes mid-execution, this is the state the next resume will read.

### Step 6 — Read the plan file

`Read` the full plan file. Do not skip sections. Plans typically follow the Prometheus template: TL;DR / Context / Work Objectives / Verification Strategy / Execution Strategy (Parallel Execution Waves) / TODOs / Final Verification Wave / Commit Strategy / Success Criteria.

### Step 7 — MANDATORY task breakdown

Decompose **every plan task** into granular, implementation-level sub-steps and register **all of them** via `TaskCreate` BEFORE starting any work. This is non-negotiable — start-work without a registered breakdown is start-work done wrong.

**Breakdown rules**:

- Each plan checkbox (`- [ ] Add user authentication`) becomes a set of concrete sub-tasks.
- Each sub-task names specific files, functions, and verification — "add validateToken() to src/auth/middleware.ts that checks JWT expiry and returns 401" is acceptable; "implement feature X" is not.
- Use `blockedBy` to encode dependencies between sub-tasks so the ultrawork loop can pick the next unblocked task without re-deriving the dependency graph each turn.
- Group sub-tasks by parallel-execution wave when the plan specified one — sub-tasks in the same wave are independent and should NOT block each other.

**Example breakdown**:

Plan task: `- [ ] Add rate limiting to API`

Becomes the following TaskCreate entries:

```
TaskCreate([
  { content: "Create src/middleware/rate-limiter.ts with sliding-window algorithm (100 req/min per IP)", priority: "high" },
  { content: "Wire RateLimiter middleware into src/app.ts router chain BEFORE auth middleware", priority: "high", blockedBy: ["<id of rate-limiter.ts task>"] },
  { content: "Set X-RateLimit-Limit / X-RateLimit-Remaining response headers in rate-limiter.ts", priority: "high", blockedBy: ["<id of rate-limiter.ts task>"] },
  { content: "Add test: verify 429 after exceeding limit in src/middleware/rate-limiter.test.ts", priority: "medium", blockedBy: ["<id of header task>"] },
  { content: "Add test: verify rate-limit headers present on normal responses", priority: "medium", blockedBy: ["<id of header task>"] }
])
```

Repeat for every checkbox in the plan. Do not start work until the full breakdown is registered.

### Step 8 — Hand off to ultrawork

Once boulder.json is written, the plan is read, and the task breakdown is registered, you hand off to the ultrawork execution loop.

**Two options:**

1. **Recommended — proceed inline.** Continue in this same session by following the `omo-ultrawork` Phase D (Execution) pattern: pick the next unblocked task from `TaskList`, dispatch via `Task(subagent_type="omo-<category-worker>", ...)` (or `omo-hephaestus` for autonomous deep work), verify, mark complete, loop until all tasks done. The ultrawork principles you must follow: explore before guessing, parallel fan-out for independent work, mandatory verification gate (typecheck + tests + lint) before marking a task done, consult `omo-oracle` after 3 failed attempts at the same sub-task. If the user invoked `/omo-start-work` directly, this inline continuation is what they expect.

2. **Alternative — explicit handoff.** Tell the user to invoke `/omo-ultrawork` next, providing the plan path and active boulder as context. Use this only if you have a specific reason to break the session here (e.g. you set up a new worktree and want the user to verify before grinding).

Default to option 1 unless something concrete blocks it.

---

## OUTPUT FORMATS

**Listing plans for selection**:

```
Available work plans

Current time: <ISO-8601>
Session id: <opaque-id>

1. <plan-name-1.md>  modified: <date>  progress: 3/10 tasks
2. <plan-name-2.md>  modified: <date>  progress: 0/5 tasks

(Use AskUserQuestion if 2+ plans, with the top 3 + "Other" as options.)
```

**Resuming existing work**:

```
Resuming work session

Active plan: <plan-name>
Progress: <completed>/<total> tasks
Sessions: <count> (appending current)
Worktree: <path-or-"(none)">

Reading plan and continuing from last incomplete task...
```

**Auto-selecting a single plan**:

```
Starting work session

Plan: <plan-name>
Session id: <opaque-id>
Started: <ISO-8601>
Worktree: <path-or-"(none)">

Reading plan and beginning execution...
```

---

## WORKTREE COMPLETION

When working inside a worktree (`worktree_path` is set in boulder.json) AND **all plan tasks are complete**, do not auto-merge into main. The user owns the merge decision. Do this:

1. **Commit remaining changes** inside the worktree:
   ```bash
   git -C <worktree-path> add -A
   git -C <worktree-path> commit -m "<conventional message tying back to the plan>"
   ```

2. **Sync `.omo/` state back to the main repo.** This matters when `.omo/` is gitignored — state written during worktree execution would otherwise be lost on worktree removal:
   ```bash
   cp -r <worktree-path>/.omo/* <main-repo>/.omo/ 2>/dev/null || true
   ```

3. **Inform the user** of the worktree path, the branch, and the suggested next step (review, merge, or open a PR). Print the absolute worktree path and the branch name so they can run their own merge command.

4. **Do NOT auto-merge** and **do NOT remove the worktree**. The main session leaves the worktree intact for review. If the user explicitly asks to merge + remove, then run `git merge <branch>` from the main repo and `git worktree remove <worktree-path>` after.

Skip this whole section if the work happened in the main checkout (no `worktree_path` in boulder.json).

---

## CRITICAL RULES

- **Always update `.omo/boulder.json` BEFORE starting work.** This is the resume contract for the next session.
- **Read the FULL plan file** before delegating any sub-task. Partial reads cause partial implementations.
- **Decompose every checkbox** in the plan via `TaskCreate` before running anything. The breakdown is the contract; vague tasks produce vague code.
- **Absolute paths everywhere.** Worktree workflows fail subtly if you mix relative and absolute paths across `Bash` calls.
- **Do not silently auto-merge a worktree.** The user owns the merge decision.
- **Do not run destructive git operations** (`reset --hard`, `clean -fd`, force-push) unless the user explicitly requested them.

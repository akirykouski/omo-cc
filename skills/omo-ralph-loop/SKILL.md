---
name: omo-ralph-loop
description: Self-referential development loop. Drives a task to completion across multiple iterations, exiting only when the agent emits the completion-promise tag. Pairs with Claude Code's /loop skill for autonomous pacing across sessions. Triggers, ralph-loop, ralph, ulw-loop, ultrawork loop, autonomous loop, self-referential loop, /omo-ralph-loop
argument-hint: '"<task>" [--completion-promise=TEXT] [--max-iterations=N] [--strategy=reset|continue] [--ultrawork]'
allowed-tools: Task Bash Read Write Edit Glob Grep AskUserQuestion TaskCreate TaskUpdate TaskList
---

# RALPH LOOP — Self-Referential Task Driver

> **MANDATORY**: First line of your response, exactly: `RALPH LOOP ENGAGED.` (or `ULTRAWORK LOOP ENGAGED.` if the `--ultrawork` flag was passed). No preamble before that line.

## Why Ralph Loop?

Named after the Ralph Wiggum-esque pattern of self-referential prompting — "I'm helping" → "I'm still helping" → "I'm still helping" — this skill drives a task to truly-done by re-prompting on every continuation token. Use it when you want a task to grind to completion without manual prodding, when partial credit is unacceptable, or when you want the agent to keep trying alternative approaches until something works. The exit token is `<promise>DONE</promise>` (or whatever you configure). Until that token fires, the loop continues.

## Pairing with Claude Code's `/loop` skill

For **autonomous pacing across sessions**, run this skill via the built-in `/loop` skill:

```
/loop 5m /omo-ralph-loop "<your task>"
```

That delegates pacing (re-invocation interval) to `/loop` while this skill owns the omo idiom — the durable state file, the completion-promise convention, and (for ultrawork mode) the Oracle verification gate.

If you don't pair with `/loop`, this skill can also be invoked **once** and will iterate until the promise tag fires **in-session**. Use the paired form for long-running tasks that span multiple Claude Code sessions.

## EXECUTION WORKFLOW

### Phase 0 — Acknowledge and parse args

1. First line, exactly: `RALPH LOOP ENGAGED.` (normal mode) or `ULTRAWORK LOOP ENGAGED.` (`--ultrawork` flag).
2. Parse the user's argument string. Expected shape:

   ```
   "<task description>" [--completion-promise=TEXT] [--max-iterations=N] [--strategy=reset|continue] [--ultrawork]
   ```

   Defaults:
   - `completion-promise` → `DONE`
   - `max-iterations` → `100` for normal mode, `500` for `--ultrawork`
   - `strategy` → `continue` (preserve prior state); `reset` wipes `.omo/ralph-loop.local.md` first
   - `--ultrawork` → off (no Oracle verification step)

3. Use `TaskCreate` to register one task per iteration as you go (don't pre-populate all 100; add them as each completes).

### Phase 1 — State setup

Read or create `.omo/ralph-loop.local.md`. If `strategy=reset`, overwrite it. If `strategy=continue` and the file exists with `Status: CANCELED`, refuse to start and tell the user to either pass `--strategy=reset` or manually flip the status — do not silently resurrect a canceled loop.

The state file format (write via `Write` on first run, then `Edit` on subsequent updates):

```markdown
# Ralph Loop State

**Task**: <task description>
**Completion promise**: <promise>
**Max iterations**: <N>
**Strategy**: <reset | continue>
**Ultrawork mode**: <true | false>
**Started**: <ISO-8601 UTC>
**Current iteration**: <N>

## Iteration log

- [<ISO-ts>] Iter 1: <one-line outcome — what was done / what's next>
- [<ISO-ts>] Iter 2: <one-line outcome>

## Status

RUNNING
```

`Status` is one of: `RUNNING`, `COMPLETED`, `CANCELED`.

Generate the ISO timestamp with `Bash`: `date -u +%Y-%m-%dT%H:%M:%SZ`.

### Phase 2 — Iterate

For each iteration up to `max-iterations`:

1. **Check cancel signal first.** Re-read `.omo/ralph-loop.local.md`. If `Status: CANCELED`, stop immediately and report the cancel.
2. **Do the work.** Use whatever tools the task needs (Read, Edit, Bash, Task fan-out, etc.). Make meaningful progress — do NOT just emit the promise to bail out.
3. **Decide if the task is FULLY complete.** Apply the "is this truly done?" test:
   - All acceptance criteria from the task description met?
   - Tests run? Lints pass? Typecheck clean? (Run them if relevant.)
   - No "I'll come back to this later" remnants? No `TODO` markers added by you?
   - The user's literal request AND their actual underlying need both addressed?
4. **If complete**, emit on its own line, exactly:

   ```
   <promise>DONE</promise>
   ```

   (Replace `DONE` with the configured `completion-promise` text.)

   - **Normal mode**: This terminates the loop. Update state to `Status: COMPLETED`. Stop.
   - **Ultrawork mode**: Do NOT terminate yet. Go to Phase 3 (Oracle gate).

5. **If not complete**, append a one-line iteration log entry to `.omo/ralph-loop.local.md` and continue to the next iteration.

6. **If stuck** (same failure twice in a row, no progress), try a different approach:
   - If you've been doing direct edits, fan out an `omo-explore` Task to find a missed pattern in the codebase.
   - If you've been exploring without progress, narrow scope and pick the smallest concrete next step.
   - If you've been re-running tests, read the failure carefully and fix the root cause rather than the symptom.

### Phase 3 — Ultrawork Oracle gate (ONLY when `--ultrawork`)

After you emit `<promise>DONE</promise>` in ultrawork mode, do NOT consider the loop finished. You MUST invoke `omo-oracle` to verify:

```
Task(
  subagent_type="omo-oracle",
  prompt="""
Verify the work for the following task. Return your verdict on the last line as either `VERDICT: GO` (work is complete and correct) or `VERDICT: NO-GO` (work is incomplete, incorrect, or has issues — list them).

Task: <original task description>

Context of what was done across all iterations (paste the iteration log from .omo/ralph-loop.local.md and a brief summary of the final state of the changed files):
<paste>
"""
)
```

When the Oracle returns:

- **`VERDICT: GO`** → terminate the loop. Update state to `Status: COMPLETED`. Stop.
- **`VERDICT: NO-GO`** (or anything that isn't a clean `VERDICT: GO`) → drop the promise, address every issue Oracle raised, and iterate again from Phase 2. Append a log line: `Iter N+1: oracle NO-GO — <summary of issues>, resuming work`.

Oracle may be invoked multiple times across iterations. Each invocation is independent — don't assume prior verdicts carry over.

### Phase 4 — Exit conditions

Stop the loop on ANY of these conditions:

1. **Verified completion** — agent emitted the promise tag; in ultrawork mode, Oracle returned `VERDICT: GO`. Update `Status: COMPLETED`.
2. **Max iterations reached** — stop and report the partial state. Update `Status: COMPLETED` only if the work is genuinely usable; otherwise leave as `RUNNING` and tell the user to either re-run with more iterations or accept the partial state.
3. **Cancel detected** — `Status: CANCELED` appeared in the state file mid-run. Stop immediately.

In every exit case, end your response with a short final summary:

```
Ralph Loop ended.
Status: <COMPLETED | CANCELED | partial — max iterations>
Iterations used: <N> / <max>
State file: .omo/ralph-loop.local.md
```

## CANCEL

The user can cancel a running loop in two ways:

1. **Edit the state file**: open `.omo/ralph-loop.local.md` and set `## Status` to `CANCELED`. Your next iteration's Phase 2 step 1 will detect it and stop.
2. **Interrupt the session**: stop the Claude Code session. The state file remains; a future `/omo-ralph-loop "<same task>" --strategy=continue` resumes from where the iteration log left off. (`--strategy=reset` discards the log and starts over.)

There is no separate `/cancel-ralph` skill in this port — the state file IS the cancel mechanism. This is intentional: a file edit works whether the loop is mid-iteration, between sessions, or paired with `/loop`.

## RULES

- **Focus on completing the task fully, not partially.** Don't emit the promise just because you're tired; emit it because the work is done.
- **Each iteration must make meaningful progress.** If an iteration is a no-op, log that and try a different approach next iteration.
- **Use TODO/task discipline.** Register sub-steps via `TaskCreate` / `TaskUpdate` as you discover them.
- **Don't treat `DONE` as final in ultrawork mode** — Oracle has veto power.
- **Don't fight Oracle.** If Oracle says NO-GO, address the issue. Don't argue. If Oracle is wrong on a specific point, push back ONCE with evidence in the next iteration's Oracle call.
- **Don't auto-resurrect a `CANCELED` loop.** If the user canceled, they canceled. Require explicit `--strategy=reset`.

## ANTI-PATTERNS

| Anti-pattern | Why it's wrong |
|---|---|
| Emitting `<promise>DONE</promise>` before the work is actually done | Defeats the entire point of the loop |
| Skipping state file updates between iterations | No durable trace — pairing with `/loop` breaks |
| Running ultrawork mode without invoking `omo-oracle` after the promise | Violates the verified-completion contract |
| Spawning a second `omo-ralph-loop` invocation inside an iteration | Infinite recursion; if you need sub-tasks use `Task(subagent_type="omo-worker-*", ...)` instead |
| Using `git checkout`-style destructive recovery without saving state first | Loses iteration history |
| Ignoring `Status: CANCELED` and continuing the loop | User cancel is non-negotiable |
| Padding iterations with no-op log lines just to reach a "looks busy" count | The iteration log is for real outcomes only |
| Pre-populating all N max-iterations as TaskCreate items | Add iterations to the task list as you go, not upfront |

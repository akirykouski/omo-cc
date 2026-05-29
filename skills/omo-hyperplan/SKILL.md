---
name: omo-hyperplan
description: Adversarial multi-agent planning. 5 hostile critics attack a planning request from orthogonal angles across 2-3 rounds, then mandatorily hand the surviving insight bundle to omo-prometheus for executable plan formalization. Use for high-stakes architecture decisions, complex refactors, or anytime you want a plan that's been beaten on. Triggers, hyperplan, hpp, adversarial plan, hostile review of plan, cross-critique plan, /omo-hyperplan
argument-hint: '"<planning request>" [--rounds=2|3]'
allowed-tools: Task Bash Read Write Edit Glob Grep WebFetch WebSearch AskUserQuestion TaskCreate TaskUpdate TaskList
model: opus
effort: xhigh
---

# HYPERPLAN — Adversarial Multi-Agent Planning

> **MANDATORY**: First action when this skill loads — say `HYPERPLAN MODE ENABLED!` on its own line, exactly once, so the user knows orchestration started. No extras, no preamble before that line.

## WHAT THIS IS

You (the orchestrator) become the **Lead** of a 5-member adversarial team. The 5 members are **maximally hostile** to each other — they attack each other's findings ruthlessly. You then synthesize only the **defensible insights** that survived the attacks into an insight bundle and hand that bundle to `omo-prometheus` for executable plan formalization.

This is not consensus building. This is intellectual combat. Weakness gets exposed. Lazy thinking gets eviscerated. Only what survives the gauntlet makes it into the plan.

**Critical separation of duties**: You (the Lead) **distill** the surviving insights in Phase 5, but you DO NOT write the work plan. The work plan is produced by `omo-prometheus` in Phase 6 — this handoff is **mandatory**, not optional. Hyperplan = adversarial distillation + dedicated planner formalization. Skipping the handoff turns it back into vanilla orchestration.

## ROUND COUNT (`--rounds=2|3`)

With Opus 4.7, hyperplan ran 3 rounds (independent → cross-attack → defend/refine/concede) because critics rubber-stamped each other at depth. With **Opus 4.8** the rubber-stamping rate is meaningfully lower (per release notes: "4× less likely to allow flaws unremarked"), so **2 rounds is the new default** — independent analysis + cross-attack. Round 3 (defend/refine/concede) becomes opt-in via `--rounds=3` when stakes are high enough to want full adversarial settlement.

- `--rounds=2` (default on 4.8): Phase 2 (independent) → Phase 3 (cross-attack) → skip Phase 4 → Phase 5 (distill).
- `--rounds=3` (default on 4.7): Phase 2 → Phase 3 → Phase 4 (defend/refine/concede) → Phase 5.
- If the user didn't pass `--rounds`, use 2 with a note explaining why ("4.8 makes round 3 marginal; pass `--rounds=3` for high-stakes plans").

## PAIRING WITH DYNAMIC WORKFLOWS

If Dynamic Workflows are enabled (Claude Code 2.1.154+, Pro/Max/Team/Enterprise research preview), hyperplan benefits massively from running **as a workflow**:

- Include the word `workflow` in the user request, e.g. `/omo-hyperplan "<question>" — run as workflow`. The 5-critic fan-out + convergence loop become native JS-script execution instead of one-message-per-round Task calls.
- The opinion layer (which 5 critics, hostile framing, mandatory Prometheus handoff in Phase 6, no-Lead-writes-plan separation) stays — Claude bakes it into the workflow script it writes.
- After a successful run, `/workflows` → select → press `s` → save as `~/.claude/workflows/omo-hyperplan-dw.js`. Subsequent runs invoke the saved JS directly.

The 16-concurrent / 1000-total limits of DW are far below what hyperplan needs (5 critics × 2-3 rounds = 10-15 calls), so the caps don't bind here.

## THE 5 ADVERSARIAL MEMBERS

The team is exactly 5 hostile critics. Each is a Claude Code subagent (Opus). Use only these names:

| Member | Subagent | Attack Vector | Default Position |
|---|---|---|---|
| Pragmatist Skeptic | `omo-skeptic` | Over-engineering, scope creep, premature abstraction | REJECT, demand simpler |
| Integration Tester | `omo-validator` | Incompleteness, blast radius, untested edge cases | Assume something was missed |
| Autonomous Researcher | `omo-researcher` | Vibes-based claims, missing citations | Assume they are guessing |
| Architect Strategist | `omo-architect` | Leaky abstractions, hidden coupling, technical debt | Assume the architecture is suboptimal |
| Creative Challenger | `omo-creative` | Orthodox first-thought-best-thought | Assume they took the obvious path |

Important: hostility IS the mechanism. Do not soften the critics' prompts when relaying tasks to them. The aggressive framing is what extracts weaknesses.

## EXECUTION WORKFLOW (8 phases)

### Phase 0 — Acknowledge

1. First line of your response, exactly: `HYPERPLAN MODE ENABLED!`
2. In 2–3 sentences, mirror the planning request back to the user so all members start with the same scope.
3. Use `TaskCreate` to register a checklist for the remaining phases. Include the Phase 6 handoff to `omo-prometheus` as an explicit non-skippable item.

### Phase 1 — Roster setup and optional context gathering

There is no `team_create` in Claude Code. The roster is fixed (the 5 critics above). What you do here:

1. Restate which 5 critics will be used and their attack angles, so the user understands the lineup.
2. If — and only if — the request is under-specified or you need codebase context the critics will demand, **fire context gatherers in parallel BEFORE Round 1**. In ONE message, spawn up to 5 parallel `Task` calls picking from:
   - `Task(subagent_type="omo-explore", prompt="<targeted search>")` for in-repo code paths.
   - `Task(subagent_type="omo-librarian", prompt="<library/docs question>")` for external library or framework facts.
3. Wait for those returns, summarize the gathered context in 5–10 lines max, and carry that summary into Phase 2's prompts.

Do not over-explore here. Goal is "enough common context that critics can attack the request meaningfully" — not full discovery. The critics themselves may also cite missing-evidence; that is expected.

### Phase 2 — Round 1: Independent analysis (parallel fan-out)

In **ONE message**, spawn 5 `Task` calls in parallel — one per critic. Each gets the SAME context block. Do not vary the request per critic — they vary themselves via their adversarial role.

For each of the 5 critics, dispatch:

```
Task(
  subagent_type: "omo-<critic>",
  prompt: <<PROMPT
<hyperplan-round-1-task>
You are participating in HYPERPLAN — adversarial multi-agent planning. This is ROUND 1: Independent Analysis.

Original user request:
<user-request>
[verbatim user planning request]
</user-request>

Gathered context (from omo-explore / omo-librarian in Phase 1, may be empty):
<context>
[5-10 line summary, or "(none gathered)"]
</context>

YOUR TASK (Round 1):
Apply your adversarial role to this request. Produce 3-7 numbered findings.
- Each finding ≤3 sentences.
- Each finding SPECIFIC (cite file:line, name an edge case, propose a concrete alternative, or call out missing evidence — per your role).
- DO NOT critique anyone else yet (no peer findings to critique — this is Round 1).
- DO NOT propose a synthesized plan.

Output ONLY your numbered findings under a `# Round 1 Findings — omo-<critic>` heading.
</hyperplan-round-1-task>
PROMPT
)
```

Where `<critic>` is one of `skeptic`, `validator`, `researcher`, `architect`, `creative`.

**Wait for all 5 returns before continuing.** Parallel Tasks in one message return concurrently; the harness will surface each result.

### Phase 3 — Round 2: Cross-attack (parallel fan-out)

Aggregate the 5 Round 1 findings into a single bundle, labeled by critic. Keep it concise — if combined size exceeds ~32KB, compress each finding to one sentence while preserving its spirit.

```
=== Round 1 Findings Bundle ===
[omo-skeptic]
1. ...
2. ...

[omo-validator]
1. ...

[omo-researcher]
1. ...

[omo-architect]
1. ...

[omo-creative]
1. ...
=== End ===
```

Then in **ONE message**, spawn 5 `Task` calls in parallel. Each critic receives the SAME aggregated bundle, plus the round-2 instruction. Each is told to attack THE OTHER FOUR, not their own findings.

```
Task(
  subagent_type: "omo-<critic>",
  prompt: <<PROMPT
<hyperplan-round-2-task>
You are in ROUND 2: Cross-Attack of HYPERPLAN.

Below are the Round 1 findings from all 5 members of this adversarial team (yours included, for reference only).

[insert Round 1 Findings Bundle verbatim]

YOUR TASK (Round 2):
ATTACK the OTHER 4 members' findings ruthlessly from your adversarial role. Do NOT critique your own findings.

For each of the 4 other members, for each of their findings:
- [other-member] Finding #N: [their claim]
  ATTACK: [your specific attack — ≤3 sentences. Concrete. Cite file:line / edge case / alternative / evidence per your role.]

OR if a finding actually survives scrutiny:
- [other-member] Finding #N: [their claim]
  STANDS — [why it holds up].

Be HOSTILE. Be RELENTLESS. No collegial hedging. No softening. The skill explicitly requires aggression — pulling punches breaks the mechanism. If a finding is weak, EVISCERATE it.

Output ONLY your numbered cross-attacks under a `# Round 2 Cross-Attacks — omo-<critic>` heading.
</hyperplan-round-2-task>
PROMPT
)
```

**Wait for all 5 cross-attack returns before continuing.**

### Phase 4 — Round 3: Defend, refine, or concede (parallel fan-out) — OPTIONAL on `--rounds=2`

**If `--rounds=2` (default on Opus 4.8): SKIP this phase entirely. Go directly to Phase 5.** Distillation in Phase 5 will treat Round 2 attacks as authoritative — a critic whose finding was attacked and didn't get to defend is treated as conceded. This is fine for 4.8 because the rubber-stamping rate at depth is meaningfully lower than 4.7.

**If `--rounds=3` (default on Opus 4.7, opt-in on 4.8): run this phase.**

Now reorganize Round 2 returns BY ORIGINAL FINDING: for each Round 1 finding produced by critic X, collect every attack from critics Y, Z, … that targeted it. Send each critic ONLY the attacks that landed on their OWN findings (don't dump the whole bundle — they only need to defend their own work).

```
Task(
  subagent_type: "omo-<critic>",
  prompt: <<PROMPT
<hyperplan-round-3-task>
You are in ROUND 3: Defend, Refine, or Concede.

Your Round 1 findings were attacked by your peers in Round 2. Here are the attacks landed on YOU:

[omo-<critic>] Finding #1: [your original claim]
  - [attacker-name] attacked: [attack]
  - [attacker-name] attacked: [attack]

[omo-<critic>] Finding #2: [your original claim]
  - [attacker-name] attacked: [attack]

...

YOUR TASK (Round 3):
For each of YOUR findings that was attacked, choose exactly ONE of:
- DEFEND: rebut the attack with concrete evidence/reasoning. State why the attack failed.
- REFINE: acknowledge the attack landed partially, restate your finding in a stronger, more precise form.
- CONCEDE: acknowledge the attack defeated this finding. State plainly what survives (often: nothing).

Be HONEST. Pride is the enemy here. If you were wrong, concede — that is a successful round, not a failure. Only defensible positions survive into the plan.

For findings that received zero attacks, list them under "UNCONTESTED" — they survive automatically.

Output format per finding:
- Finding #N: DEFEND | REFINE | CONCEDE — [≤3 sentence explanation]

Output under a `# Round 3 Verdicts — omo-<critic>` heading.
</hyperplan-round-3-task>
PROMPT
)
```

**Wait for all 5 Round 3 returns before continuing.**

### Phase 5 — Insight distillation (Lead's job, NOT the critics')

Now YOU (the orchestrator) distill the surviving insights. You DO NOT write the work plan. You produce a structured **insight bundle** that becomes input to `omo-prometheus` in Phase 6.

1. **Filter to defensible insights only.** Keep findings that:
   - Were uncontested in Round 2, OR
   - Were successfully DEFENDED in Round 3 with concrete evidence, OR
   - Were REFINED in Round 3 into a stronger form.
   Drop everything CONCEDED.

2. **Categorize the survivors into 4 buckets.** This is the non-negotiable bundle shape:

```markdown
# Hyperplan Insight Bundle — [task title]

## Original User Request
[restate the user's planning request verbatim]

## Hard Constraints (non-negotiables surviving all 3 rounds)
- [constraint] — surfaced by [omo-<critic>] in Round 1; defended against [attackers] in Round 3; why it must hold.

## Decisions (judgment calls with rationale)
- [decision] — proposed by [omo-<critic>]; attacked by [others] who argued [X]; defended/refined to [final form]; rationale = [trail].

## Risks & Mitigations
- Risk: [risk] (surfaced by [omo-<critic>]) — Mitigation: [explicit mitigation tied to a specific finding, must be plan-executable].

## Open Questions (still genuinely contested)
- [question] — [the contention] — [why Round 3 could not resolve it]. SURFACE TO USER AS A GATE in the plan.

## Adversarial Provenance
- omo-skeptic findings that survived: <count>
- omo-validator findings that survived: <count>
- omo-researcher findings that survived: <count>
- omo-architect findings that survived: <count>
- omo-creative findings that survived: <count>
- Total Round 1 findings conceded/destroyed: <count>
```

3. Tell the user in one short sentence: "Adversarial distillation complete — N findings survived, M were destroyed. Handing the bundle to omo-prometheus for executable plan formalization."

4. **Do NOT** present the bundle as the final plan. It is INPUT to Phase 6, not the deliverable.

### Phase 6 — MANDATORY plan handoff to omo-prometheus

The Lead does NOT write the plan in hyperplan. The plan is owned by `omo-prometheus`, the dedicated planner. This separation is by contract and non-negotiable.

In a single `Task` call (foreground; you wait for it), dispatch:

```
Task(
  subagent_type: "omo-prometheus",
  prompt: <<PROMPT
<hyperplan-handoff>
The following insight bundle survived an adversarial 5-member cross-critique debate (omo-skeptic / omo-validator / omo-researcher / omo-architect / omo-creative) across 3 rounds. Every claim here was either uncontested OR defended/refined under attack — conceded findings were already filtered out.

Your task: produce an EXECUTABLE work plan from these insights. You do NOT need to re-explore the codebase or re-derive the constraints — they are already battle-tested. Your value is plan structure, sequencing, dependency analysis, parallelization opportunities, and explicit verification criteria per task.

Hard rules for your plan:
- Every Hard Constraint MUST be respected by the plan.
- Every Risk MUST have its Mitigation woven into the relevant task.
- Every Open Question MUST surface as a user-input gate BEFORE the dependent tasks can start.
- Every task MUST have explicit success criteria.

[paste the full Insight Bundle from Phase 5 here verbatim]

Original user planning request (for reference):
<user-request>
[verbatim user planning request]
</user-request>
</hyperplan-handoff>
PROMPT
)
```

If `omo-prometheus` returns clarifying interview questions instead of a plan, **forward them to the user without modification**. The planner is allowed to interview before committing — that is healthy planning behavior, not a failure mode.

When `omo-prometheus` returns a plan, present it **verbatim** to the user, prefixed with one provenance line:

```
*Plan generated by omo-prometheus from a hyperplan adversarial-distilled insight bundle (5 critics × 3 rounds). Run: <ISO-8601 timestamp>.*

[omo-prometheus output verbatim]
```

Do NOT edit, summarize, or "polish" the plan. The contract is verbatim.

### Phase 7 — Cleanup and transcript artifact

1. Compute the run timestamp: `RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)` (via `Bash`).
2. Create the transcript directory: `mkdir -p .omo/hyperplan/${RUN_TS}/`.
3. Write `.omo/hyperplan/${RUN_TS}/transcript.md` containing, in order:
   - The original user request.
   - Phase 1 gathered context summary (if any).
   - Round 1 findings (all 5 critics, verbatim returns).
   - Round 2 cross-attacks (all 5 critics, verbatim returns).
   - Round 3 verdicts (all 5 critics, verbatim returns).
   - The Phase 5 distilled insight bundle.
   - A link line: `Plan: see omo-prometheus output in conversation, run ${RUN_TS}`.
4. Confirm in one line to the user: `Transcript saved to .omo/hyperplan/${RUN_TS}/transcript.md.`

This transcript is how we recover when something looks wrong post-hoc — auditability is part of the deliverable.

## ANTI-PATTERNS — DO NOT DO THESE

| # | Anti-pattern | Why it fails |
|---|---|---|
| 1 | Skipping rounds to "save time" | The adversarial filter IS the value. Skipping rounds = vanilla planning with extra steps. |
| 2 | Soft-pedaling critic prompts ("please be respectful") | Hostility is the mechanism. Politeness defeats the skill. |
| 3 | Distilling before Round 3 completes | Premature synthesis preserves weak findings that would have died on cross-fire. |
| 4 | Including CONCEDED findings in the insight bundle | Conceded = defeated. Bundle must contain ONLY survivors. |
| 5 | **Lead writing the plan in Phase 5 instead of handing off in Phase 6** | **The handoff is the contract. Lead-written plans skip the planner's value-add (sequencing, dependencies, gates) and collapse hyperplan back into vanilla orchestration.** |
| 6 | Pre-writing tasks before dispatching to omo-prometheus | Anchors the planner to your draft, undermines independent judgment. Dispatch raw insights, let the planner structure. |
| 7 | Spawning critics sequentially instead of in one parallel message | 5x latency for no quality gain. Always batch all 5 Task calls into one orchestrator message per round. |
| 8 | Editing/summarizing/"polishing" omo-prometheus's plan before presenting | Plan is presented verbatim. Provenance line is the only addition. |
| 9 | Calling other critics directly (`omo-skeptic`, etc.) outside hyperplan | These agents only make sense inside the 3-round protocol. Direct invocation produces hostile output with no orchestration to filter it. |
| 10 | Skipping Phase 7 transcript | Without the transcript, post-hoc "why did the plan say X?" debugging is impossible. Always save. |

## NOTES FOR THE LEAD (YOU)

- Each round = exactly ONE orchestrator message with 5 parallel `Task` calls. Three rounds = three orchestrator messages.
- Critics do NOT see each other directly. You are the information broker. The bundles you forward in Rounds 2 and 3 are the entire context they have.
- Keep bundles concise — ≤32KB per critic prompt. If aggregated findings exceed this, compress each finding to one sentence while preserving its spirit.
- The Phase 6 `omo-prometheus` handoff runs **foreground** (you wait for it). Only after the plan is presented should you do Phase 7 cleanup.
- If `omo-prometheus` needs additional codebase context the bundle didn't cover, you may fire `omo-explore` or `omo-librarian` to fetch it, then re-dispatch `omo-prometheus` with the augmented bundle. Do not skip the planner — augment the input.
- The 5 critics are intentionally hostile to each other. They are NOT hostile to you. They report back; you orchestrate.

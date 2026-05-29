---
name: omo-security-research
description: Team Mode security audit with 3 vulnerability hunters and 2 PoC engineers. Performs surface-mapping, auth/data/injection analysis, runtime/supply-chain analysis, then independently builds and falsifies PoCs. Severity-calibrated by actual exploitability. Triggers: security audit, pen test, vulnerability hunt, exploitability audit, security review, pre-release security check, threat model validation, /omo-security-research
argument-hint: '"<scope: paths or feature to audit>"'
allowed-tools: Task Bash Read Write Edit Glob Grep WebFetch WebSearch AskUserQuestion TaskCreate TaskUpdate TaskList
model: opus
effort: xhigh
---

# Security Research — Team-Mode Vulnerability Audit

Run a parallel security audit that separates **real exploitability** from generic concern. The team has 3 vulnerability hunters and 2 PoC engineers, all running as parallel Claude Code subagents (no team-mode runtime — fan-out via parallel `Task` calls).

**MANDATORY first line of your response**: `SECURITY RESEARCH MODE ENGAGED.` exactly once.

---

## Pairing with Dynamic Workflows

If Dynamic Workflows are enabled (Claude Code 2.1.154+, research preview), security-research is a strong workflow candidate — the 3-hunter / 2-PoC fan-out + cross-check phase + falsification round map cleanly onto a JS orchestration script:

- Include the word `workflow` in the user request: `/omo-security-research "<scope>" — run as workflow`. The runtime spawns hunters and PoC engineers in parallel, holds intermediate findings in script state (no Claude-context pollution), and surfaces only the final report.
- After a successful run, `/workflows` → press `s` to save as `~/.claude/workflows/omo-security-research-dw.js`. Re-run on every release candidate.
- The opinion layer survives intact in the saved script: "no severity without an attack path", "never run destructive exploits", CWE/OWASP/CVSS standard references, Engineer B's falsification mandate.

DW concurrency caps (16 concurrent / 1000 total) don't bind here — security-research runs at most ~10 agents.

---

## Hard Preconditions

Before starting, verify:

1. You have a concrete target: repository path, diff range, PR, release candidate, path list, or threat surface. If the user provided none, default to: the current repository, current branch, diff against the merge base of `production` (or `main`/`master`). If there is no diff, audit the security-sensitive surfaces in the working tree.
2. You are in the main session (not invoked from within another subagent that would re-recurse).
3. You can write under `.omo/security-research/` in the project's working directory.

If the scope is ambiguous, use `AskUserQuestion` to clarify before Phase 1. Max 4 questions. Examples: "Audit the whole repo, or a specific path?", "Include dependency/supply-chain check?", "Time budget (quick triage / standard / deep)?", "Any directories or files to explicitly exclude?".

---

## Severity Standard

Use these references as the scoring frame — cite them in every finding:

- **CWE** for root-cause weakness classification: https://cwe.mitre.org/
- **OWASP WSTG** for test methodology: https://owasp.org/www-project-web-security-testing-guide/
- **OWASP ASVS** for control verification: https://owasp.org/www-project-application-security-verification-standard/
- **CVSS v4.0** for exploitability and impact scoring: https://www.first.org/cvss/v4.0/specification-document

**Rules — non-negotiable:**

- **No severity without an attack path.**
- **No critical/high finding without concrete exploit preconditions AND concrete impact.**
- Keep CWE category SEPARATE from severity. A finding can be CWE-89 (SQL Injection) and still be Low if no attacker can reach it.
- Prefer a small, reproducible PoC over theoretical language.
- **Never run destructive exploits against real services or third-party systems.** Use local fixtures, toy payloads, dry runs, or static proof when real execution would be unsafe.
- Do not claim CVSS precision unless you actually scored the metrics. If you didn't score, say "approximate" and show the vector.

---

## Team Roster

5 parallel Claude Code subagents. They are NOT called in a `team_create` runtime — Claude Code has no such tool. Instead, they are spawned via parallel `Task` calls in a single message (see Phase 1 / Phase 2 below).

| Agent | Subagent type | Role |
|---|---|---|
| Surface mapper | `omo-surface-hunter` | Map entry points, trust boundaries, attacker-controlled inputs, data sinks, privilege transitions, sensitive assets |
| Auth/data hunter | `omo-auth-data-hunter` | Hunt auth, authorization, tenant/data isolation, injection, SSRF, credential exposure, confused-deputy flaws |
| Runtime/supply hunter | `omo-runtime-supply-hunter` | Hunt filesystem, subprocess, archive, dependency, hook, MCP, config, env-var risks |
| PoC engineer A | `omo-poc-engineer-a` | Build minimal safe PoCs for candidate findings |
| PoC engineer B | `omo-poc-engineer-b` | Independently reproduce and **falsify** candidate findings |

---

## Workflow — 5 Phases

### Phase 0 — Scope and Baseline

Acknowledge with the first-line `SECURITY RESEARCH MODE ENGAGED.` (already done above), then:

1. **Confirm scope**: paths / files / feature / diff range. Echo it back to the user before fanning out.
2. **Baseline the project**: language, framework, auth model, deployment surface, secret-handling pattern, existing security tests. Use `Bash`, `Glob`, `Grep`, `Read`. If you need deeper context, spawn `omo-explore` via `Task` in parallel.
3. **Capture commit context** via `Bash`:
   ```bash
   git rev-parse HEAD
   git rev-parse --abbrev-ref HEAD
   git diff --name-only $(git merge-base HEAD production 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)..HEAD
   ```
4. **Create the artifact dir** for this audit:
   ```bash
   TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
   mkdir -p ".omo/security-research/$TS/poc-a" ".omo/security-research/$TS/poc-b"
   echo "$TS" > .omo/security-research/LATEST
   ```
   Record the timestamp; all 5 subagents receive this artifact path in their prompts.
5. **Collect user-stated constraints**: "no network calls", "no destructive tests", "do not touch X", time budget. Pass these to every subagent.

Use `rg`, `git diff`, `git log`, existing tests, and `Grep` before assigning work. Do not skip the baseline — hunters need it.

---

### Phase 1 — Independent Hunter Pass (parallel)

In **ONE message**, fire 3 `Task` calls in parallel. Each hunter receives an identical context bundle:

```
Audit target:
{scope summary from Phase 0}

Baseline:
{language, framework, auth model, deployment surface}

Commit:
{SHA, branch, changed files}

Constraints:
{user-stated constraints, e.g. "no network calls"}

Artifact dir:
.omo/security-research/{TS}/

Your role:
{role-specific brief — see below}

Task:
Find candidate vulnerabilities in your assigned role. For each candidate include:
- title
- affected file/function (absolute path + symbol)
- attacker capability (what does the attacker control?)
- attack path (step-by-step reachability)
- impact (what does the attacker gain?)
- CWE candidate (best-fit ID)
- exact evidence (file path + line range + code snippet)
- safe verification idea (how PoC engineers could prove it without running destructive ops)

Reject generic hardening advice. Return ONLY candidates with a plausible attack path.
DO NOT assign severity yet — that happens in Phase 3 after PoC validation.
Write your findings to `.omo/security-research/{TS}/candidates-{your-name}.md`.
Output: a structured list back to the orchestrator with all candidates.
```

The three Task calls (in ONE message — they must fan out, not run sequentially):

- `Task(subagent_type="omo-surface-hunter", description="Map attack surface", prompt="<context + 'Your role: map entry points and trust boundaries'>")`
- `Task(subagent_type="omo-auth-data-hunter", description="Hunt auth/data flaws", prompt="<context + 'Your role: auth, authz, injection, SSRF, credential exposure'>")`
- `Task(subagent_type="omo-runtime-supply-hunter", description="Hunt runtime/supply risks", prompt="<context + 'Your role: filesystem, subprocess, archives, deps, hooks, MCP, config, env'>")`

Wait for all three to return. Collect their candidate lists.

---

### Phase 2 — PoC Pass (parallel)

Deduplicate hunter candidates. Group by surface (auth, injection, ssrf, filesystem, supply-chain, etc.). Both engineers get **the same** candidate list — independent reproduction is the point.

In **ONE message**, fire 2 `Task` calls in parallel:

- `Task(subagent_type="omo-poc-engineer-a", description="Build PoCs", prompt="<all candidates + 'Prove or disprove each. Write PoCs to .omo/security-research/{TS}/poc-a/'>")`
- `Task(subagent_type="omo-poc-engineer-b", description="Falsify PoCs", prompt="<all candidates + 'Independently reproduce. Try to FALSIFY. Write to .omo/security-research/{TS}/poc-b/'>")`

Each PoC engineer must return:

- For each candidate: **Reproduced** / **Falsified** / **Unsafe-to-run** (with explanation).
- Exact commands, fixtures, or static proof.
- Observed output OR reason it fails.
- Recommended severity using exploitability + impact (CVSS vector, not just a label).
- Downgrade rationale for anything not reproduced.

If a PoC would be unsafe to run for real (e.g., would write to a production DB, would exfiltrate data, would hit a third-party API), the engineer designs a **safe equivalent** — local fixture, dry-run, or static proof — and explicitly notes the limit.

---

### Phase 3 — Cross-Check (orchestrator-side)

You (the orchestrator) read both PoC engineers' returns and reconcile. **Do not** spawn the hunters again — the cross-check is yours to do.

For each candidate:

- **Both engineers reproduced** → finding survives. Assign severity per CVSS v4.0 using their vectors.
- **Only one reproduced** → finding survives at LOWER severity. Add a note: "Reproduced by A only; B noted {reason}. Treating as {Medium/Low}."
- **Both falsified** → drop the finding. Add to "Downgraded / rejected candidates" with reason.
- **Disagreement on impact** → adjudicate by taking the LOWER claim unless there is concrete evidence for the higher one.
- **Unsafe to run** → static proof only; severity capped at Medium unless the static proof is airtight.

Write the adjudication notes to `.omo/security-research/{TS}/cross-check.md`.

---

### Phase 4 — Final Report

Write the final report to `.omo/security-research/{TS}/report.md`, then present it verbatim to the user.

**Report template** (use exactly this structure):

```markdown
# Security Research Report — <YYYY-MM-DD>

**Scope**: <files/paths/feature>
**Verdict**: PASS | PASS WITH FINDINGS | BLOCK
**Commit**: <SHA on branch <branch>>
**Audit dir**: `.omo/security-research/<TS>/`

## Verdict rationale
<1-3 sentences explaining the verdict>

## Findings
| # | Severity | Title | CWE | Exploitability | Impact | PoC | Suggested Fix |
|---|----------|-------|-----|----------------|--------|-----|---------------|
| 1 | High     | ...   | CWE-89 | Network, unauthenticated | Database read | `.omo/.../poc-a/sql-injection.md` | Parameterize the query in <file:line> |

## Finding details
### Finding 1 — <title>
- **Evidence**: <file:line range>
- **Attack path**: <step-by-step>
- **PoC reproduction**:
  - Engineer A: `.omo/security-research/<TS>/poc-a/<name>.md`
  - Engineer B: `.omo/security-research/<TS>/poc-b/<name>.md`
- **Severity rationale**: CVSS v4.0 vector: <vector string>. <Reasoning.>
- **Minimal fix**: <smallest-possible code change>
- **Regression test**: <test idea that would prevent recurrence>

## Downgraded / rejected candidates
| Candidate | Reason |
|-----------|--------|
| ... | Falsified by both engineers — no working path |

## Residual risk
<2-4 sentences: what was NOT tested and why. Be honest about scope limits.>

## Provenance
- Hunters: omo-surface-hunter, omo-auth-data-hunter, omo-runtime-supply-hunter
- PoC engineers: omo-poc-engineer-a, omo-poc-engineer-b
- Standards consulted: CWE, OWASP WSTG, OWASP ASVS, CVSS v4.0
- Artifact dir: `.omo/security-research/<TS>/`
```

### Verdict rules

- **PASS** — zero findings survived PoC.
- **PASS WITH FINDINGS** — one or more findings survived, but none are critical/high OR all critical/high have an acceptable mitigation already in place AND the user can ship after fixing.
- **BLOCK** — at least one surviving critical/high finding without mitigation, OR a hard supply-chain compromise found, OR cannot complete the audit (state why).

After writing the report, **present it verbatim** to the user. End the skill — do not start fixing anything yourself.

---

## Output Rules

- **Lead with the verdict** in your final user-facing message.
- Do not bury blocking issues.
- Do not report speculative findings as vulnerabilities — only what survived Phase 3.
- Do not claim CVSS precision unless you actually scored the metrics. Show the vector string.
- Include exact file paths (absolute) and exact commands for every surviving finding.
- If no findings survive PoC, say that plainly, then list residual risk so the user knows what was NOT proven.

---

## Anti-patterns — never do these

| Anti-pattern | Why it's wrong |
|---|---|
| Assigning Critical/High without a working PoC | The whole point of this skill is exploitability-calibrated severity |
| Running PoCs against production / third-party services | We use local fixtures and dry-runs only |
| Skipping cross-check because both PoC engineers said similar things | Cross-check catches false-positive convergence |
| Letting hunters assign severity in Phase 1 | They produce candidates, not findings. Severity comes after PoC |
| Writing fixes yourself before the report is delivered | This skill audits; it does not patch. Hand off to the user |
| Re-using the same `omo-poc-engineer-a` and `-b` outputs as if they were a single source | The whole reason there are two is independent reproduction |
| Forgetting to cite CWE | CWE is the language reviewers use; "auth bug" is not |
| Network calls that are not strictly read-only research (CWE lookups, vendor advisories) | Hunters and PoC engineers must default to local; only research-style WebFetch is okay |
| Editing project source files | This skill is read-only relative to the codebase. Subagents must NOT Write/Edit project sources |

---

## Failure Recovery

- **A hunter returns nothing useful** → re-prompt with sharper scope ("focus on X auth surface specifically"). Do not just drop their input.
- **Both PoC engineers say "unsafe to run"** → accept static proof, but cap severity at Medium and call this out in the report.
- **A finding is too large to PoC in one pass** → split into sub-findings and PoC each. Note the split in the report.
- **`omo-explore` or other helpers fail** → fall back to direct `Grep` / `Read` / `Bash`. Do not retry > 2 times.

---

## What the skill does NOT do

- It does not patch the code. It produces a report.
- It does not file tickets. The user decides what to do with the verdict.
- It does not run penetration tests against live services.
- It does not gate deploys — that is a CI concern, not a skill concern.
- It does not load other skills programmatically — it delegates to `omo-*` agents whose discipline is baked into their prompts.

End of skill.

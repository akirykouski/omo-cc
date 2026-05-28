# omo-cc — a Claude Code port of oh-my-openagent

`omo-cc` ports the load-bearing prompts and orchestration patterns from [`oh-my-openagent`](https://github.com/code-yeongyu/oh-my-openagent) (omo, formerly `oh-my-opencode`) to [Claude Code](https://claude.com/claude-code). Same discipline — mandatory plan-before-implementation, parallel-greedy fan-out, hostile adversarial planning, severity-calibrated security audits, per-task verification gates — running natively in Claude Code with no opencode dependency.

> **License (read before installing):** this is a derivative work distributed under the **Sustainable Use License v1.0** ([LICENSE](LICENSE)) — the same license as upstream. SUL-1.0 limits use to "internal business, non-commercial, or personal" purposes and forbids commercial redistribution. Not OSI-approved. See [NOTICE.md](NOTICE.md) for the full derivative-work disclosure and what changed from upstream.

## Install

```bash
git clone https://github.com/akirykouski/omo-cc.git
cd omo-cc
bash scripts/install.sh           # install into ~/.claude
bash scripts/install.sh --dry-run # preview without touching anything
bash scripts/install.sh --verbose # print every file as it's copied
```

The installer is idempotent. Any existing `omo-*` files under `~/.claude/skills/` and `~/.claude/agents/` are backed up to `~/.claude/backups/omo-cc-<timestamp>/` before being overwritten. Frontmatter is validated before any file is copied — if a single file fails validation, the install aborts.

To install into a custom prefix, set `CLAUDE_HOME=/custom/path` before running `install.sh`.

## Uninstall

```bash
bash scripts/uninstall.sh             # backs up to ~/.claude/backups/ then removes
bash scripts/uninstall.sh --dry-run   # preview
bash scripts/uninstall.sh --no-backup # remove without backing up
```

The uninstaller is safety-pinned to only touch files matching `omo-*`. It will never remove anything without the `omo-` prefix.

## Quickstart

After installing, from any Claude Code session:

```
/omo-ultrawork "fix the login bug"
```

That launches the full omo workflow:

1. Sisyphus (orchestrator) fans out parallel `omo-explore` / `omo-librarian` Tasks to gather context.
2. Mandatory handoff to `omo-prometheus` (planner) — interview mode if the request has ambiguity, plan-generation mode if it doesn't.
3. Prometheus writes a plan to `.omo/plans/<name>.md` with parallel-execution waves, per-task acceptance criteria, and QA scenarios.
4. Sisyphus executes waves in parallel via worker agents (`omo-worker-quick`, `-deep`, `-ultrabrain`, `-visual`, `-artistry`, `-default`).
5. Per-task verification: typecheck + read every changed file + hands-on QA for user-facing changes.
6. Final Verification Wave: 4 parallel reviewers (`omo-oracle`, `omo-worker-ultrabrain`, `omo-worker-default`, `omo-worker-deep`). All must approve.
7. Boulder closeout at `.omo/boulders/<ts>/summary.md`.

For lower-stakes work, you can call sub-skills directly:

```
/omo-hyperplan "should we migrate from Stripe to Paddle?"
/omo-security-research "audit supabase/functions/process-trade-in"
/omo-init-deep
/omo-remove-ai-slops --scope=branch
/omo-ralph-loop "rename foo to bar across all .ts files"
/omo-start-work my-plan-name --worktree ../my-worktree
```

## What ships

### Skills

| Skill | Purpose |
| --- | --- |
| `/omo-ultrawork` | Master orchestration mode. Plan-mandatory, fan-out-greedy, 4-reviewer Final Verification Wave. |
| `/omo-hyperplan` | Adversarial multi-agent planning. 5 hostile critics across 3 rounds, then mandatory handoff to Prometheus. |
| `/omo-security-research` | 3 vulnerability hunters + 2 PoC engineers. Severity-calibrated by actual exploitability. |
| `/omo-start-work` | Kick off work on a Prometheus-generated plan. Discovers `.omo/plans/`, resumes active boulder, optionally creates a git worktree. |
| `/omo-init-deep` | Hierarchical `CLAUDE.md` generator. Scores subdirs, fans out parallel writes. |
| `/omo-remove-ai-slops` | Detect and remove AI-generated comment slop, over-defensive code, spaghetti nesting from changed files. |
| `/omo-ralph-loop` | Self-referential dev loop. Pairs with Claude Code's `/loop` for autonomous pacing. |

### Agents

**Discipline triumvirate:**
| Agent | Role | Model |
| --- | --- | --- |
| `omo-sisyphus` | Master orchestrator. Plans, delegates, verifies, ships. | opus |
| `omo-hephaestus` | Autonomous deep worker. Explores, plans, executes, verifies — minimal supervision. | opus |
| `omo-prometheus` | Strategic interview-mode planner. Generates `.omo/plans/<name>.md` with parallel waves. | opus |

**Planning support:**
| Agent | Role | Model |
| --- | --- | --- |
| `omo-metis` | Pre-planning consultant. Surfaces ambiguity and AI-slop risks. | sonnet |
| `omo-momus` | Plan reviewer for High Accuracy mode. Approval-biased. | sonnet |

**Read-only research:**
| Agent | Role | Model |
| --- | --- | --- |
| `omo-oracle` | Strategic advisor with 3-tier responses + effort estimates. Used as verification gate inside Prometheus. | opus |
| `omo-librarian` | External library researcher with mandatory GitHub permalink citations. | sonnet |
| `omo-explore` | Codebase search specialist. Mandatory `<analysis>` + `<results>` block contract. | sonnet |

**Hyperplan critics** (only invoked by `/omo-hyperplan`):
| Agent | Attack angle |
| --- | --- |
| `omo-skeptic` | Over-engineering, scope creep, premature abstraction |
| `omo-validator` | Incompleteness, blast radius, untested edge cases |
| `omo-researcher` | Demands `file:line` evidence for every claim |
| `omo-architect` | Leaky abstractions, hidden coupling, separation of concerns |
| `omo-creative` | Orthodox thinking, "is this really the only way?" |

**Security hunters** (only invoked by `/omo-security-research`):
| Agent | Domain |
| --- | --- |
| `omo-surface-hunter` | Attack-surface mapping (entry points, trust boundaries, sinks) |
| `omo-auth-data-hunter` | AuthN/AuthZ, injection, SSRF, credential exposure |
| `omo-runtime-supply-hunter` | Filesystem, subprocess, archive, dependency, MCP, env-var risks |
| `omo-poc-engineer-a` | Builds minimal safe PoCs |
| `omo-poc-engineer-b` | Independently reproduces and falsifies |

**Worker agents** (Claude-Code equivalents of omo's `category=` routing):
| Agent | Use for | Model |
| --- | --- | --- |
| `omo-worker-quick` | Trivial tasks, single-file changes, typo fixes | haiku |
| `omo-worker-deep` | Hairy single-goal problems requiring deep research | opus |
| `omo-worker-ultrabrain` | Hard logic, architecture decisions, algorithms | opus |
| `omo-worker-visual` | Frontend, UI, UX, design-system work | sonnet |
| `omo-worker-artistry` | Creative, unconventional problem-solving | opus |
| `omo-worker-default` | Moderate-effort tasks that don't fit a specialized category | sonnet |

## Workspace state — the `.omo/` directory

Workflows persist state under `.omo/` in the current working directory:

- `.omo/plans/<name>.md` — Prometheus-generated plans
- `.omo/drafts/<name>.md` — Prometheus's working draft (deleted on plan complete)
- `.omo/notepads/<name>/{learnings,decisions,issues,problems}.md` — durable cross-task wisdom
- `.omo/boulders/<ts>/summary.md` — ultrawork closeout summaries
- `.omo/hyperplan/<ts>/transcript.md` — hyperplan 3-round debate transcripts
- `.omo/security-research/<ts>/{report.md,poc-a/,poc-b/}` — security audit artifacts
- `.omo/boulder.json` — active-plan state for `/omo-start-work`
- `.omo/ralph-loop.local.md` — ralph-loop iteration state
- `.omo/ai-slop-runs/<ts>/originals/` — pre-cleanup file backups for `/omo-remove-ai-slops`

Add `.omo/` to your project's `.gitignore` if you don't want plans/notes/boulders in version control. (Some teams check `.omo/plans/` in deliberately — it's up to you.)

## What doesn't port (vs. upstream omo)

omo runs in opencode and assumes a few things that don't exist in Claude Code. Where possible we degrade gracefully:

| omo feature | omo-cc behavior |
| --- | --- |
| **Hashline** (hash-anchored edit tool) | Claude Code's `Edit` tool already does anchored matching via `old_string`. Use `Edit`. |
| **LSP MCPs** (`lsp_symbols`, `lsp_diagnostics`, `lsp_rename`, etc.) | Fall back to `Grep` + `Read` for navigation; `Bash` running `npx tsc --noEmit` for diagnostics. Optional `mcp__lsp__*` MCP can be added by the user. |
| **AST-grep MCPs** | Fall back to `Grep`. `npx ast-grep` available via `Bash` if installed. |
| **Team Mode** (`team_create`, `team_send_message`, `team_*` family) | Simulated via parallel `Task` fan-out — multiple `Task` calls in one orchestrator message. Works for 3-round adversarial debates (hyperplan) and 5-shot audits (security-research). |
| **tmux visualization** | Skipped. Use `TaskList` output for progress visibility. |
| **Multi-model gateway** (Kimi, GLM, GPT-5.5, Gemini routing) | Claude-only. `omo-worker-*` agents map omo's category routing to Claude models (Haiku / Sonnet / Opus). |
| **Session continuity** (`task_id="ses_..."`) | Claude Code subagents don't preserve context across calls. The orchestrator concatenates prior-turn findings into the next prompt. Some token cost vs. upstream. |
| **Comment-checker hook** | The `omo-remove-ai-slops` skill ports the discipline as an on-demand slash command. Wiring it as a `PreToolUse`/`PostToolUse` hook is left as a manual user step (see `~/.claude/settings.json`). |
| **`/init-deep` LSP code-map section** | Replaced with `git log` heuristic (top 20 most-edited files in last 90 days). |

## Caveats

- **License**: upstream omo ships under [SUL-1.0](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/LICENSE.md) (Sisyphus Use License — non-standard, not OSI-approved). This port is a derivative work; the same license terms apply. Read upstream's LICENSE before commercial use.
- **Prompts are opinionated**. The omo design has strong preferences — mandatory Prometheus handoff, mandatory verification gates, hostile-critic rounds. If you don't want that discipline, don't invoke the skills. Each skill is a one-shot trigger; nothing runs automatically on its own.
- **Token cost is higher than vanilla Claude Code**. Parallel fan-out + 4-reviewer Final Verification Wave + 3-round adversarial debates spend tokens to buy quality. Use `/omo-ultrawork` for high-stakes work, not for "rename a variable".
- **`.omo/` paths are CWD-relative**. If you invoke a skill from inside a worktree, `.omo/` lives in that worktree.

## Triggering tips

Skills are invoked explicitly via slash commands. Triggers in each skill's `description:` line are used by Claude Code's skill-matching — natural language like "do this with hyperplan" or "audit security on X" may auto-route, but **explicit `/omo-<skill>` invocation is the reliable form.**

For autonomous recurrence, pair with Claude Code's built-in `/loop`:

```
/loop 30m /omo-ultrawork "<task>"
```

That re-runs every 30 minutes until the task emits the completion-promise token.

## Acknowledgments

- Upstream design by [Yeongyu Kim (`@code-yeongyu`)](https://github.com/code-yeongyu) and contributors.
- This port adapts the prompts and orchestration patterns to Claude Code; no upstream binaries or runtime code are bundled.
- The 5-critic hyperplan structure, the 5-agent security audit, the Prometheus interview/plan/verify discipline, the Sisyphus parallel-fan-out doctrine, and the Hephaestus "explore-first ask-last" stance are all omo originals.

## Smoke test

Before installing, you can validate the suite locally:

```bash
bash scripts/smoke-test.sh
```

Checks: frontmatter validity, cross-references (every `Task(subagent_type="omo-X")` resolves to a real `omo-X.md`), no forbidden upstream patterns (`task(`, `category=`, `load_skills=`, `team_*`, …), install/uninstall dry-runs.

## Repository layout

```
omo-cc/
├── skills/
│   ├── omo-ultrawork/SKILL.md
│   ├── omo-hyperplan/SKILL.md
│   ├── omo-security-research/SKILL.md
│   ├── omo-start-work/SKILL.md
│   ├── omo-init-deep/SKILL.md
│   ├── omo-remove-ai-slops/SKILL.md
│   └── omo-ralph-loop/SKILL.md
├── agents/
│   ├── omo-sisyphus.md            # orchestrator
│   ├── omo-hephaestus.md          # autonomous deep worker
│   ├── omo-prometheus.md          # interview-mode planner
│   ├── omo-metis.md               # pre-planning consultant
│   ├── omo-momus.md               # plan reviewer
│   ├── omo-oracle.md              # 3-tier strategic advisor
│   ├── omo-librarian.md           # external lib researcher
│   ├── omo-explore.md             # codebase search w/ analysis+results contract
│   ├── omo-skeptic.md             # hyperplan critic: anti-over-engineering
│   ├── omo-validator.md           # hyperplan critic: completeness/blast-radius
│   ├── omo-researcher.md          # hyperplan critic: cite-or-retract
│   ├── omo-architect.md           # hyperplan critic: separation-of-concerns
│   ├── omo-creative.md            # hyperplan critic: orthodoxy
│   ├── omo-surface-hunter.md      # security: attack-surface map
│   ├── omo-auth-data-hunter.md    # security: authn/authz/injection
│   ├── omo-runtime-supply-hunter.md  # security: fs/subprocess/deps/env
│   ├── omo-poc-engineer-a.md      # security: build PoCs
│   ├── omo-poc-engineer-b.md      # security: independently falsify
│   ├── omo-worker-quick.md        # haiku — trivial tasks
│   ├── omo-worker-deep.md         # opus — hairy single-goal research
│   ├── omo-worker-ultrabrain.md   # opus — hard logic / architecture
│   ├── omo-worker-visual.md       # sonnet — frontend / UI
│   ├── omo-worker-artistry.md     # opus — creative / unconventional
│   └── omo-worker-default.md      # sonnet — moderate-effort default
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── smoke-test.sh
├── LICENSE         # SUL-1.0
├── NOTICE.md       # derivative-work disclosure
└── README.md
```

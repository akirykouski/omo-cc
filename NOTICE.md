# NOTICE — Derivative work disclosure

This repository (`omo-cc`) is a **modified port** of [`oh-my-openagent`](https://github.com/code-yeongyu/oh-my-openagent) (`omo`, formerly `oh-my-opencode`) by [Yeongyu Kim](https://github.com/code-yeongyu) and contributors.

## What changed

The upstream `oh-my-openagent` is an [opencode](https://github.com/sst/opencode) plugin. This repository ports the **prompts and orchestration patterns** of its load-bearing skills and agents to run natively in [Claude Code](https://claude.com/claude-code) — Anthropic's official CLI for Claude — without any opencode runtime dependency.

Specifically:
- **Subagent invocations** rewritten from opencode's `task(subagent_type="X", category="Y", load_skills=[...], run_in_background=Z)` shape to Claude Code's `Task(subagent_type="omo-X", prompt="...")` shape.
- **Team mode** (`team_create`, `team_send_message`, `team_*` family) simulated via parallel `Task` fan-out, since Claude Code has no equivalent runtime.
- **Multi-model gateway routing** (Kimi K2.6, GPT-5.5, GLM, Gemini, …) collapsed to Claude-only model assignment (Haiku/Sonnet/Opus) via worker-agent variants.
- **Session continuity** (`task_id="ses_..."` re-dispatch) dropped — Claude Code subagents don't preserve context across calls. Orchestrators concatenate prior-turn findings into each new prompt. With Opus 4.8's prompt caching + the [Messages API mid-task system entries](https://support.claude.com/en/articles/12138966-release-notes), the token cost of this workaround is roughly comparable to upstream's session-resume idiom.
- **Native multi-agent orchestration via [Dynamic Workflows](https://code.claude.com/docs/en/workflows)** (Claude Code 2.1.154+, research preview): omo-cc skills detect DW availability and recommend the workflow path; the omo opinion layer (mandatory Prometheus interview, scenario contract, hostile-critic rounds, verification gates) runs inside the JS orchestration script Claude writes.
- **Hashline edit tool, LSP MCPs, AST-grep MCPs, tmux visualization** — not ported (these are runtime / harness pieces). Skill prompts fall back to Claude Code's native tools (`Edit` with anchored matching, `Grep`/`Read`, `Bash` typecheck).
- All `omo-*` names prefixed to namespace the install under `~/.claude/skills/omo-*/` and `~/.claude/agents/omo-*.md`.

## License

This work is distributed under the **Sustainable Use License v1.0 (SUL-1.0)** — see [`LICENSE`](LICENSE). This is the same license as the upstream work; we have not changed the license terms.

Key practical implications of SUL-1.0:

> *"You may use or modify the software only for your own internal business purposes or for non-commercial or personal use. You may distribute the software or provide it to others only if you do so free of charge for non-commercial purposes."*

This means:
- **You may** use it personally, internally at your company, or for non-commercial projects.
- **You may not** sell it, bundle it into a commercial product, or distribute it for payment.
- If you fork or modify, you must preserve this NOTICE and the LICENSE file, and you must add your own prominent notice describing what you changed (per the upstream license's "Notices" clause).
- SUL-1.0 is **not OSI-approved** and is not compatible with most "open source" definitions. Read the LICENSE in full before depending on this.

## Upstream attribution

The intellectual design — the discipline agents (Sisyphus / Hephaestus / Prometheus / Oracle / Librarian / Explore / Metis / Momus), the 5-critic hyperplan structure, the 3-hunter + 2-PoC-engineer security audit, the ultrawork mode-prompt with mandatory plan handoff and 4-reviewer Final Verification Wave, the category-routing prompt-append idiom, the `<analysis>` / `<results>` explore contract, the Inherited-Wisdom notepad protocol, the Incremental Write Protocol for Prometheus — is all originated upstream by Yeongyu Kim and the omo contributors. This port adapts that design to a different harness. Credit and complaints belong upstream.

Upstream sources consulted for this port (commit `6cdec907` of branch `dev`):
- `packages/prompts-core/prompts/ultrawork/default.md`
- `packages/prompts-core/prompts/prometheus/default.md`
- `src/agents/*.ts` (sisyphus, hephaestus, metis, momus, oracle, librarian, explore)
- `.agents/skills/hyperplan/SKILL.md`
- `.agents/skills/security-research/SKILL.md`
- `src/features/builtin-commands/templates/{start-work,init-deep,ralph-loop,remove-ai-slops}.ts`
- `src/features/builtin-skills/skills/ai-slop-remover.ts`
- `src/tools/delegate-task/{anthropic,google,openai}-categories.ts`

## No affiliation

This repository is not endorsed by or affiliated with Yeongyu Kim, Sisyphus Labs, the `oh-my-openagent` project, Anthropic, or Claude Code. It is an independent, unofficial port.

# CLAUDE.md — Heddle SDK

The canonical agent instructions for this repository live in
[`AGENTS.md`](AGENTS.md). Read that first and treat it as the source of
truth for architecture, verification commands, and repo-specific rules.

Cross-repo guidance (philosophy, invariants, wire-protocol contract,
skills, and subagents) lives in
**[`../heddle-agent-toolkit/`](../heddle-agent-toolkit/)** — installed
into this repo's `.claude/` via the toolkit's `install.sh`.

## Claude-specific notes

- When session history is missing or compacted, recover direction from
  `AGENTS.md` + the toolkit anchors. Then `docs/ROADMAP.md`,
  `docs/CONTRACT_EVOLUTION.md`, and `git status` for the active work.
- Keep handoffs short and concrete: name changed files, commands run,
  and any local tooling caveats.
- For non-trivial work, spawn `heddle-architect` to design first.
- For wire-protocol diffs, spawn `heddle-contract-reviewer` to verify
  cross-language coherence before commit.

If this file ever conflicts with `AGENTS.md`, follow `AGENTS.md` and
the current user request.

# How to Maintain AGENTS.md

Status: active maintenance guide
Created: 2026-05-18
Scope: best-practice guide for repository-level coding-agent instruction files

## Purpose

This guide defines how to write and maintain `AGENTS.md`-style files. It should
capture broad best practices from the AGENTS.md community, OpenAI Codex, and
Claude Code documentation.

It must not encode this repository's current roadmap, phase state, research
status, domain governance, or file-by-file project routing. Those details belong
in the repository's `AGENTS.md` or in the canonical project documents that
`AGENTS.md` links to.

## Source References

This guide is based on:

- AGENTS.md community format: `https://agents.md/`
- OpenAI Codex AGENTS.md docs:
  `https://developers.openai.com/codex/guides/agents-md`
- Claude Code memory docs:
  `https://code.claude.com/docs/en/memory`
- Claude Code best practices:
  `https://code.claude.com/docs/en/best-practices`

Common direction across those sources:

- give agents a predictable instruction file;
- include project-specific setup, testing, style, workflow, and safety rules;
- keep instructions concise, specific, structured, and stable;
- link to detailed docs instead of copying long context;
- review and prune instructions as the project evolves.

## Core Principles

Use `AGENTS.md` as a README for coding agents: a small, predictable entry point
that tells an agent how to work safely and effectively in the repository.

Good instructions are:

- **Specific**: "Run `pnpm test` after changing frontend code" is better than
  "test your work".
- **Actionable**: the agent can directly follow the rule.
- **Stable**: the rule should remain true across many sessions.
- **Scoped**: project-wide rules live near the repo root; specialized rules can
  live in nested instruction files or tool-specific files.
- **Verifiable**: include commands, expected checks, or success criteria when
  possible.
- **Short enough to matter**: bloated instruction files cause important rules to
  be ignored.

## Layering Model

Keep durable agent behavior in `AGENTS.md`. Keep detailed or frequently changing
knowledge in canonical project docs and link to them.

Typical layering:

```text
AGENTS.md
  startup protocol, safety rules, setup commands, testing commands,
  repository etiquette, routing links, verification expectations

README / project overview
  human-facing introduction and quick start

architecture / status / roadmap docs
  current state, plans, decisions, active workstreams

governance / security docs
  durable policy, approval gates, compliance, data-handling rules

decision records
  why major decisions were made

reports / generated artifacts
  factual outputs from runs, audits, or evaluations
```

If a detail belongs to a lower layer, `AGENTS.md` should link to it rather than
copy it.

## What Belongs In AGENTS.md

Include:

- concise project identity and scope;
- setup, build, lint, test, and verification commands;
- required startup or orientation steps;
- code style rules that differ from defaults;
- repository-specific workflow rules, such as branch, commit, PR, or release
  conventions;
- approval and safety constraints that an agent must know before acting;
- security, secrets, data, or production-risk rules;
- links to authoritative project docs;
- common gotchas that are not obvious from code;
- instructions for when to ask the user before proceeding.

## Exit Criteria Discipline

For research or evaluation-heavy repositories, `AGENTS.md` should include a
durable rule that decision records verify exit criteria at the same granularity
where the criterion was stated.

Useful wording pattern:

```text
Aggregate metrics cannot close cohort-, segment-, asset-, horizon-, or
scenario-specific obligations. If an exit metric is scale-sensitive, such as
AUC, precision, recall, breach rate, coverage, or calibration gap, include the
relevant per-slice breakdown in the decision record or explicitly mark the
claim aggregate-only / diagnostic-only.
```

Keep the rule general in `AGENTS.md`; put project-specific thresholds,
claim-grade names, cohorts, and phase outcomes in the canonical governance or
decision documents.

## What Does Not Belong In AGENTS.md

Do not include:

- long phase histories;
- full research findings;
- full platform or vendor evaluations;
- detailed API documentation;
- file-by-file codebase descriptions;
- old command transcripts;
- large copied tables from project docs;
- current status blocks that change often;
- information the agent can cheaply discover by reading code or linked docs;
- generic advice like "write clean code" unless the repository defines a
  concrete local meaning.

## Cursor And Status Rule

`AGENTS.md` may tell agents where the current project cursor lives, but should
not duplicate the cursor itself.

Good:

```text
Read docs/status.md for the current research cursor.
Read docs/roadmap.md for the current architecture cursor.
If the cursor changes, update that canonical file.
```

Bad:

```text
Current phase: Phase N ...
Next 14 actions: ...
Current blockers: ...
```

Duplicated state drifts.

## Discovery And Scope Notes

Codex reads `AGENTS.md` files before work and layers global, project, and nested
instructions. More specific files closer to the working directory can override
broader guidance.

Claude Code reads `CLAUDE.md`, not `AGENTS.md`, but Claude documentation
recommends importing `AGENTS.md` from `CLAUDE.md` when a repository already uses
the AGENTS format.

For large repositories, prefer nested instruction files or path-scoped rules for
specialized areas instead of growing one root file indefinitely.

## Size And Context Budget

There is no universal required length. The practical rule is: short enough to be
read every session, long enough to prevent expensive mistakes.

Recommended project-level target:

- about 100-200 lines for a root instruction file;
- well below tool context limits;
- split or link out when instructions become long, historical, or conditional.

OpenAI's Codex docs describe an instruction-size cap for discovered project
documents; Claude docs also stress that shorter, clearer instruction files are
followed more reliably. Treat size as a behavior-quality issue, not a formatting
preference.

## Edit Checklist

Before adding something to `AGENTS.md`, ask:

1. Would removing this cause a likely agent mistake?
2. Is it stable across sessions?
3. Is it actionable?
4. Is there a canonical doc that should own the detail instead?
5. Can this be a one-line link rather than copied context?
6. Does it duplicate a status, roadmap, README, CLI reference, or policy doc?
7. Is the wording specific enough to change behavior?

If the answer to 1, 2, or 3 is no, do not add it.

## Rewrite Checklist

When pruning or rewriting `AGENTS.md`:

1. Preserve safety constraints.
2. Preserve setup and verification commands.
3. Preserve source-of-truth routing.
4. Preserve approval requirements.
5. Preserve repo-specific workflow rules.
6. Move historical or changing context to canonical docs.
7. Replace long status blocks with links.
8. Verify links exist.
9. Check the diff for accidental content loss.

## Recommended Shape

A practical root `AGENTS.md` usually has sections like:

```markdown
# AGENTS.md

## Startup Protocol

## Project Identity

## Source-of-Truth Map

## Safety And Approvals

## Setup And Commands

## Code Style

## Testing And Verification

## Git / PR Workflow

## Documentation Maintenance
```

No section is mandatory. Use headings that fit the repository, but keep them
predictable.

## Review Cadence

Review `AGENTS.md` when:

- an agent repeats a preventable mistake;
- onboarding requires the same explanation more than once;
- build, test, security, approval, or workflow rules change;
- the file grows large enough that important instructions get buried;
- project status is copied into `AGENTS.md` instead of linked;
- instruction behavior seems stale after a major repository change.

Review question:

```text
Would a new coding agent understand how to work safely here in under two minutes?
```

If not, improve routing and prune history.

## Self-Update Rule

Update this guide only when the underlying best-practice model changes, such as:

- a source reference changes;
- OpenAI / Claude / AGENTS.md community guidance changes;
- the recommended shape of instruction files changes;
- a new broadly useful anti-bloat or maintenance rule is adopted.

This file may be changed only with explicit user agreement. Do not silently
modify it as a side effect of ordinary `AGENTS.md` maintenance.

Do not add repository-specific roadmap, governance, or phase details to this
guide.

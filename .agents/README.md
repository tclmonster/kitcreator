# .agents

Task-specific agent skills, in the [Agent Skills](https://agentskills.io/specification)
format: `skills/<name>/SKILL.md`, with optional `scripts/` and `references/`.
General instructions are in `AGENTS.md`, which also lists the skills.

To add a skill:

- Name it `kc-<topic>`; the `name` in `SKILL.md` must match the directory.
- Keep `SKILL.md` brief; put long material in `references/`.
- Write scripts in POSIX `sh` where practical.
- List it under Skills in `AGENTS.md` with when to read it.

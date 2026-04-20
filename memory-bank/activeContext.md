# Active Context — k8s-monitoring

> **Update this file at the START and END of every session.**
> It is the first file read to resume work. Keep it focused on the present.

## Current Focus

_What is being worked on right now? (1-3 sentences)_

Setting up project context persistence infrastructure. Created the `progressive-commits` skill for atomic commits. Now establishing the Memory Bank system so future sessions can resume without loss of context.

## Recent Changes

_What changed in the last 1-2 sessions? (bullet list, newest first)_

- Created `memory-bank/` directory with initial project context files (this session)
- Created `.github/skills/progressive-commits/SKILL.md` — skill for atomic conventional commits
- Updated `AGENTS.md` with the `progressive-commits` skill entry

## Next Steps

_What comes next? Be specific. Each item should be something the next session can start immediately._

- [ ] Run and verify all infrastructure scripts (`01`→`09`) end-to-end on Linux
- [ ] Create missing Linux scripts (`04`→`09` in `00.Infraestrutura/linux/`) — check which ones exist
- [ ] Deploy `MonitoringDotNet` to the cluster and validate OTLP signals reach Grafana
- [ ] Verify `nuxt-workshop` Helm chart deploys and produces telemetry
- [ ] Add `instalar.sh` equivalent for every `instalar.ps1` in `00.Infraestrutura/servicos/`

## Active Decisions

_Decisions made this session that future sessions should know about._

- Memory Bank pattern adopted for project context persistence (see `memory-bank/` folder)
- `progressive-commits` skill should be used whenever running setup scripts
- `session-handoff` skill must be triggered at end of work sessions to update memory bank

## Blockers / Open Questions

_Things that need resolution._

- [ ] Confirm which Linux scripts are missing vs. Windows scripts — `00.Infraestrutura/linux/` appears incomplete
- [ ] `05.configurar-cnpg-criar-base-pgsql.sh` and `06`-`08` scripts missing from linux folder

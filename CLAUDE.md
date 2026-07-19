# island

App macOS native (Swift/SwiftUI) : une "Dynamic Island" flottante qui suit les sessions Claude Code (états, résumés, quotas) et notifie quand un agent a fini ou attend une réponse. Voir `CONTEXT.md` pour le vocabulaire du projet et `docs/adr/` pour les décisions actées.

## Règles

1. **Git-flow strict** : jamais de commit direct ni de merge par l'agent vers `main`/`develop`. Voir le skill `git-flow` (`.claude/skills/git-flow/`) — en cours d'adaptation à ce projet (epic dédiée) ; en cas de contradiction entre le skill et ce fichier, ce fichier prime.
2. **Langue** : issues, PRD et docs en français ; code, identifiants et messages de commit en anglais.
3. Les skills de `.claude/skills/` proviennent du projet Akutia et sont en cours d'adaptation — ignorer les références Akutia (yarn, VPS, deploy.yml, em-dash guard, ports DB) tant que l'epic d'adaptation n'est pas livrée.

## Agent skills

### Issue tracker

GitHub Issues sur `Taklin1/island` via le CLI `gh`. See `docs/agents/issue-tracker.md`.

### Triage labels

Vocabulaire canonique par défaut (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) + label structurel `epic`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : `CONTEXT.md` à la racine + `docs/adr/`. See `docs/agents/domain.md`.

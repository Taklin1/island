# island

App macOS native (Swift/SwiftUI) : une "Dynamic Island" flottante qui suit les sessions Claude Code (états, résumés, quotas) et notifie quand un agent a fini ou attend une réponse. Voir `CONTEXT.md` pour le vocabulaire du projet et `docs/adr/` pour les décisions actées.

## Règles

1. **Git-flow strict** : jamais de commit direct ni de merge par l'agent vers `main`/`develop`. Voir le skill `git-flow` (`.claude/skills/git-flow/`) ; en cas de contradiction entre le skill et ce fichier, ce fichier prime.
2. **Langue** : issues, PRD et docs en français ; code, identifiants et messages de commit en anglais.
3. Les skills de `.claude/skills/` sont adaptés à island. Ils décrivent le workflow réel du projet ; en cas de doute, ce fichier prime.
4. **Vérification locale** : avant tout auto-merge ou PR, un dev est vert quand `swift build` et `swift test` passent localement. Il n'y a pas de CI de PR (aucune vérification déclenchée par une PR). La **seule** CI est le workflow de **release** (`.github/workflows/release.yml`, ADR-0010) : au push d'un tag `vX.Y.Z` sur `main`, elle vérifie que le tag == la tête de `CHANGELOG.md`, builde/signe avec le certificat stable (`island-release`, secrets `ISLAND_CERT_P12`/`ISLAND_CERT_P12_PASSWORD`) et publie une GitHub Release avec l'asset `island.zip` ; `workflow_dispatch` en produit une **draft** jetable (dry-run). Elle ne juge pas les PR — la vérité d'un dev reste `swift build`/`swift test` en local. Pièges vérifiés pour éditer/rejouer ce workflow : `docs/agents/release-ci.md`.
5. **Versioning / CHANGELOG** : les agents d'implémentation ne touchent JAMAIS à la version ni à `CHANGELOG.md`. Seul l'orchestrateur d'epic bump la version `0.x.y` et ajoute une ligne dense par issue mergée lors de la réconciliation.

## Agent skills

### Issue tracker

GitHub Issues sur `Taklin1/island` via le CLI `gh`. See `docs/agents/issue-tracker.md`.

### Triage labels

Vocabulaire canonique par défaut (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) + label structurel `epic`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : `CONTEXT.md` à la racine + `docs/adr/`. See `docs/agents/domain.md`.

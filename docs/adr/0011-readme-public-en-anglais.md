# README public en anglais : exception à la règle docs-FR

Le `README.md` à la racine — la vitrine du repo public — est rédigé **en anglais**. C'est une exception assumée et délimitée à la règle « issues, PRD et docs en français » (CLAUDE.md, règle 2) : le README est la surface d'accueil d'un public international (les utilisateurs de Claude Code), pas un document de travail interne. Tout le reste est inchangé : `CONTEXT.md`, PRD, ADR et issues restent en français ; code, identifiants et messages de commit restent en anglais. Décision actée au triage/grill du 2026-07-21 (issue #101).

## Considered Options

- **README en français** (cohérence stricte docs-FR) : rejeté — un README FR filtre l'audience dès la première seconde. Le public d'island vit dans l'écosystème Claude Code, anglophone par défaut ; la première impression d'un repo public se joue sur son README, et il serait le seul élément non anglais du parcours visiteur (code, commits, releases, install one-liner déjà EN).
- **README bilingue** (EN + `README.fr.md`, ou sections doublées) : rejeté — double maintenance sur le document le plus retouché du repo, dérive garantie entre les deux versions, et aucun lectorat identifié pour la version française (le mainteneur lit l'anglais).
- **Tout basculer en anglais** (docs, ADR, issues) : rejeté — coût de re-traduction du corpus existant sans bénéfice : ces documents sont des surfaces de travail internes dont le lectorat est l'équipe et ses agents, pas les visiteurs. La règle docs-FR garde sa raison d'être là où elle s'applique.

## Consequences

- **Frontière nette** : le README (et ce qu'il embarque : texte alternatif des visuels, légendes) est EN ; tout ce qui vit sous `docs/` reste FR — y compris `docs/assets/README.md` (doc interne sur les visuels).
- **Décision peu réversible** : revenir en arrière = re-traduire un document dense et ses visuels annotés ; l'exception est donc actée ici plutôt que laissée implicite.
- **Vocabulaire produit** : le README traduit le vocabulaire de `CONTEXT.md` de façon stable (Island, session, Summary, quotas, click-to-focus, Answer from the Island) ; `CONTEXT.md` reste la source de vérité et ses listes _Avoid_ s'appliquent aussi en anglais — jamais notch/widget pour désigner le produit (le nom de la bibliothèque vendorée DynamicNotchKit, nom propre, n'est pas concerné).
- La règle 2 de CLAUDE.md n'est pas réécrite : cet ADR est la trace de l'exception, au même titre que les autres décisions structurantes.

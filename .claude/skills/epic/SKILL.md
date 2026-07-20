---
name: epic
description: Orchestre l'implémentation complète d'une epic GitHub island par des sous-agents parallèles - branche epic intermédiaire, prompts /prompt par lot, merges + bump + CHANGELOG réconciliés, gate humain unique sur la PR epic -> develop. Utiliser dès que l'utilisateur lance « /epic <N> », demande d'« implémenter l'epic », de « lancer les issues de l'epic », de « paralléliser les issues », ou nomme une epic prête à exécuter - même sans le mot « epic » (« fais toutes les issues de la #12 »). NE PAS utiliser pour préparer une epic (grilling/PRD/issues = /grill, /to-prd, /to-issues) ni pour une issue isolée (= /prompt).
---

# /epic - orchestrateur d'implémentation d'une epic

Transforme une epic **déjà préparée** (issues grillées, décisions tranchées) en livraison
complète : sous-agents parallèles en worktrees, branche epic intermédiaire, réconciliation
version/CHANGELOG, un seul gate humain à la fin.

**Ton rôle = orchestrateur, JAMAIS implémenteur.** Tu ne touches au code que pour :
la branche epic, les résolutions de conflit de merge, la réconciliation (bump + CHANGELOG),
et les réparations d'hygiène attrapées en revue. Tout le reste passe par un sous-agent.
Une seule epic à la fois, et on valide avec Loic entre les phases - ici, entre les vagues
et au gate final.

**Entrées** : `/epic <N>` (numéro d'epic) ; option `--plan` = s'arrêter à l'étape 2
(carte + prompts affichés, RIEN n'est lancé ni créé côté git/GitHub).

---

## Étape 0 - Gate de préparation (STRICT, refus si non conforme)

`gh issue view <N>` (label `epic` attendu) + liste des sous-issues OUVERTES (sub-issues
natives via GraphQL, fallback : checklist du body). Pour CHAQUE sous-issue ouverte, vérifier :

1. **Section « Grilling » dans le body** (audit code : cause racine `fichier:ligne`,
   fichiers à toucher, taille) - c'est elle qui rend l'issue auto-porteuse pour un agent AFK ;
2. **Label `ready-for-agent`** ;
3. **Aucune « décision produit ouverte » non tranchée** dans le body (les sections Grilling
   marquent les décisions founder comme FIGÉES quand elles le sont).

Si UNE issue échoue : **STOPPE avant tout geste git**. Affiche la liste précise
(issue -> ce qui manque) et renvoie vers la préparation : grilling-code par agents read-only
+ décisions founder en batch + enrichissement des bodies. Ne lance cette préparation QUE si
Loic le demande explicitement - /epic n'auto-répare pas une epic mal préparée, c'est voulu :
le grilling est un geste founder, pas un détail d'exécution.

**Reprise (idempotence)** : relancer `/epic <N>` après une interruption reprend où on en
était. Classer chaque sous-issue dans UN de ces trois états - les confondre coûte cher :

- **Livrée** (issue close, ou PR mergée vers la branche epic) -> exclue du plan ;
- **En vol** (PR OUVERTE vers la branche epic, ou branche `feature/<issue>-*` avec des
  commits au-delà de la base) -> **ne JAMAIS relancer un agent dessus** (doublon garanti) :
  reprendre la SUPERVISION là où elle en est (vérif locale ? revue croisée ? merge ?
  réconciliation ?). Si la branche est orpheline (aucun agent vivant), le nouvel agent
  REPREND la branche existante au lieu d'en créer une ;
- **Vierge** (rien de tout ça) -> planifiée normalement à l'étape 2.

L'état se lit dans la RÉALITÉ GitHub (`gh pr list`, `git branch -a`, commits des branches),
jamais dans une mémoire ou un plan antérieur : c'est GitHub qui prime.

## Étape 1 - Branche epic

Selon /git-flow : `epic/<n>-<slug>` créée depuis un `develop` fraîchement pullé
(la réutiliser si elle existe déjà - cas reprise), pushée sur origin. TOUTES les branches
d'issues partent d'elle et TOUTES les PR d'issues la ciblent. develop ne bouge pas pendant
l'epic ; la seule PR vers develop est la PR finale (étape 5).

## Étape 2 - Carte de parallélisation + prompts

Invoquer le skill **/prompt** sur le lot des issues restantes, avec `{base}` = la branche
epic. Compléter sa carte avec les règles apprises :

- **ORDONNANCER AVANT DE PARALLÉLISER.** Lire la section `## Blocked by` de CHAQUE
  sous-issue, construire le graphe de dépendances, faire un **tri topologique**. Une vague
  ne contient QUE des issues dont tous les bloqueurs sont déjà livrés (issue close ou PR
  mergée vers la branche epic). **Deux issues liées par un bloqueur ne vont JAMAIS dans la
  même vague** - l'agent de l'aval construirait sur du code inexistant. Cycle détecté ->
  **STOP** : c'est une erreur de découpage à remonter à Loic, pas un cas à contourner.
  Si le corps de l'epic porte déjà un plan de vagues, le **recalculer** et signaler tout
  écart plutôt que l'appliquer aveuglément (le plan peut avoir vieilli ; les `Blocked by`
  des sous-issues font foi).
- **Fusionner en un seul lot** deux issues qui éditent le même fichier au même endroit.
  Un lot = un agent = une branche = une PR. Une dépendance `Blocked by` entre deux issues
  qui touchent le même site d'appel est un signal fort de fusion (elles seront de toute
  façon sérialisées).
- **Vagues de 6-8 lots maximum** - ce cap borne la LARGEUR d'un niveau topologique, il ne
  l'autorise pas à en franchir un. Il existe pour la bande passante de revue croisée et les
  merges séquentiels, pas pour la parallélisation (les fichiers d'un même niveau sont
  disjoints).
- Chaque prompt reçoit le **bloc ORCHESTRATION** (verbatim depuis
  `references/orchestration-block.md`) et `{base}` = branche epic partout (branche ET cible PR).

Si `--plan` : afficher carte + prompts et S'ARRÊTER LÀ.

## Étape 3 - Lancement + supervision

- Un sous-agent par lot (Agent tool, `isolation: worktree`, nom `impl-<issue>`),
  prompt complet de l'étape 2. Lancer toute la vague en un seul tour.
- **Relais QUESTION** : un agent qui bute termine son tour par un bloc « QUESTION: »
  (le bloc ORCHESTRATION le lui impose). À réception : poser la question à Loic
  (AskUserQuestion, avec la reco de l'agent), puis renvoyer la réponse à l'agent -
  par son **agentId** (un agent au tour terminé n'est plus joignable par nom).
- **Rapport manquant** : une notification idle peut arriver sans le rapport final ->
  renvoyer « renvoie ton rapport complet à main » au même agentId.
- Un gotcha découvert par UN agent (environnement, build) concerne probablement TOUTE la
  flotte : le diffuser immédiatement aux agents encore en vol.

## Étape 4 - Revue croisée + merges + réconciliation (par PR, séquentiel)

Pour CHAQUE PR d'issue (cible = branche epic) :

1. **Revue croisée du diff complet** - checklist minimale : périmètre respecté (rien
   au-delà de l'issue), champ de version et `CHANGELOG.md` intouchés, invariants de la zone
   respectés (règles path-scoped s'il en existe - `.claude/rules/` pas encore configuré sur
   island), nouveaux tests présents et cohérents. Un doute = question
   à l'agent, pas un patch silencieux.
2. **Vérif locale verte exigée** : `swift build` + `swift test` (+ le parcours de feature FP
   de l'issue). C'est la vérif de l'orchestrateur - pas de CI configurée pour l'instant,
   ne pas en supposer une. Puis merge : `gh pr merge <PR> --merge`.
3. **Réconciliation, STRICTEMENT gatée sur le succès du merge** (une seule chaîne `&&`,
   jamais d'étape hors chaîne, pour ne pas pousser un CHANGELOG sur un merge refusé) :
   `git pull --ff-only` (branche epic) `&&` bump `+0.0.1` (champ de version du projet)
   `&&` entrée CHANGELOG (style du repo : 1 ligne dense par version, reprise depuis la
   section « Changelog proposé » du body de PR) `&&` commit `&&` push.
4. **Conflit de merge** (typiquement `CHANGELOG.md` ou le champ de version) : worktree
   temporaire, `git merge origin/<branche-epic>`, résolution par UNION des lignes, push,
   re-vérif locale, re-merger. Ne jamais forcer.
5. **Clôture** : commenter l'issue (lien PR + version) et la fermer explicitement (les
   mots-clés `Closes` ne ferment PAS une issue sur un merge hors branche par défaut).
   Fermer l'epic manuellement une fois la dernière sous-issue close (pas de workflow
   d'auto-fermeture configuré). Pas de board GitHub pour l'instant - rien à déplacer.

## Étape 5 - Fin de vague / fin d'epic

**S'il reste des issues** : nettoyage partiel (worktrees + branches des lots livrés),
puis **/handoff** vers une session vierge pour la vague suivante (hygiène de contexte) :
le handoff pointe la branche epic, les lots restants, la version courante ; fournir le
prompt-à-coller.

**Si l'epic est complète** :

1. **Suite HP** : `/agentic-tests` (parcours nominaux) sur la branche epic - c'est le gate
   de composition prévu par ce skill avant une PR d'intégration.
2. **PR `epic/<...>` -> `develop`**, body récap : issues livrées + versions, zones sensibles
   touchées (mises en évidence pour la revue humaine), résultats HP. Si develop a bougé
   pendant l'epic : merger develop dans la branche epic d'abord et renuméroter
   versions/CHANGELOG si collision (risque de collision de version entre branches parallèles).
3. **LOIC MERGE cette PR** - c'est le gate humain unique du flux, non négociable :
   toutes les PR d'issues ont été auto-mergées par l'orchestrateur, la revue à deux parties
   vit ICI. Ne jamais la merger toi-même, même permission en poche. (La PR `develop` -> `main`
   est de même une décision humaine, hors du périmètre de /epic.)
4. Après son merge : nettoyage complet (branches locales+remote des issues ET de l'epic,
   worktrees, `git worktree prune`, `git remote prune origin`), fermer l'epic si elle ne
   l'est pas, **fermer le PRD source** (voir ci-dessous), puis **/capitalise** si la vague
   a appris quelque chose de nouveau.

   **Clôture du PRD source** : le chantier n'atterrit vraiment sur `develop` qu'ICI, donc
   c'est ici — et pas avant — qu'on ferme le PRD qui l'a lancé. Aucun lien natif GitHub ne
   rattache le PRD à l'epic ; on le retrouve par convention : l'issue **OUVERTE portant le
   label `prd`** dont le body référence cette epic (`/to-prd` écrit « PRD de l'epic #<N> »
   en tête). Sur ce PRD : commenter le lien de la PR d'intégration + la version livrée, puis
   `gh issue close`. Si aucun PRD ouvert ne référence l'epic (feature promue sans PRD, ou
   déjà fermé), ne rien inventer — le noter et passer.

---

## Ce qui casse ce flux (à surveiller activement)

- **Un agent qui touche le champ de version ou `CHANGELOG.md`** : conflit garanti en cascade
  sur toutes les PR suivantes. Le bloc ORCHESTRATION l'interdit ; la revue le vérifie.
- **Deux lots sur le même fichier dans la même vague** : la carte de l'étape 2 existe pour
  ça ; en cas de doute, fusionner les lots ou les séquencer - un conflit évité vaut mieux
  qu'un conflit résolu.
- **La dérive du périmètre** : un agent qui « en profite pour » refactorer. La revue
  croisée coupe tout ce qui n'est pas dans l'issue (le signaler à l'agent, suivi possible
  en issue séparée).
- **Le contexte long** : au-delà de ~8 lots supervisés, la qualité d'orchestration baisse -
  c'est la raison d'être des vagues + /handoff, ne pas s'en affranchir.

## Références

- `references/orchestration-block.md` - le bloc ORCHESTRATION verbatim (contraintes de
  flotte câblées : version/CHANGELOG réservés, vérif locale swift, worktree, QUESTION).
- Skills composés : `/prompt` (gabarit + carte), `/git-flow` (conventions de branches),
  `/agentic-tests` (FP par issue, HP avant PR d'intégration), `/handoff`, `/capitalise`.
- Pas encore de mémoire pilote sur island : la première vague la créera via /capitalise
  (protocole complet + pourquoi de chaque règle).

---
name: capitalise
description: Capitalise un apprentissage reutilisable dans le BON fichier (CONTEXT.md, docs/adr, docs/agents, test de regression ; JAMAIS bloater CLAUDE.md) pour que les sessions futures n'y retombent pas. Declenche cette skill des que tu decouvres en cours de travail une methode defaillante + un meilleur chemin verifie, une commande/un outil qui ne marche pas comme attendu, ou un piege non documente ; des que l'utilisateur veut perenniser un acquis meme en mots courants ("note ca quelque part", "mets ca dans la memoire du projet", "retiens la bonne facon pour la prochaine fois", "pour que ca ne recommence pas", "il faut que les prochaines sessions le sachent") ; et systematiquement en fin de grosse phase pour figer ce qui a ete appris - meme si l'utilisateur n'ecrit pas explicitement "capitalise" ou "note ca".
---

# /capitalise - Perenniser un apprentissage

Tu viens de decouvrir, en cours de travail, une meilleure facon de faire, une commande/un outil qui ne marche pas comme attendu (+ le contournement fiable), ou un piege non documente. Cette skill te fait le **ranger au bon endroit** pour que les sessions futures n'y retombent jamais - sans gonfler le `CLAUDE.md` (charge a chaque session, il doit rester concis, < 200 lignes ; c'est exactement le piege qui fait diverger un CLAUDE.md).

Suis les 5 etapes dans l'ordre. Si l'etape 1 echoue, arrete-toi : ne rien ecrire est souvent la bonne reponse.

## 1. Filtre qualite (sinon, n'ecris RIEN)
Ne capitalise QUE si l'apprentissage est :
- **reutilisable** - se reproduira dans d'autres sessions/contextes (pas un detail one-shot) ;
- **non-evident** - un bon dev pourrait y retomber (sinon ca ne merite pas une trace) ;
- **verifie** - tu as une **preuve** concrete (l'ancienne methode echoue, la nouvelle marche).

Pourquoi ce filtre : la memoire du projet n'a de valeur que si elle reste dense. Une note "au cas ou" non verifiee est du bruit qui coute des tokens et de la confiance a TOUTES les sessions futures. Si les 3 criteres ne passent pas, dis-le et stoppe.

## 2. Router vers le bon fichier (le coeur)
Le bon emplacement = celui qui **re-surface automatiquement au bon moment**, sans cout always-on inutile.

| Nature de l'apprentissage | Destination | Pourquoi la |
|---|---|---|
| **Terme de domaine** clarifie / vocabulaire flou tranche | `CONTEXT.md` (racine) via la discipline `/grill` | glossaire relu par les skills a chaque exploration de code ; zero cout sinon |
| **Decision d'archi** difficile a reverser, surprenante, issue d'un vrai trade-off | `docs/adr/NNNN-slug.md` (ADR) | relu par les skills qui touchent la zone concernee |
| **Invariant lie a une zone de code** (ce qu'il ne faut jamais faire / toujours verifier ici) | **test de regression** dans la cible `Tests` SwiftPM + un ADR si c'est aussi une decision | le test re-surface a chaque `swift test` ; c'est ce qui casse le cycle "meme erreur a l'infini" |
| **Convention d'outillage agent** (tracker, labels, commandes `gh`, sous-issues natives) | `docs/agents/*.md` | lu par les skills d'ingenierie quand elles parlent au tracker |
| **Gotcha situationnel transverse** (git, locale, env, outil CLI) | un ADR si c'est un choix ; sinon `docs/agents/` si c'est de l'outillage ; sinon un one-liner `CLAUDE.md` s'il est catastrophique-universel | island n'a pas encore de `.claude/rules/` path-scoped ni de systeme `memory/`+recall (a documenter quand il existera) |
| **Imperatif catastrophique ET universel** (a voir a CHAQUE session, non zone-scopable) | one-liner dans `CLAUDE.md` | rare, borne |

Regle d'or : **CLAUDE.md ne recoit jamais un learning de detail.** Un invariant de code se verrouille par un test de regression (+ ADR si c'est une decision) ; un terme va dans `CONTEXT.md` ; une convention d'outillage va dans `docs/agents/`. Seul ce qui est a la fois catastrophique et universel merite un one-liner dans `CLAUDE.md`. Si l'utilisateur a dit "mets ca dans CLAUDE.md" mais que le contenu appartient ailleurs, range-le au bon endroit ET dis-le ("range dans X, pas CLAUDE.md, parce que ...").

**Version / release** : n'ecris RIEN. `CHANGELOG.md` est reserve a l'orchestrateur d'epic (bump `0.x.y` + une ligne par issue mergee lors de la reconciliation) ; les agents d'implementation n'y touchent jamais.

Avant d'ecrire : `grep` l'idee dans la destination pour ne pas dupliquer (mets a jour l'entree existante plutot que d'en creer une jumelle).

## 3. Format (toujours le meme, 4 lignes)
- **Decouverte** : le piege, en 1-2 lignes.
- **Bonne methode** : le chemin le plus fiable + sur + juste, avec la **commande/le code exact**.
- **Preuve** : la commande + le resultat observe (ce qui prouve que l'ancienne methode echoue et la nouvelle marche).
- **Pourquoi** : l'axe qui rend ca important (fiabilite / securite / perf / justesse).

Dans un ADR, mappe ca sur le format maison (contexte -> decision -> raison ; voir `.claude/skills/grill/ADR-FORMAT.md`). Dans `CONTEXT.md`, mappe sur `**Terme** : definition` + `_Avoid_:` (voir `.claude/skills/grill/CONTEXT-FORMAT.md`).

## 4. Verrouiller (le code suit la pensee)
Si l'apprentissage est un **invariant de code** : ecris le **test de regression** qui **echoue sur l'ancienne methode** et **passe sur la nouvelle**, dans la cible de tests SwiftPM (`Tests/<Cible>Tests/<Nom>Tests.swift`). Verifie-le avec `swift test`. Sans test, l'apprentissage se reperd ; le test est ce qui casse le cycle "meme erreur a l'infini".
Si l'invariant concerne un comportement observable de l'app (etat des Sessions apres reception d'un evenement hook), prefere un test agentique via l'API locale d'evenements (POST d'une fixture JSON -> assertion sur l'etat publie) plutot qu'un test couple a l'implementation.
Si pertinent : refactore le code existant qui utilise encore l'ancienne methode (ou note la dette si trop large pour maintenant).

## 5. Verifier avant de finir
- **Pas de doublon** (le `grep` de l'etape 2).
- `CLAUDE.md` reste concis (<= 200 lignes).
- Si tu as touche du code ou un test : `swift build` et `swift test` verts.
- **Annonce** ou tu as range l'apprentissage et pourquoi.

## Exemples
**Exemple 1 - invariant de code (-> test de regression + zone)**
Decouverte : muter un `@Published` depuis une tache hors main-actor ne rafraichit pas la vue et logue "Publishing changes from background threads is not allowed".
Bonne methode : router la mutation par `await MainActor.run { ... }`, ou marquer le store `@MainActor`.
Preuve : un test qui pousse un evenement hook depuis une tache detachee laisse l'etat Session publie "stale" sans MainActor, correct avec.
Destination : test de regression dans la cible `Tests` SwiftPM + un ADR si on fige la regle "tout store observable est `@MainActor`".

**Exemple 2 - convention d'outillage agent (-> docs/agents)**
Decouverte : `gh` n'expose aucun flag pour lier une sous-issue native (`--add-sub-issue` n'existe pas).
Bonne methode : utiliser la mutation GraphQL `addSubIssue` avec les node IDs parent et enfant.
Preuve : `gh issue edit N --add-sub-issue` renvoie "unknown flag" ; la mutation GraphQL lie bien la sous-issue (visible dans l'onglet Sub-issues).
Destination : `docs/agents/issue-tracker.md` (outillage agent : ni zone de code precise, ni catastrophique-universel).

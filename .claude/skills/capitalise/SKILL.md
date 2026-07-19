---
name: capitalise
description: Capitalise un apprentissage reutilisable dans le BON fichier (.claude/rules, memory, docs, CHANGELOG ; JAMAIS bloater CLAUDE.md) pour que les sessions futures n'y retombent pas. Declenche cette skill des que tu decouvres en cours de travail une methode defaillante + un meilleur chemin verifie, une commande/un outil qui ne marche pas comme attendu, ou un piege non documente ; des que l'utilisateur veut perenniser un acquis meme en mots courants ("note ca quelque part", "mets ca dans la memoire du projet", "retiens la bonne facon pour la prochaine fois", "pour que ca ne recommence pas", "il faut que les prochaines sessions le sachent") ; et systematiquement en fin de grosse phase pour figer ce qui a ete appris - meme si l'utilisateur n'ecrit pas explicitement "capitalise" ou "note ca".
---

# /capitalise - Perenniser un apprentissage

Tu viens de decouvrir, en cours de travail, une meilleure facon de faire, une commande/un outil qui ne marche pas comme attendu (+ le contournement fiable), ou un piege non documente. Cette skill te fait le **ranger au bon endroit** pour que les sessions futures n'y retombent jamais - sans gonfler le `CLAUDE.md` (charge a chaque session, il doit rester < 200 lignes ; c'est exactement le piege qui l'avait fait exploser a 324k).

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
| Invariant / pattern lie a une **zone de code** (ce qu'il ne faut jamais faire, ce qu'il faut verifier dans cette zone) | `.claude/rules/<domaine>.md` (le fichier dont la frontmatter `paths:` matche la zone) **+ test de regression** | path-scoped : charge pile quand on edite la zone, zero token sinon |
| **Decision / incident / gotcha situationnel** (env, git, locale, VPS, choix produit) | `memory/<slug>.md` + 1 ligne d'index dans `MEMORY.md` | rappele via recall quand la situation revient ; n'alourdit pas l'always-on |
| **Architecture** (flux, schema BDD, topologie) | `docs/ARCHITECTURE.md` (+ ancre) | reference on-demand |
| **Exploitation** (deploy, cron, backup, rotation secret) | `docs/OPERATIONS.md` ou le runbook concerne | cheatsheet Day-2 |
| **Version / deploiement** | `CHANGELOG.md` (1 ligne) | historique |
| **Imperatif catastrophique ET universel** (a voir a CHAQUE session, non zone-scopable) | one-liner dans `CLAUDE.md` | rare, borne |

Regle d'or : **CLAUDE.md ne recoit jamais un learning de detail.** S'il existe un `.claude/rules/<domaine>.md` dont le `paths:` couvre le code concerne, c'est la. Sinon, si ce n'est pas catastrophique-universel, c'est `memory/`. Si l'utilisateur a dit "mets ca dans CLAUDE.md" mais que le contenu appartient ailleurs, range-le au bon endroit ET dis-le ("range dans X, pas CLAUDE.md, parce que ...").

Avant d'ecrire : `grep` l'idee dans la destination pour ne pas dupliquer (mets a jour la regle existante plutot que d'en creer une jumelle).

## 3. Format (toujours le meme, 4 lignes)
- **Decouverte** : le piege, en 1-2 lignes.
- **Bonne methode** : le chemin le plus fiable + sur + juste, avec la **commande/le code exact**.
- **Preuve** : la commande + le resultat observe (ce qui prouve que l'ancienne methode echoue et la nouvelle marche).
- **Pourquoi** : l'axe qui rend ca important (fiabilite / securite / perf / justesse).

Dans un `.claude/rules/*.md`, mappe ca sur le format maison **Regle / Why / Code+test**. Dans `memory/`, garde le frontmatter (`type: feedback|project|reference`) + lie les fichiers liens avec `[[slug]]`.

## 4. Verrouiller (le code suit la pensee)
Si l'apprentissage est un **invariant de code** : ecris le **test de regression** qui **echoue sur l'ancienne methode** et **passe sur la nouvelle**, dans `scripts/test/<nom>.test.ts` (lance : `set -a && . /etc/briefy.env && set +a && npx tsx scripts/test/<nom>.test.ts`). Sans test, l'apprentissage se reperd ; le test est ce qui casse le cycle "meme erreur a l'infini".
Si pertinent : refactore le code existant qui utilise encore l'ancienne methode (ou note la dette si trop large pour maintenant).

## 5. Verifier avant de finir
- **0 em-dash** : `perl -CSD -ne 'print if /[\x{2014}\x{2013}]/' <fichier>` doit etre vide (le `grep -P "\xe2..."` est NON fiable en locale UTF-8).
- `MEMORY.md` < 25 KB (sinon sa fin est ignoree au boot) ; `CLAUDE.md` <= 200 lignes.
- Pas de doublon (le `grep` de l'etape 2).
- **Annonce** ou tu as range l'apprentissage et pourquoi.

## Exemples
**Exemple 1 - invariant de code (-> .claude/rules + test)**
Decouverte : avec `drizzle-orm/postgres-js`, un DELETE sans RETURNING renvoie `.count` (pas `.length` ni `.rowCount`) -> compteurs toujours 0.
Bonne methode : lire `(res as { count?: number }).count ?? 0`. Preuve : test isole 3 rows -> `length:0, rowCount:undefined, count:3`.
Destination : `.claude/rules/database.md` (ses `paths:` couvrent `src/lib/db/**` + `drizzle/**`) + invariant grep dans `scripts/test/`.

**Exemple 2 - gotcha transverse (-> memory)**
Decouverte : `grep -P "\xe2..."` rate les em-dashes en locale UTF-8 (il matche le caractere `a-circonflexe`, pas l'octet).
Bonne methode : `perl -CSD -ne 'print if /[\x{2014}\x{2013}]/' f`. Preuve : sur un fichier a 55 em-dashes, le byte-grep dit 0, le perl dit 55.
Destination : `memory/em-dash-detection-locale.md` + ligne `MEMORY.md` (ni zone de code precise, ni catastrophique-universel).

# Travailler sur la CI de release (release.yml)

Pièges vérifiés en conditions réelles pendant l'implémentation de `release.yml`
(#90, PR #102, épic #85, ADR-0010). Le contrat du workflow lui-même est décrit
dans `CLAUDE.md` (règle 4) ; ici : ce qui casse quand on l'édite ou le rejoue.

## Pousser un fichier `.github/workflows/*` : le push HTTPS/`gh` est rejeté

- **Découverte** : pousser une branche contenant un workflow via le remote
  HTTPS (credentials `gh`) est rejeté — « refusing to allow an OAuth App to
  create or update workflow without `workflow` scope » (le token `gh` de
  Taklin1 a `repo` mais pas `workflow`).
- **Bonne méthode** : push par SSH, non soumis à la restriction OAuth :
  ```bash
  git push git@github.com:Taklin1/island.git <branch>:<branch>
  ```
  Alternative durable : `gh auth refresh -s workflow` (ajoute le scope).
- **Preuve** (#90, 2026-07-21) : même commit, push HTTPS → refus « workflow
  scope » ; push SSH → accepté, workflow enregistré par GitHub.
- **Pourquoi** : fiabilité — le refus ressemble à un problème de droits repo et
  fait tourner en rond alors que seul le *transport* est en cause.

## `${{ runner.temp }}` est invalide dans un `env:` de niveau job

- **Découverte** : référencer le contexte `runner` dans le bloc `env:` d'un
  *job* fait échouer le parse du workflow (422 au dispatch) — ce contexte
  n'existe qu'au niveau des *steps*.
- **Bonne méthode** : publier les chemins depuis un step initial, visibles
  ensuite partout (y compris dans le cleanup `if: always()`) :
  ```yaml
  - run: echo "KEYCHAIN_PATH=${RUNNER_TEMP}/island-signing.keychain-db" >> "$GITHUB_ENV"
  ```
- **Preuve** (#90) : `env:` job avec `${{ runner.temp }}` → 422 au dispatch ;
  step `>> "$GITHUB_ENV"` → dispatch et cleanup OK (c'est la forme en place
  dans `release.yml`).
- **Pourquoi** : justesse — un 422 au dispatch ne pointe pas la ligne fautive ;
  sans cette note on suspecte le YAML entier.

## Keychain runner : ne JAMAIS nettoyer le System keychain

- **Découverte** : `sudo security delete-certificate … System.keychain` bloque
  non-interactivement sur un runner headless → le job entier pend jusqu'au
  timeout (tout le reste avait fini en < 1 min). À l'inverse, `sudo security
  add-trusted-cert -d -r trustRoot -p codeSign -k System.keychain` passe sans
  souci — et c'est ce trust admin-domain qui rend le certificat auto-signé
  acceptable par `codesign` (sinon `CSSMERR_TP_NOT_TRUSTED`).
- **Bonne méthode** : le runner GitHub est éphémère — se contenter de
  `security delete-keychain <jetable>` + `rm` des fichiers secrets dans le
  cleanup ; laisser le System keychain tel quel.
- **Preuve** (#90) : job figé au timeout sur `delete-certificate` ; supprimé du
  cleanup → run complet en quelques minutes, release publiée.
- **Pourquoi** : fiabilité — un job qui pend au cleanup ressemble à un échec de
  build/signature alors que la release est déjà faite.

## `workflow_dispatch` marche depuis une branche non-défaut

- **Découverte** : la crainte « un workflow n'est dispatchable que depuis la
  branche par défaut » ne s'est PAS vérifiée : dès le push de la branche,
  GitHub enregistre le workflow.
- **Bonne méthode** : dry-run possible AVANT merge —
  `gh workflow run release.yml --ref feature/…` exécute la version du workflow
  de ce ref (et produit une draft Release jetable, contrat du dry-run).
- **Preuve** (#90) : dispatch `--ref feature/90-release-workflow` → run vert,
  draft Release produite, avant tout merge vers l'epic.
- **Pourquoi** : vitesse — itérer sur le workflow sans polluer `main` ni
  attendre un merge.

## Runner `macos-15` : versions qui comptent

- Swift 6 par défaut (build release ~36 s) ; `actions/checkout@v5`
  (v4 déclenche un warning Node 20 déprécié). Vérifié sur les runs de #90.

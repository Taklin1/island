# HP-04 — Carte Étendue : titre de session + compte discret des tâches de fond

**But** : vérification **VISUELLE** (le seul canal qui tranche pour le rendu
SwiftUI) de la carte Étendue — (1) le **titre de session** s'affiche en haut de
la carte (#32), le chemin du projet en dessous ; (2) un **compte discret**
« ⋯ N background tasks running » (libellé EN, ADR-0012) apparaît tant qu'une
tâche de fond est vivante — ici un Sous-agent (#48/Q6, élargi #79).

**Couvre** : #32 (titre sur carte Étendue) + #48/Q6 (compte discret).

## Pré-requis

- App lancée sur 41414, `TOKEN`, helper `post` (cf. HP-01).
- Le titre est lu **localement** du transcript (#32, ADR-0002) : il faut un vrai
  fichier transcript. Deux enregistrements JSONL distincts : `ai-title`
  (`aiTitle`, auto) et `custom-title` (`customTitle`, `/rename`, qui prime).
  Écrire un transcript minimal AVANT de poster le hook :
  ```bash
  T=/tmp/hp-expanded-1.jsonl
  printf '%s\n' '{"type":"ai-title","aiTitle":"Corrige le crash du parser","sessionId":"hp-expanded-1"}' > "$T"
  ```
- Ouverture de l'Étendu : hover synthétique CGEvent vers le haut-centre (l'Island
  est top-center), cf. `docs/agents/agentic-driving.md`. Compiler `mouse_move` :
  ```bash
  swiftc -o /tmp/mouse_move docs/…/mouse_move.swift   # source dans agentic-driving.md
  /tmp/mouse_move 720 15 && sleep 1.5 && screencapture -x /tmp/hp-expanded.png
  /tmp/mouse_move 720 600   # rendre le curseur
  ```
  (Intrusif — consenti pour cette campagne. Vite, puis rendre la main.)

## Étapes

1. Écrire le transcript `hp-expanded-1.jsonl` avec un `ai-title` reconnaissable.

2. **UserPromptSubmit** (transcript_path pointant sur ce fichier) ⇒ `running`, le
   titre est relu.
   ```json
   {"session_id":"hp-expanded-1","transcript_path":"/tmp/hp-expanded-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"UserPromptSubmit","prompt":"Corrige le crash"}
   ```

3. **Stop** constat avec un Sous-agent vivant (pour afficher le compte) ⇒
   `running ×1bg`.
   ```json
   {"session_id":"hp-expanded-1","transcript_path":"/tmp/hp-expanded-1.jsonl","cwd":"/Users/loic/Documents/island","hook_event_name":"Stop","last_assistant_message":"Sous-agent lancé…","background_tasks":[{"id":"sub-1","type":"subagent","status":"running"}]}
   ```
   Attendu trace : `island[hp-expanded-1]=running ×1bg`.

4. Ouvrir l'Étendu (hover synthétique) et screenshoter. **Vérif visuelle** :
   - Le **titre** « Corrige le crash du parser » s'affiche en haut de la carte
     (et non le seul nom de projet `island`).
   - Le **chemin du projet** apparaît sous le titre.
   - La ligne discrète **« ⋯ 1 background task running »** est présente.
   - La trace `island: [ts] expanded on hover: N session card(s)` confirme
     l'ouverture de l'Étendu.

## Critères de réussite

- Screenshot montrant le titre de session en tête de carte + le chemin dessous
  (#32).
- Screenshot montrant « ⋯ 1 background task running » tant que le Sous-agent est
  vivant (#48/Q6).
- Le mode Étendu s'est bien ouvert (trace `expanded on hover`), curseur rendu.

## Hors périmètre (fixtures pures)

- **#33 click-to-focus** : ramener le focus sur le terminal Ghostty d'une Session
  exige une **vraie fenêtre Ghostty ciblée** ; non reproductible en fixtures
  pures. À vérifier **manuellement** (cliquer une carte ⇒ le terminal repasse au
  premier plan, et l'Acquittement éteint le Liseré de cette Session). Marqué comme
  observation, non exécuté ici.

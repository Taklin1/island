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
- Rendu : **le screenshot d'un Étendu maintenu au hover synthétique n'est PAS
  fiable** (panneau déployé autour du curseur ⇒ pas de `mouseEntered` natif ⇒
  recede avant le `screencapture` ; méthode périmée, cf. « Mode Étendu » de
  `docs/agents/agentic-driving.md`, campagnes #41 et #134). Ce qui tranche :
  - le **mécanisme** de Révélation : la trace `révélation: N session card(s)`
    (couvert par ailleurs par les tests purs Reveal/Recede et le FP #130) ;
  - le **canal visuel** : capturer un **Peek** (événementiel, fenêtre ~2,5 s,
    déclenché par le POST d'un `Stop` marquant — aucun geste souris) ;
  - le **contenu de carte** (titre, compte) : à l'œil au **gate HITL** (vrai
    trackpad posé sur le panneau), ou considéré inchangé si l'épopée en cours
    ne touche pas au rendu des cartes.

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

4. **Canal visuel** : POSTer un `Stop` marquant sur une session dédiée
   (`hp-peek-*`, ex. question ⇒ `waiting`) et `screencapture` pendant la fenêtre
   du Peek (~2,5 s). Vérif : pastille Sprite + texte « projet · état : "…" ».

5. **Contenu de carte** (vérif humaine, vrai trackpad posé sur le panneau, ou
   « rendu inchangé » si l'épopée ne touche pas aux cartes) :
   - Le **titre** « Corrige le crash du parser » en haut de la carte
     (et non le seul nom de projet `island`), le **chemin du projet** dessous.
   - La ligne discrète **« ⋯ 1 background task running »** présente.

## Critères de réussite

- Trace `running ×1bg` (état + décodage du compte) et titre relu du transcript.
- Screenshot du **Peek** net (Sprite + texte) — le canal visuel événementiel.
- Carte Étendue : confirmée à l'œil (gate HITL) ou explicitement marquée
  « rendu intouché par l'épopée » dans le rapport.

## Hors périmètre (fixtures pures)

- **#33 click-to-focus** : ramener le focus sur le terminal Ghostty d'une Session
  exige une **vraie fenêtre Ghostty ciblée** ; non reproductible en fixtures
  pures. À vérifier **manuellement** (cliquer une carte ⇒ le terminal repasse au
  premier plan, et l'Acquittement éteint le Liseré de cette Session). Marqué comme
  observation, non exécuté ici.

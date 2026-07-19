# Spike #25 — Ciblage fenêtre Ghostty (Accessibilité) & format du tool-call AskUserQuestion

> Epic #22 · PRD #23 · ADR « réponse par injection ciblée » · termes CONTEXT.md « Réponse depuis l'Island » / « Injection ».
> **Statut : findings à VALIDER par Loïc.** Rien n'est figé (ADR/CONTEXT) tant que le feu vert n'est pas donné.
> Investigation exploratoire du 2026-07-19 — prototypes jetables sous scratchpad, aucun code de production livré.

## Résumé exécutif (la reco en un paragraphe)

- **Comment on cible (a)** : chaque fenêtre Ghostty expose son cwd via l'attribut Accessibilité
  **`AXDocument` = `file://<cwd>/`**. On rapproche ce cwd de `Session.cwd`. **Critère « cible certaine »
  = exactement UNE fenêtre (toutes instances Ghostty confondues) dont l'`AXDocument` égale le cwd de la
  Session.** Zéro ou ≥ 2 correspondances → **incertain → on dégrade en Click-to-focus** (jamais de frappe).
- **Quoi on lit (b)** : le tool-call `AskUserQuestion` est présent tel quel dans le JSONL — bloc
  `tool_use`, `input.questions[]`, chaque question portant `question`, `header`, `multiSelect`, et
  `options[]` **ordonnées** (`{label, description}`). L'ordre du tableau **est** le mapping option → touche
  (1, 2, 3…). Défensif : pas d'`options` extractibles → pas de boutons → on dégrade en focus.
- **Permissions escaladées** : **absentes du transcript** (aucun `tool_use` de permission n'y figure) →
  la source des options d'un prompt de permission n'est **pas** le JSONL → **à traiter en #29**, source à
  déterminer (menu allow/deny fixe, ou autre signal).
- **Injection** : la permission Accessibilité est accordable **par binaire** (`AXIsProcessTrusted() == true`
  vérifié). Le ciblage + la lecture se font **sans rien poster**. L'injection réelle (frappe) est **faisable
  en principe** mais **ne se prouve QUE sur `island.app` packagé contre une cible jetable — JAMAIS sur
  l'instance Ghostty vivante** (cf. incident ci-dessous, capitalisé dans `docs/agents/agentic-driving.md`).

---

## Inconnue (a) — ciblage d'une fenêtre/onglet Ghostty via l'Accessibilité

### Signal retenu : `AXDocument` (cwd structuré), pas le titre

Ghostty implémente le « represented document » macOS : chaque fenêtre expose
`AXDocument = file:///chemin/du/cwd/`. Lu via `AXUIElementCopyAttributeValue(window, kAXDocumentAttribute)`.

Le **titre (`AXTitle`) n'est PAS fiable** pour le cwd : Claude Code l'écrase avec le texte de la tâche
(ex. `✳ Découper l'epic #22…`, `⠂ Spike ciblage Ghostty…`). Un shell nu montre bien `~/Documents/projet`,
mais dès qu'une Session tourne, le titre part sur la tâche. **`AXDocument` reste le cwd** quel que soit
l'état → c'est le signal primaire. (Le cwd de la Session est déjà connu du Store : `Session.cwd`.)

### Énumération : TOUTES les instances du bundle

`AXWindows` se lit sur `AXUIElementCreateApplication(pid)`. Il faut itérer **toutes** les
`NSRunningApplication` du bundle `com.mitchellh.ghostty`, pas seulement la première : un `open -n` peut
lancer une 2ᵉ instance dont les fenêtres seraient sinon invisibles. (En usage normal Loïc a une seule
instance ; robustesse tout de même.)

### Critère « cible certaine vs incertaine » = unicité de l'`AXDocument`

Démonstration sur un cas **réel multi-fenêtres** (8 fenêtres, 3 projets) capturé pendant le spike :

| cwd (`AXDocument`)            | fenêtres | verdict                          |
|-------------------------------|:--------:|----------------------------------|
| `…/Documents/island/`         | **1**    | **certain → injection autorisée** |
| `…/Documents/akutia/`         | 4        | incertain → **dégrade (focus)**   |
| `…/Documents/hedgencia/`      | 3        | incertain → **dégrade (focus)**   |

→ **Règle** : `matches = fenêtres où AXDocument == Session.cwd`. `matches.count == 1` → certain.
Sinon (0 ou ≥ 2) → incertain → Click-to-focus (réutilise IslandFocus de #10). C'est exactement la garde
« cible sûre ou rien » de l'ADR.

### Limites connues (documentées, gérées par la gate)

- **Plusieurs Sessions dans le même projet** = plusieurs fenêtres au même cwd → **incertain** (cas akutia
  ci-dessus). C'est le cas dominant d'« incertain » ; il dégrade proprement, jamais de frappe au mauvais endroit.
- **Splits** (plusieurs surfaces/terminaux dans une fenêtre) : `AXDocument` ne reflète que la surface active
  → une fenêtre splittée à 2 cwds est un angle mort. Géré conservativement : si le cwd ne matche pas, la
  fenêtre n'est pas comptée ; si un split masque le vrai cwd, on tombe au pire en « incertain » → focus.
- **Onglets d'arrière-plan** : granularité `AXDocument` par onglet non entièrement caractérisée (les onglets
  natifs macOS apparaissent comme des `AXWindows` distinctes, mais un onglet d'arrière-plan pourrait ne pas
  rafraîchir son `AXDocument`). Même filet : ambiguïté → focus.
- Ces angles morts **ne peuvent pas** produire une frappe dans le mauvais terminal : ils élargissent seulement
  le domaine du « incertain ». Cohérent avec « aucune décision automatique / le prompt du terminal reste le filet ».

### Injection de frappe — mécanisme, permission, et garde-fou de test

- **Permission** : `AXIsProcessTrusted()` renvoie **`true`** dans l'environnement de dev (Ghostty a l'octroi
  Accessibilité). Cette même permission couvre la lecture AX **et** le post de `CGEvent`. Accordée **par
  binaire** → à ré-accorder pour `island.app` au packaging (onboarding = #28).
- **Mécanisme visé** : `AXRaise` la fenêtre cible + activer l'app + poster la frappe en `CGEvent`
  (`keyboardSetUnicodeString` pour le texte, keycode 36 pour Return). `CGEvent` frappe la fenêtre au premier
  plan → il faut d'abord fronter la cible (ce que la garde d'unicité rend sûr).
- **Ce qui est prouvé** (lecture seule, sans risque) : permission OK, énumération multi-instance OK,
  `AXDocument` fiable, `AXRaise` disponible sur les fenêtres, le code `CGEvent` compile et poste.
- **Ce qui reste à prouver end-to-end** : qu'une frappe atterrit bien dans la surface Ghostty ciblée. **À
  faire UNIQUEMENT sur `island.app` packagé contre une cible jetable dédiée** — voir garde-fou.

> ⚠️ **Garde-fou (incident du spike, capitalisé)** : tenter la preuve d'injection en pilotant au clavier
> l'**instance Ghostty vivante** (`Cmd+N`/frappe/`Cmd+W` en `CGEvent`, même « gardé » par un check de titre)
> a **fermé toutes les fenêtres Ghostty de Loïc** (`AXWindows` 8 → 0). `open -n Ghostty.app` ne fournit pas
> une cible isolée fiable (mono-instance : restauration de fenêtres + activation cross-instance qui ne
> fronte pas → la frappe fuit ailleurs). **Règle absolue** : ne jamais synthétiser de frappe/raccourci vers
> l'instance qui héberge les vraies Sessions ; l'injection réelle se valide en FP sur `island.app`.
> Détail : `docs/agents/agentic-driving.md` § « Injection de frappe : JAMAIS sur l'instance Ghostty vivante ».

---

## Inconnue (b) — format du tool-call AskUserQuestion dans le JSONL

Capturé sur de **vrais** transcripts `~/.claude/projects/-Users-loic-Documents-island/*.jsonl`
(20 occurrences réelles ; le format est stable entre elles).

### Bloc `tool_use` (message `type: "assistant"`)

```json
{
  "type": "tool_use",
  "id": "toolu_014GjjBBBbHratYKYEidRXxD",
  "name": "AskUserQuestion",
  "input": {
    "questions": [
      {
        "question": "Les glyphes pixel-art des cartes Étendues te conviennent-ils ?",
        "header": "Glyphes",
        "multiSelect": false,
        "options": [
          { "label": "Validé, intègre (Recommandé)", "description": "…" },
          { "label": "Validé sauf détails",          "description": "…" },
          { "label": "À retravailler",               "description": "…" }
        ]
      }
    ]
  }
}
```

Structure à lire (extension du `TranscriptReader`/`ToolInput` de #7) :

- **`input.questions` est un TABLEAU** → une invocation peut poser **plusieurs questions** (cas réel observé :
  2 questions dont une `multiSelect`). Décision d'affichage #26 : traiter le cas dominant (1 question) ; sur
  N > 1, choix produit (afficher la 1ʳᵉ / empiler / dégrader).
- Par question : `question` (**le libellé**), `header` (puce courte), `multiSelect` (booléen), `options[]`.
- **`options[]` est ordonné** → **l'index (0,1,2…) EST le mapping vers la touche (1,2,3…)**. C'est ce qu'on
  affiche en boutons et ce qu'on injecte.

### Résultat (message `type: "user"`)

Le `tool_result` est une **chaîne** (pas d'objet structuré) :

```
"Your questions have been answered: \"<question>\"=\"<réponse>\", \"<question2>\"=\"<réponse2>\". You can now continue with these answers in mind."
```

→ Il enregistre le **texte de la réponse**, pas la touche pressée ; la réponse peut être un libellé **ou** du
texte libre (« Other »). Utile comme fixture d'entrée, **pas** comme source du mapping (le mapping est le sens
*aller* option → touche, que l'Island contrôle).

### Points ouverts sur le mapping option → frappe (pour #26/#27)

Le transcript donne les options **logiques** et leur **ordre** ; il ne dit **pas** quelle frappe physique
sélectionne l'option N dans la TUI Claude Code. À confirmer sur la TUI vivante en #26/#27 :

1. **Chiffre direct (`1`/`2`/`3`) vs flèches + `Entrée`** pour le sélecteur `AskUserQuestion`.
2. **`multiSelect: true`** : toggle (espace) puis `Entrée`, pas un chiffre unique.
3. **Option « Other » ajoutée automatiquement** par le harness (toujours présente, hors `options[]`) :
   position dans le menu ? touche ?
4. **N questions** : posées séquentiellement → séquence de frappes, pas une seule.

### Cas « pas d'options extractibles »

`questions` absent/vide, ou `options` vide/illisible → pas de boutons → **dégrade en focus** (US10). Le
`TranscriptReader` étant déjà défensif (tout optionnel, ligne illisible ignorée), l'extension suit le même
principe : un champ manquant ne casse jamais l'extraction.

### Permissions escaladées (arme #29)

**Constat** : sur les transcripts island, les seuls `tool_use` orientés utilisateur sont `AskUserQuestion`
(20×) ; **aucun** `tool_use` de permission, **aucun** menu numéroté de permission dans le JSONL. Les prompts
de permission sont une interaction **niveau TUI**, signalée à l'Island via le hook Notification
(`waitingForUser(message:)`), **pas** via des options structurées dans le transcript.

→ **Pour #29, la source des options de permission n'est pas le JSONL.** Piste : menu fixe (allow / allow &
don't ask / deny) reconstruit côté Island, ou autre signal à identifier en #29. Satisfait le critère « source
identifiée, ou explicitement à revoir en #29 ».

---

## Reco concrète

**Ciblage (a)** — pour rapprocher une fenêtre Ghostty d'une Session :
1. lire `Session.cwd` (déjà dans le Store) ;
2. énumérer `AXWindows` de **toutes** les instances `com.mitchellh.ghostty` ;
3. `matches = { w | normaliser(AXDocument(w)) == normaliser(Session.cwd) }` ;
4. `matches.count == 1` → **cible certaine** (injection autorisée) ; sinon → **incertain → Click-to-focus**.

**Extraction (b)** — pour une Session « en attente » (au moment de `.waitingForUser`) :
1. lire le dernier `tool_use name=="AskUserQuestion"` dans le tail JSONL (extension défensive du `TranscriptReader`) ;
2. en tirer `question` + `options[]` ordonnées ; mapping option→touche = l'index ;
3. si extraction vide → pas de boutons → focus. La frappe physique exacte se cale en #26/#27 sur la TUI.

**Permissions (a/b)** — même chemin d'injection, mais **options reconstruites côté Island** (pas le transcript) → #29.

### Quand ça dégrade (résumé)

- 0 ou ≥ 2 fenêtres au cwd de la Session → focus (jamais de frappe).
- Pas d'options extractibles (texte libre, `questions` vide) → focus.
- Permission Accessibilité absente (`island.app` pas encore autorisé) → affichage + focus (onboarding #28).
- Split/onglet masquant le cwd → au pire « incertain » → focus.

## Impact sur les tranches

- **#26 (affichage)** : lit le format (b) figé ci-dessus ; gère N-questions + « pas d'options » ; le mapping
  physique de touche est un point à trancher côté TUI.
- **#27 (injection)** : garde d'unicité (a) + `AXRaise`+`CGEvent` ; **FP sur `island.app` uniquement**, cible jetable.
- **#28 (onboarding)** : détecter `AXIsProcessTrusted() == false`, guider vers Réglages Système ; par binaire.
- **#29 (permissions)** : source des options **hors transcript** — à concevoir.

## Décisions (validées par Loïc, 2026-07-19)

1. **Ciblage par `AXDocument` + gate d'unicité** : **validé, figé** dans l'ADR-0006.
2. **Injection prouvée seulement sur `island.app`** (jamais l'instance vivante) : **acté** (garde-fou capitalisé
   dans `docs/agents/agentic-driving.md`).
3. **Format (b)** validé, figé dans l'ADR-0006.
4. **Collision de numéro d'ADR : résolue** — l'ADR d'injection a été renuméroté en
   `0006-reponse-par-injection-ciblee.md` sur `epic/22` (PRD #23 réaligné, plus aucune réf « 0005 ») ; `0005`
   reste l'ADR de packaging sur `develop`. La décision du spike est figée par **mise à jour de l'ADR-0006**.

_Reste à trancher en #26 (hors périmètre spike)_ : sur une invocation à **N questions**, comportement
d'affichage (1ʳᵉ question / empiler / dégrader) ; et la **frappe physique** exacte du sélecteur TUI
(chiffre vs flèches, `multiSelect`, « Other ») à caler sur la TUI vivante.

## Annexe — fixtures réelles (à déposer sous `Tests/` après feu vert)

- **Multi-questions + `multiSelect`** : `~/.claude/projects/-Users-loic-Documents-island/5a23c630-…jsonl`, ligne 84.
- **Question simple, 3 options** : même fichier, ligne 400.
- Prototypes AX jetables (lecture seule) : `ax_probe.swift`, `ax_target.swift` (énumération + gate d'unicité)
  dans le scratchpad de session — non versionnés (exploratoires).

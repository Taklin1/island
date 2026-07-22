# Capture #81 — ground truth AX des fenêtres/onglets Ghostty (unicité `AXDocument`)

> Issue #81 · ADR-0009 (§ Spike #25, § Résolution #81) · discipline
> `docs/agents/agentic-driving.md` § « Injection de frappe : JAMAIS sur l'instance vivante ».
> Capture du 2026-07-20, outil jetable **lecture seule** (`ax_capture_81.swift`, scratchpad,
> non versionné : uniquement `AXUIElementCopyAttributeNames`/`CopyAttributeValue` — aucun
> `CGEvent`, aucun `AXRaise`, aucun `activate`). 110 snapshots sur ~10 min, dont une
> topologie préparée par le mainteneur : **≥ 2 fenêtres Ghostty + ≥ 2 onglets d'une même
> fenêtre, tous sur LE MÊME cwd `~/Documents/island`**, Space Ghostty actif, clics
> d'onglets pendant la rafale.

## Verdicts

**V1 — `AXWindows` ne voit que le Space courant.** Ghostty sur un autre Space
(Brave frontmost) → `AXWindows` = **0 fenêtre**, alors que `CGWindowListCopyWindowInfo`
(`.optionAll`) recense au même instant **66 fenêtres CG Ghostty** (`onscreen=false`,
une par onglet). La cible d'une Session dont le Space n'est pas affiché est donc
**invisible au verdict** → `uncertain` → dégrade (comportement sûr, mais à acter).

**V2 — un onglet d'arrière-plan n'existe pas pour l'AX.** La fenêtre à onglets
n'expose **aucun** `AXTabGroup` et ses onglets n'apparaissent **pas** comme
`AXWindows` distinctes : sur toute la capture, Ghostty actif expose **UNE seule
`AXWindow` lisible** — la fenêtre-clé — dont `AXTitle`/`AXDocument` **suivent
l'onglet visible** (titres observés changeant au fil des clics d'onglets :
`⠐ Implémenter la livraison fiable…#81`, `~/Documents/island`,
`✳ Fix workflow status…`, `✳ Implémenter issue #77…`, `👻`…).

**V3 — une autre fenêtre présente peut être illisible.** Pendant la topologie
2-fenêtres, la seconde fenêtre n'apparaît que par intermittence, avec **tous les
attributs illisibles** (`document=nil`, `title=""`) — elle ne compte jamais comme
« match » dans le verdict d'unicité.

Extrait représentatif (topologie 2 fenêtres + 2 onglets, même cwd) :

```json
"windows": [
  { "index": 0, "document": null, "title": "", "main": null },
  { "index": 1, "document": "file:///Users/loic/Documents/island/",
    "main": true, "focused": false,
    "title": "⠐ Implémenter la livraison fiable de frappe vers Island (#81)" }
]
```

NB : `AXFocused` est resté `false` sur la fenêtre-clé **même Ghostty actif** —
`AXMain` (`true`) est le signal fiable de « fenêtre-clé », pas `AXFocused`.

## Implications pour la garde d'unicité (ADR-0009)

1. **Le verdict « certain » du gate #77 était structurellement affaibli** : sur un
   cwd porté par plusieurs onglets/fenêtres, l'énumération ne voyait que l'onglet
   visible → 1 match → « certain », alors que d'autres terminaux au même cwd
   existaient, cachés. « Exactement une fenêtre au cwd » signifie en réalité
   « **l'onglet visible de la fenêtre-clé est au cwd** » — rien de plus.
2. La démonstration 8 fenêtres / 3 projets du spike #25 reste valable pour des
   fenêtres **non-fullscreen visibles d'un même Space** (elles exposent chacune leur
   `AXDocument` et l'unicité dégrade correctement, cas akutia = 4). L'angle mort
   est : **onglets d'arrière-plan** et **fenêtres d'autres Spaces**.
3. Aucune API en lecture ne permet d'énumérer le cwd des onglets cachés (ni AX,
   ni CGWindowList — les titres CG sont la tâche Claude, pas le cwd). L'ambiguïté
   « plusieurs terminaux au même cwd » ne peut donc être détectée **que côté
   Island** : plusieurs **Sessions vivantes** partageant le cwd = ambigu → dégrade.
   Le résiduel (un shell nu caché au même cwd) reste indétectable — à acter.

## Hypothèse de livraison (pourquoi la frappe se perd)

- Secure Keyboard Entry **inactif** au moment de la capture (aucun `SecureInput`
  dans `ioreg`) — pas la cause.
- Le clic sur le panneau island (NSPanel non-activant) peut prendre le **key
  focus** sans activer l'app : un `CGEvent` posté en `.cghidEventTap` suit le
  routage clavier global → il atterrit dans le **panneau island** (qui l'ignore),
  pas dans Ghostty pourtant « frontmost ». Cohérent avec les deux repros (aucun
  caractère nulle part, aucune fuite). `app.activate()` ne rend pas le key focus
  au terminal de façon synchrone, et `NSWorkspace.frontmostApplication` ne
  détecte pas cette situation (activation et key focus sont séparables).
- Un routage `CGEvent.postToPid(pid Ghostty)` livre dans la file d'événements de
  Ghostty **indépendamment du key focus global**, vers sa fenêtre-clé — celle-là
  même que le verdict vient de vérifier. À trancher au gate HITL (Résolution #81).

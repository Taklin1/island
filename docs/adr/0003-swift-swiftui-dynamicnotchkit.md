# Swift + SwiftUI + DynamicNotchKit pour l'Island

> **Statut (2026-07-19)** : le choix Swift/SwiftUI + DynamicNotchKit **vendoré** reste en vigueur. En revanche la décision d'y **forcer le style `.notch`** (Island toujours visible — dernière phrase des _Consequences_) est **remplacée par [ADR-0007](0007-island-flottante-masquee-par-defaut.md)** : l'Island passe en style `.floating`, **masquée par défaut**.

App native Swift/SwiftUI. Le rendu de l'Island s'appuie sur DynamicNotchKit (MIT) : panneau flottant, animations expand/collapse, fallback natif pour les Macs sans encoche — la machine cible (MacBook Air M1) n'en a pas, l'Island est donc toujours flottante top-center.

## Considered Options

- **Electron/Tauri** : rejeté — lourd, animations moins fluides, subtilités macOS (non-activation, overlay fullscreen) pénibles.
- **NSPanel from scratch** : rejeté — les trois apps de référence l'ont toutes fait et ont réinventé les mêmes edge cases (multi-écrans, Spaces, fullscreen) ; DynamicNotchKit les couvre.

## Consequences

DynamicNotchKit est **vendoré** dans `Vendor/DynamicNotchKit` (copie MIT patchée) plutôt que tiré par `.package(url:)`. Raison vérifiée (#4) : les Command Line Tools seuls n'embarquent pas les plugins de macros SwiftUI (`@Entry`, `#Preview`), sans lesquels l'upstream ne compile pas ; la copie vendorée retire ces usages. Revenir à l'URL upstream dès qu'un Xcode complet est installé sur la machine de build. Le mode `.notch` est forcé explicitement : le style `floating` de la lib masque le panneau en état compact sur un Mac sans encoche (sans ce choix, aucune Island visible).

### Patchs du vendoré (à réconcilier au retour vers l'URL upstream)

- **Macros SwiftUI retirées** (`@Entry`, `#Preview`) — cf. ci-dessus (#4).
- **First mouse sur le contenu du panneau** (#33) : le panneau est un `.nonactivatingPanel` (pour ne jamais voler le focus au terminal), ce qui a un effet de bord — quand l'app de l'Island n'est pas active, macOS avale le premier `mouseDown` (ordering de fenêtre) et le `.onTapGesture` d'une carte ne réagit qu'au **second** clic. Correctif : le contenu SwiftUI est monté dans un `FirstMouseHostingView` (sous-classe de `NSHostingView` qui surcharge `acceptsFirstMouse(for:) -> true`), au lieu d'un `NSHostingView` nu. Le premier clic atteint alors le contenu **sans** rendre le panneau activant : l'Island ne devient jamais l'app active, et la chaîne click-to-focus (`cardActivated → focusTerminal → Ghostty`, #10) part dès le premier coup. Fichiers : `Utility/DynamicNotchPanel.swift` (la sous-classe) et `DynamicNotch/DynamicNotch.swift` (`initializeWindow`, un seul point de montage). Garde-fou : `Tests/IslandUITests/FirstMouseTests.swift`.
- **`.fullScreenAuxiliary` sur le panneau** (#103) : ajouté au `collectionBehavior` du panneau (`Utility/DynamicNotchPanel.swift`) pour qu'il rejoigne le Space d'une app plein écran — sans lui, `.canJoinAllSpaces` seul n'y atteint jamais et ni Peek ni Révélation n'apparaissent au-dessus du plein écran (le Liseré, qui a le flag, le prouve). Vérifié absent d'upstream 1.1.0 (dernier tag) et `main`. Garde-fou : `Tests/DynamicNotchKitTests/DynamicNotchPanelTests.swift`, hors gate racine — `swift test --package-path Vendor/DynamicNotchKit`.
- **`hide()` ne fuit jamais sa continuation** (#131) : dans `DynamicNotch/DynamicNotch.swift`, les gardes d'annulation de `closePanelTask` sortaient sans appeler le `completion` — un `expand()`/`compact()` qui annule un `hide()` en vol (ou un `hide()` qui en remplace un autre) laissait `await hide()` suspendu pour toujours (`SWIFT TASK CONTINUATION MISUSE`, la course du cross-fade du Peek, observée à l'instrumentation de la PR #104). Correctif : `defer { completion?() }` en tête de la task — le completion tire sur TOUS les chemins de sortie ; sur les chemins annulés la fenêtre n'est délibérément PAS dé-initialisée (l'annuleur la réutilise ou la reconstruit), le teardown nominal est inchangé. Garde-fou : `Tests/DynamicNotchKitTests/DynamicNotchHideContinuationTests.swift`, hors gate racine — `swift test --package-path Vendor/DynamicNotchKit`.

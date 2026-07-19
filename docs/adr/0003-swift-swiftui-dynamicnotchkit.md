# Swift + SwiftUI + DynamicNotchKit pour l'Island

App native Swift/SwiftUI. Le rendu de l'Island s'appuie sur DynamicNotchKit (MIT) : panneau flottant, animations expand/collapse, fallback natif pour les Macs sans encoche — la machine cible (MacBook Air M1) n'en a pas, l'Island est donc toujours flottante top-center.

## Considered Options

- **Electron/Tauri** : rejeté — lourd, animations moins fluides, subtilités macOS (non-activation, overlay fullscreen) pénibles.
- **NSPanel from scratch** : rejeté — les trois apps de référence l'ont toutes fait et ont réinventé les mêmes edge cases (multi-écrans, Spaces, fullscreen) ; DynamicNotchKit les couvre.

## Consequences

DynamicNotchKit est **vendoré** dans `Vendor/DynamicNotchKit` (copie MIT patchée) plutôt que tiré par `.package(url:)`. Raison vérifiée (#4) : les Command Line Tools seuls n'embarquent pas les plugins de macros SwiftUI (`@Entry`, `#Preview`), sans lesquels l'upstream ne compile pas ; la copie vendorée retire ces usages. Revenir à l'URL upstream dès qu'un Xcode complet est installé sur la machine de build. Le mode `.notch` est forcé explicitement : le style `floating` de la lib masque le panneau en état compact sur un Mac sans encoche (sans ce choix, aucune Island visible).

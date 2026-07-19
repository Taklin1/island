# Swift + SwiftUI + DynamicNotchKit pour l'Island

App native Swift/SwiftUI. Le rendu de l'Island s'appuie sur DynamicNotchKit (MIT) : panneau flottant, animations expand/collapse, fallback natif pour les Macs sans encoche — la machine cible (MacBook Air M1) n'en a pas, l'Island est donc toujours flottante top-center.

## Considered Options

- **Electron/Tauri** : rejeté — lourd, animations moins fluides, subtilités macOS (non-activation, overlay fullscreen) pénibles.
- **NSPanel from scratch** : rejeté — les trois apps de référence l'ont toutes fait et ont réinventé les mêmes edge cases (multi-écrans, Spaces, fullscreen) ; DynamicNotchKit les couvre.

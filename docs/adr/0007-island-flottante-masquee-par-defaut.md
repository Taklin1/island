# Island flottante masquée par défaut (Mac sans encoche)

L'Island passe du style DynamicNotchKit `.notch` **forcé + toujours visible**
(ADR-0003) au style **`.floating` masqué par défaut** : au repos, rien n'est
affiché ; l'Island ne sort que pour un **Peek** transitoire (~2,5 s à un
Événement marquant) ou sur **Révélation** à la demande (curseur poussé contre le
bord haut, bande centrée ~280 pt près de la webcam). La persistance de
l'attention reste portée par le **Liseré** (bords d'écran), pas par l'Island. Le
choix Swift/SwiftUI + DynamicNotchKit vendoré (ADR-0003) est inchangé — seuls le
style et le mode de repos changent. Cible : Mac **sans encoche** (aucune machine
à encoche dans le projet aujourd'hui ; le repo devient public). Issu du grill de
#41 (Loïc, 2026-07-19).

## Considered Options

- **Garder `.notch` forcé, barre toujours visible** (ADR-0003) : rejeté. Sur un
  Mac sans encoche, la micro-barre stationne en permanence au top-center — lourde
  pour un simple suivi de sessions, sans l'ancrage physique d'une encoche qui la
  justifierait. « Léger, caché quand rien ne se passe » prime.
- **Double-mode auto-détecté** (`.notch` natif si encoche, `.floating` sinon, via
  `NSScreen.safeAreaInsets`) : rejeté pour l'instant. Double la surface de rendu
  et de test pour un cas (encoche) que personne n'a dans le projet. Noté comme
  évolution possible ; réversible.
- **Rangée ambiante minimale pendant le travail** (petit Sprite persistant au
  centre) : rejeté. Casse le « repos = vide ». La présence permanente « un peu
  mignonne » passe par l'**Icône animée** de la barre des menus, optionnelle.

## Consequences

- **`.compact()` = masqué.** En style `.floating`, DynamicNotchKit fait `hide()`
  sur `compact()` (`DynamicNotch.swift`). `CompactLeadingView` /
  `CompactTrailingView` (rangée de Sprites + logo) ne sont plus jamais rendues :
  code mort à retirer. Les Sprites survivent dans le Peek et les cartes.
- **Révélation = moniteur global de souris.** Le survol natif de DynamicNotchKit
  est gardé `state != .hidden` : hors caché, pas de fenêtre à survoler. « Monter
  la souris pour sortir l'Island » exige donc un moniteur global (`NSEvent`) sur
  la bande top-center, actif en permanence, qui appelle `expand()`. Bord franc
  (curseur à y≈0) plutôt que bande épaisse : geste délibéré, quasi zéro faux
  positif ; rien si zéro Session.
- **Plein écran couvert.** Le panneau (niveau `.screenSaver`) comme le Liseré
  (`.statusBar`) portent `.canJoinAllSpaces` + `.fullScreenAuxiliary` : Peek,
  Révélation et Liseré s'affichent par-dessus une app plein écran (cas d'usage
  principal : coder en plein écran). C'est `.fullScreenAuxiliary` qui autorise à
  rejoindre le Space plein écran — le niveau et `.canJoinAllSpaces` seuls n'y
  suffisent pas ; le panneau ne l'a gagné qu'avec #103 (le Liseré l'avait déjà).
  La Révélation coexiste avec la barre des menus qui se révèle au même geste
  (centre de la barre vide).
- **Acquittement redéfini.** Sans barre toujours-visible, « survoler = acquitter
  tout » disparaît : regarder ≠ traiter. On acquitte **une Session à la fois** en
  agissant (clic carte → click-to-focus #10, ou refocus terminal) ; le Liseré
  d'une Session reste allumé tant qu'elle n'est pas traitée — sûr en
  multi-sessions. Met à jour la définition d'« Acquittement » (CONTEXT.md).
- **Icône animée (barre des menus).** L'icône d'app existante devient une mascotte
  agrégée, priorité **waiting > terminé > working > idle** (même langage que le
  Liseré et le Peek), une seule mascotte (pas de badge compteur), idle qui dort,
  affichage optionnel (réglage). macOS ne permet pas de centrer un `NSStatusItem` :
  « centré près de la webcam » impliquerait notre propre overlay, écarté au profit
  de l'icône native à droite.
- **Retombées doc.** ADR-0003 partiellement remplacé (statut mis à jour) ; #32
  (« afficher le titre dans le Compact ») à revoir, le Compact étant retiré.

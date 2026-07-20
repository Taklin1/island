# Changelog

Toutes les versions notables d'island. Format : une ligne dense par version, la plus récente en haut.
Seul l'orchestrateur d'epic écrit ici (bump `0.x.y` + une ligne par issue mergée lors de la réconciliation) ; les agents d'implémentation n'y touchent jamais.

## 0.1.26

- #91 Détection de mise à jour : verdict pur (`UpdateCheckGate`, comparaison sémantique) sur l'API GitHub Releases via seam `UpdateFetcher` (fixtures réelles capturées), item de menu muté en place (« island vX.Y.Z — à jour » ↔ « ⬆ Mettre à jour vers vY.Z… ») + « Vérifier les mises à jour… », UNE notification macOS par version (persistée) ; un build `-dev` ne propose jamais rien, hors-ligne silencieux, surfaces Sessions intactes ; clic no-op tracé (branché en #92). (Épic #85, PR #97.)

## 0.1.25

- #89 Canal d'installation : `scripts/install.sh`, one-liner `curl … | sh` qui installe/met à jour island depuis la dernière GitHub Release (asset `island.zip` en URL directe, sans quarantaine ni Gatekeeper, remplacement à chaud sans double process, idempotent — c'est aussi le futur updater). FP prouvé sur le vrai canal, repo passé en public (prérequis ADR-0010). (Épic #85, PR #96.)

## 0.1.24

- #88 Version embarquée : builds locaux packagés en `X.Y.Z-dev` (`--release` pour la version nue, futur usage CI), trace `island: version …` au lancement et version affichée en tête du menu de la barre des menus ; repli `0.0.0-dev` pour le binaire SwiftPM nu — socle de la garde « un build `-dev` ne se met jamais à jour » (ADR-0010, épic #85, PR #95).

## 0.1.23

- #70 Une Session « en attente » n'expose plus d'outil en cours : le cas `.waitingForUser` de `SessionStore.apply` remet `session.currentTool = nil` à l'entrée **effective** en attente (dans la garde `state != .ended`, non-régression #31), supprimant le libellé « outil : … » fantôme qui restait au-dessus de la question/message quand un `PreToolUse` précédait la `Notification`. Vaut pour les questions comme pour les permissions. (Épopée #22.)

## 0.1.22

- #29 Réponse depuis l'Island étendue aux **prompts de permission escaladés** (auto-mode) — **affichage seul, pas d'injection** : leurs options ne sont extractibles nulle part (absentes du JSONL ; `notification_type == "permission_prompt"` ne distingue pas permission et question ; menu-fixe deviné **rejeté** car il frapperait potentiellement « allow-always », décision de sécurité persistante — US7). La carte en attente **sans boutons** surface donc le message humain de la `Notification` (« Claude needs your permission to use Bash ») via `Session.waitingMessage` (posé/vidé en miroir de `pendingQuestion`, marqueur de trace `+msg`) ; le clic dégrade en Click-to-focus, aucune décision auto. La moitié « injection de permission » reste reportée, figée dans **ADR-0009 § « Résolution #29 »** ; `CONTEXT.md` clarifié. (Épopée #22.)

## 0.1.21

- #28 Onboarding Accessibilité + préférence on/off de la **Réponse depuis l'Island** : le gate pur `AnswerFromIslandGate.action(featureEnabled:permissionGranted:onboardingAlreadyPrompted:)` décide `inject` (feature on ∧ permission accordée) vs `displayAndFocus(guideToSettings:)` — off ou permission absente ⇒ affichage + Click-to-focus, guidage vers Réglages Système au **premier** usage seulement (jamais bloquant, jamais de nag). #26 rend les boutons quoi qu'il arrive ; seule l'injection consulte le gate. Kept AppKit-free (testable sans toucher la TCC). (Épopée #22, ADR-0009.)

## 0.1.20

- #27 **Injection ciblée** de la frappe depuis l'Island (ADR-0009) : un clic sur une option injecte sa frappe (`optionIndex+1` + Entrée en `CGEvent`) dans le terminal Ghostty de **cette** Session **uniquement** si la garde d'unicité (`GhosttyWindowTargeting` : exactement une fenêtre dont l'`AXDocument` = `Session.cwd`) est certaine — sinon dégrade proprement en Click-to-focus, jamais de frappe dans le mauvais terminal (US4). Retour visuel optimiste (`resumeAfterAnswer` : Session « en cours », option envoyée, Liseré éteint via l'Acquittement existant, US11) ; sans clic, aucune décision (US7). Les APIs réelles (AX/`CGEvent`) vivent dans le seul seam `TerminalResponder.live`, exercé uniquement par la FP HITL sur `island.app` (jamais l'instance vivante — spike #25). (Épopée #22.)

## 0.1.19

- #26 **Extraction des options d'`AskUserQuestion`** et boutons dans la carte Étendue : `TranscriptReader.pendingQuestion` lit défensivement le dernier `tool_use` `AskUserQuestion` non répondu du transcript (format figé par le spike #25 : `input.questions[]`, `options[]` ordonnées, l'index = la touche 1/2/3), porté par `.waitingForUser` jusqu'à `Session.pendingQuestion` ; la carte affiche le libellé + un bouton par option. Dégrade (pas de boutons) sur permission/texte libre, N>1 questions, options vides ou question déjà répondue (US10). Le bloc question évince le Résumé du tour. (Épopée #22.)

## 0.1.18

- #43 Panneau Étendu **défilable** et **plafonné** à ~1/4 de la hauteur d'écran : `SessionCardsView` enveloppe sa liste dans une `ScrollView(.vertical)` (scrollers macOS standards, pas d'indicateur permanent) et borne sa hauteur via la fonction pure `SessionCardsView.cappedHeight(contentHeight:screenHeight:)` = `min(contenu, 0,25 × NSScreen.frame.height)` — bien sous la borne vendorée demi-écran (non patchée). Sous le plafond : hauteur intrinsèque mesurée par `GeometryReader` (pas d'espace vide à 1–2 Sessions) ; au-delà : le surplus défile, toutes les cartes atteignables. Le défilement ne rend jamais le panneau actif (`.nonactivatingPanel` / `FirstMouseHostingView` #33 préservés). (Épopée #46.)

## 0.1.17

- #44 Panneau Étendu : cartes triées par **Priorité d'état** (waiting > terminé > working > idle), départage par récence *par groupe* (`waiting` = plus ancien d'abord contre l'oubli, terminé/working/idle = plus frais d'abord), ordre déterministe (départage final par `id`, donc pas de sautillement) et réordonnancement animé. Le rang est **centralisé** dans `SessionState.priorityRank` (source unique) et consommé aussi par le choix du Peek (`mostPressingForPeek`) et l'Icône animée (`SpriteAnimation.menuBarMascot`) — fin des copies inline. Terme « Priorité d'état » ajouté au glossaire `CONTEXT.md`. (Épopée #46.)

## 0.1.16

- #60 Durcit le recede de la Révélation (ADR-0007) : l'Étendu se déployant *autour* du curseur au bord haut, aucun `mouseEntered` natif ne se produit, si bien qu'un curseur repartant sans survoler le panneau le laissait ouvert. Ajout d'un repli **géométrique** — fonction pure `IslandController.shouldRecede(at:in:)` interrogée par le moniteur souris global (coquille mince) qui arme, une seule fois, le même recede anti-clignotement quand l'Étendu est ouvert et le panneau non survolé. Hystérésis (bande recede 340 > bande révélation 280, profondeur de maintien 220 pt couvrant le panneau) : l'oscillation brève au bord ne clignote pas ; le survol natif `isHovering` reste l'autorité, nominal intact. (Épopée #41.)

## 0.1.15

- #55 Peek « spritey » + retrait du mode Compact mort (ADR-0007) : le clin d'œil transitoire affiche désormais le **Sprite** de la Session concernée (son animation encode l'état — check vert terminé, `?` clignotant en attente, via `IslandController.peekAnimation(for:)`) à côté du texte, et reste **cliquable** (click-to-focus #10). `CompactLeadingView` / `CompactTrailingView` et toute la machinerie devenue morte avec le `.floating` (`compactSprites`/`compactTone`/`CompactSprite`/`CompactTone`/`spritesTrace`) sont **supprimés** — `DynamicNotch` sans slots compacts (`EmptyView`), aucune référence morte. Les Sprites restent inchangés dans les cartes de l'Étendu. (Épopée #41.)

## 0.1.14

- #53 Island flottante masquée par défaut (`.floating`, ADR-0007) : au repos, plus rien à l'écran même quand des Sessions travaillent — l'ancien Compact toujours-visible est abandonné. Machine à 3 états Masqué / Peek / Étendu dans `IslandController`. **Révélation** par geste « bord franc » : un moniteur souris global `NSEvent` (coquille mince) délègue toute la décision à la fonction pure `IslandController.shouldReveal(at:in:sessionCount:)` — curseur plaqué au bord haut ∧ bande centrée ~280 pt (webcam) ∧ ≥1 Session — puis déploie l'Étendu (une carte par Session), maintenu ouvert par le hover `.keepVisible` et refermé au départ du curseur avec un délai de grâce anti-clignotement. Peek transitoire ~2,5 s puis retour Masqué. **Acquittement redéfini** : révéler ou survoler l'Island n'acquitte plus rien (regarder ≠ traiter) ; seuls le clic sur une carte (click-to-focus #10) et le refocus terminal acquittent, une Session à la fois. (Épopée #41.)

## 0.1.13

- #54 Icône animée dans la barre des menus : l'`NSStatusItem` porte une mascotte pixel-art unique animée sur timer, reflétant l'état agrégé le plus pressant sur toutes les Sessions (waiting > terminé > working > idle, via la fonction pure `SpriteAnimation.menuBarMascot(for:)` qui ne compte que les waiting/ended non acquittées) ; une seule mascotte, jamais de badge ; à vide ou tout acquitté elle dort. Réglage « Afficher l'Icône animée » persisté (ON par défaut) : quand off, repli sur une icône statique neutre, le menu (préférences / réinstaller-hooks / quitter) restant toujours accessible. (Épopée #41, ADR-0007.)

## 0.1.12

- #48 Une Session reste « en cours » tant qu'un Sous-agent `Agent` (background, même `session_id`, distingué par `agent_id`) tourne : le compte des Sous-agents vivants est lu directement dans le tableau `background_tasks` du hook `Stop` (entrées `type == "subagent"`, `id` non vide) — décision au Stop, sans course ni flash vert et sans tic d'horloge (chaque complétion de Sous-agent réinjecte un tour ⇒ nouveau `Stop` qui ré-évalue). La question l'emporte toujours (`?` ⇒ orange immédiat, même Sous-agent actif). Compte discret « ⋯ N sous-agents en cours » sur la carte Étendue. Supprime le compteur mort et la complétion différée de #31. (ADR-0008 amendé : gate `background_tasks` au lieu du timeout ; capture ciblée du fil réel.)

## 0.1.11

- #39 Un tour finissant sur une question (« ? ») est classé « attend » (Liseré orange, glyphe « ? », question au Peek) au lieu de « terminé » : détection sur le texte final autoritaire `last_assistant_message` (robuste au lag du transcript de Claude Code au `Stop`). Un sous-agent `Agent` en arrière-plan (session distincte) n'altère pas ce classement — ses hooks portent un `agent_id` et sont écartés, le parent se résout sur son propre `Stop`. (ADR-0006 ; lag capitalisé en ADR-0002.)

## 0.1.10

- #32 La carte Étendue affiche le titre de session Claude Code en haut (chemin du projet en dessous) ; le renommage manuel `/rename` (`custom-title`) prime sur le titre auto-généré (`ai-title`), reflété au prochain Événement et à l'ouverture Étendue (survol) ; repli sur le nom du dossier.

## 0.1.9

- #31 Fiabilise l'état des Sessions en temps réel : une notification d'inactivité ne crée plus de faux « attend » ni ne ressuscite un tour terminé (whitelist de blocage + repli sur le texte) ; le suivi des sous-agents (`SubagentStart`/`Stop`, compteur sur la Session parente) empêche d'afficher « terminée » tant qu'un sous-agent tourne, la fin de tour n'étant actée qu'au dernier sous-agent arrêté — même si son `Stop` arrive après le `Stop` principal.

## 0.1.8

- #33 Réparé le click-to-focus : le premier clic sur une carte (ou le Peek) ramène Ghostty au premier plan du premier coup, même quand l'Island n'est pas l'app active — via `acceptsFirstMouse` sur le contenu du panneau vendoré non-activant, sans jamais rendre l'Island activante (ciblage de la fenêtre/onglet exact = v1.5, suivi en #36).

## 0.1.7

- #11 Sprites pixel-art animés par Session (planche « Bots » + logo île + glyphes d'état des cartes Étendues, sheets embarquées, moteur SpriteView, mapping états → animations, teintes #8 portées par le Sprite).

## 0.1.6

- #8 État « attend » et Liseré avec Acquittement : hook Notification → Session « attend », Liseré plein écran click-through sur tous les Spaces et par-dessus le fullscreen (orange = attend prioritaire sur vert = terminé, persistant jusqu'à Acquittement — survol, focus terminal observé, ou clic sur carte), Peek à l'entrée en attente, Compact teinté, préférence Liseré respectée en live.
- #10 Click-to-focus : clic sur une carte ou le Peek → activation du terminal via NSWorkspace (bundle id Ghostty, repli launch par nom) sans activer l'island, le clic vaut Acquittement ; champ terminal de l'Événement (défaut ghostty par l'Adaptateur seul, ADR-0004), modules IslandGlow/IslandFocus.

## 0.1.5

- #9 Quotas via tee de la statusline : endpoint dédié du Serveur local, QuotaStore (jauges 5 h/7 j + reset, % contexte par Session, masquées sans rate_limits), tee opt-in dans le script statusline (bloc marqué inséré après input=$(cat), curl fire-and-forget, backup horodaté, idempotent, opt-out restauration byte-exacte), jauges + % contexte dans la vue Étendue.

## 0.1.4

- #7 Résumé par extraction locale du transcript (ADR-0002) : au Stop, TranscriptReader lit la fin du transcript JSONL (défensif, sidechains exclues, plafond 4 Mo, repli « état + projet » garanti) et publie le Résumé — première ligne dans le Peek, détail (message, todos, fichiers, durée) dans la carte Étendue.

## 0.1.3

- #6 Installation automatique des hooks Claude Code au premier lancement (merge additif préservant les hooks tiers, backup horodaté, idempotent, désinstallation propre, fix curl stdin en arrière-plan) + cycle de vie : icône barre de menu (préférences Liseré/Son, login item SMAppService, réinstaller/désinstaller les hooks, quitter).

## 0.1.2

- #5 Sessions vivantes : machine à états complète (start/prompt/outils/stop/end, resume sans doublon, TTL orphelines 30 min, sous-agents ignorés), Island Compacte à une entrée par Session et cartes Étendues au survol (projet, état, prompt, outil, durée), mises à jour UI throttlées (200 ms).

## 0.1.1

- #4 Tracer bullet : hook Stop → Peek — serveur local HTTP (41414, token 0600), adaptateur Claude Code (Stop, SubagentStop ignoré), SessionStore minimal, Island Compacte + Peek DynamicNotchKit (vendoré patché CLT), hook manuel documenté au README.

## 0.1.0

- Bootstrap repo, skills du workflow adaptés à island (git-flow, versioning orchestrateur-seul, vérif locale `swift build`/`swift test`, tests agentiques via API d'événements).

# Changelog

Toutes les versions notables d'island. Format : une ligne dense par version, la plus récente en haut.
Seul l'orchestrateur d'epic écrit ici (bump `0.x.y` + une ligne par issue mergée lors de la réconciliation) ; les agents d'implémentation n'y touchent jamais.

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

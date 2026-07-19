# Changelog

Toutes les versions notables d'island. Format : une ligne dense par version, la plus récente en haut.
Seul l'orchestrateur d'epic écrit ici (bump `0.x.y` + une ligne par issue mergée lors de la réconciliation) ; les agents d'implémentation n'y touchent jamais.

## 0.1.3

- #6 Installation automatique des hooks Claude Code au premier lancement (merge additif préservant les hooks tiers, backup horodaté, idempotent, désinstallation propre, fix curl stdin en arrière-plan) + cycle de vie : icône barre de menu (préférences Liseré/Son, login item SMAppService, réinstaller/désinstaller les hooks, quitter).

## 0.1.2

- #5 Sessions vivantes : machine à états complète (start/prompt/outils/stop/end, resume sans doublon, TTL orphelines 30 min, sous-agents ignorés), Island Compacte à une entrée par Session et cartes Étendues au survol (projet, état, prompt, outil, durée), mises à jour UI throttlées (200 ms).

## 0.1.1

- #4 Tracer bullet : hook Stop → Peek — serveur local HTTP (41414, token 0600), adaptateur Claude Code (Stop, SubagentStop ignoré), SessionStore minimal, Island Compacte + Peek DynamicNotchKit (vendoré patché CLT), hook manuel documenté au README.

## 0.1.0

- Bootstrap repo, skills du workflow adaptés à island (git-flow, versioning orchestrateur-seul, vérif locale `swift build`/`swift test`, tests agentiques via API d'événements).

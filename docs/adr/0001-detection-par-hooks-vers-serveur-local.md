# Détection par hooks Claude Code vers un serveur HTTP local

L'app apprend l'état des Sessions via les hooks Claude Code (Stop, Notification, SessionStart/End, Pre/PostToolUse, PermissionRequest) qui POSTent vers un Serveur local HTTP embarqué, authentifié par un token fichier (0600). Le transcript JSONL (`~/.claude/projects/`) n'est lu qu'en source secondaire, au moment d'un Événement, pour en extraire le Résumé.

## Considered Options

- **Watch des transcripts seul** : rejeté — format non documenté, détection de fin par heuristique d'inactivité, fragile.
- **Wrapper autour du CLI** : rejeté — casse à chaque mise à jour, complique l'installation.
- Le pattern hooks→serveur local est celui des trois apps de référence (agent-island en HTTP :31415, VibeHub en socket Unix, vibeisland.app).

## Consequences

Les hooks sont installés dans `~/.claude/settings.json` par l'app au premier lancement, en préservant les hooks existants (pixel-agents). Le hook doit avoir un timeout court et ne jamais bloquer Claude Code si l'app ne tourne pas — sauf usage délibéré de la réponse bloquante (allow/deny de PermissionRequest, v1.5).

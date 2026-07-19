# Schéma d'Événements générique, Adaptateur Claude Code seul en v1

Le Serveur local définit un schéma d'Événements générique (session, état, résumé, cwd, terminal, agent) indépendant de Claude Code ; les hooks Claude Code ne sont qu'un Adaptateur parmi d'autres possibles. La v1 ne livre que cet Adaptateur, mais l'UI et le store ne connaissent que le schéma générique — brancher Codex/Cursor plus tard ne touche pas l'UI.

Corollaire de périmètre : tout ce qui est spécifique à Claude Code (format des hooks, statusline, transcripts) vit dans l'Adaptateur, jamais au-delà.

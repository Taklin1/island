# Résumé par extraction locale, sans appel LLM

Le Résumé affiché à la fin d'un tour est extrait localement du transcript JSONL (dernier message assistant, état des todos, fichiers modifiés, durée), jamais généré par un appel LLM. Le dernier message de Claude est déjà un TLDR dans la grande majorité des cas ; l'extraction est instantanée, gratuite et hors-ligne, là où un appel `claude -p` coûterait 2-5 s de latence et du quota.

Aucune des trois apps de référence ne produit de résumé « fait / état / suite » : c'est le différenciateur du projet, et il repose entièrement sur cette extraction.

## Consequences

Le format du transcript n'est pas documenté : le parseur doit être défensif, et en cas d'échec de parse la notification part quand même (état + nom du projet, sans Résumé). Un enrichissement LLM optionnel reste possible plus tard sans casser ce chemin.

**Le transcript LAG au `Stop` — pour le dernier message assistant, lire le champ hook `last_assistant_message`, pas le fichier.** Les docs officielles Claude Code préviennent : au `Stop`, « the transcript file might not yet include the current turn's most recent messages », et recommandent d'utiliser `last_assistant_message` de la charge utile du hook pour le texte final du tour. L'Adaptateur prend donc ce champ (verbatim, sans course) comme source du **texte** du dernier message — il prime sur le texte extrait du transcript (qui peut être périmé) ; le transcript ne fournit plus que les faits structurés (todos, fichiers, durée) et sert de repli sur les vieilles versions sans le champ. Piège vérifié : le FP de #39 (classer « attend » un tour finissant sur « ? ») ratait en réel — la détection lisait un transcript périmé (dernier message = l'avant-dernier, sans « ? ») → vert au lieu d'orange. Verrouillé par les tests de régression `questionDetectedFromPayloadWhenTranscriptLags` (Adaptateur) et `laggingTranscriptStillPublishesWaitingViaPayload` (bout-en-bout serveur).

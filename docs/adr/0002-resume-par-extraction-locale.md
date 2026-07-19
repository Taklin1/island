# Résumé par extraction locale, sans appel LLM

Le Résumé affiché à la fin d'un tour est extrait localement du transcript JSONL (dernier message assistant, état des todos, fichiers modifiés, durée), jamais généré par un appel LLM. Le dernier message de Claude est déjà un TLDR dans la grande majorité des cas ; l'extraction est instantanée, gratuite et hors-ligne, là où un appel `claude -p` coûterait 2-5 s de latence et du quota.

Aucune des trois apps de référence ne produit de résumé « fait / état / suite » : c'est le différenciateur du projet, et il repose entièrement sur cette extraction.

## Consequences

Le format du transcript n'est pas documenté : le parseur doit être défensif, et en cas d'échec de parse la notification part quand même (état + nom du projet, sans Résumé). Un enrichissement LLM optionnel reste possible plus tard sans casser ce chemin.

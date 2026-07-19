# Island

App macOS qui affiche l'état des sessions Claude Code dans une interface flottante façon Dynamic Island, et rattrape l'attention quand un agent a fini ou attend une réponse.

## Language

**Island** :
Le panneau flottant en haut-centre de l'écran, **masqué par défaut** : il ne se montre que sur Peek ou Révélation. Distinct du Liseré (bords de l'écran) et de l'Icône animée (barre des menus).
_Avoid_ : notch, encoche, widget

**Session** :
Une conversation Claude Code vivante (un `session_id` des hooks), rattachée à un projet (cwd) et à un terminal.
_Avoid_ : agent (réservé à l'acteur qui produit le travail), conversation

**Événement** :
Fait typé reçu par le Serveur local (hook ou statusline) qui fait évoluer l'état d'une Session : démarrée, en cours, terminée, en attente, fermée.
_Avoid_ : notification (réservé aux notifications macOS), message

**Adaptateur** :
Composant qui traduit les événements bruts d'un outil agent (v1 : les hooks Claude Code) vers le schéma d'Événements générique.

**Serveur local** :
Serveur HTTP embarqué dans l'app, sur 127.0.0.1, seul point d'entrée des Événements.

**Masqué** :
État de repos de l'Island : rien à l'écran. Une Session qui ne fait que travailler n'affiche rien ; seuls un Peek ou une Révélation en sortent l'Island (ADR-0007, remplace le mode « Compact » toujours-visible d'ADR-0003).
_Avoid_ : compact, micro-barre

**Étendu** :
Mode de l'Island après Révélation : une carte par Session (projet, dernier prompt, Résumé, badges, quotas). Se replie (retour à Masqué) quand le curseur quitte le panneau (petit délai de grâce anti-clignotement).

**Révélation** :
Geste qui sort l'Island de l'état Masqué à la demande : pousser le curseur contre le bord haut de l'écran (« bord franc »), dans une bande centrée ~280 pt près de la webcam. Ne se déclenche que s'il existe ≥1 Session, à tout moment (repos comme attente), plein écran compris. N'acquitte rien.
_Avoid_ : survol (ambigu), hover

**Peek** :
Sortie automatique de l'Island ~2-3 s à l'arrivée d'un Événement marquant (montre le Sprite de la Session concernée), puis retour à Masqué. Transitoire : la persistance de l'attention est portée par le Liseré, pas par le Peek.
_Avoid_ : toast, popup

**Sprite** :
Mascotte pixel-art animée représentant une Session, affichée dans le Peek et les cartes (Étendu) ; son animation encode l'état (travaille, dort, fini, question).

**Icône animée** :
Mascotte pixel-art unique dans la barre des menus (à droite, `NSStatusItem` — macOS ne permet pas le centre), reflétant l'état agrégé le plus pressant sur toutes les Sessions : waiting > terminé > working > idle. Idle (zéro Session ou tout acquitté) = mascotte qui dort. Affichage optionnel (réglage Island).

**Liseré** :
Contour lumineux dessiné sur les bords de l'écran tant qu'un Événement marquant n'est pas Acquitté. Orange : une Session attend une réponse. Vert : une Session a terminé.
_Avoid_ : glow, halo, bordure

**Acquittement** :
Action utilisateur qui éteint le Liseré d'une Session, **une Session à la fois** : cliquer sa carte (click-to-focus) ou refocaliser son terminal. Révéler ou survoler l'Island n'acquitte rien (regarder ≠ traiter).

**Résumé** :
Ce que l'Island affiche d'un tour terminé : extrait local du transcript (dernier message assistant, todos, fichiers modifiés). Jamais généré par un appel LLM.

**Quotas** :
Jauges d'usage Claude (fenêtres 5 h et 7 jours, % de contexte) reçues via le tee de la statusline.

**Click-to-focus** :
Action de cliquer une carte de Session pour ramener le focus sur son terminal (Ghostty).

# Island

App macOS qui affiche l'état des sessions Claude Code dans une interface flottante façon Dynamic Island, et rattrape l'attention quand un agent a fini ou attend une réponse.

## Language

**Island** :
Le panneau flottant en haut-centre de l'écran, **masqué par défaut** : il ne se montre que sur Peek ou Révélation. Distinct du Liseré (bords de l'écran) et de l'Icône animée (barre des menus).
_Avoid_ : notch, encoche, widget

**Session** :
Une conversation Claude Code vivante (un `session_id` des hooks), rattachée à un projet (cwd) et à un terminal. Peut porter plusieurs agents à la fois : l'agent principal (hooks à `agent_id` vide) et un ou plusieurs Sous-agents.
_Avoid_ : agent (réservé à l'acteur qui produit le travail), conversation

**Sous-agent** :
Un acteur secondaire travaillant sous la MÊME Session que l'agent principal — même `session_id`, distingué par un `agent_id` propre (p. ex. l'outil `Agent`). Il ne crée **pas** de Session ni de carte à lui. Sa seule empreinte sur l'Island : tant qu'au moins un Sous-agent tourne, la Session reste « en cours » (jamais « terminée »).
_Avoid_ : session (réservé au `session_id`), agent (l'acteur générique)

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
Mode de l'Island après Révélation : les jauges de Quotas en tête du panneau (premier élément visible à l'ouverture, défilent avec la liste), puis une carte par Session (projet, dernier prompt, Résumé, badges), triées par **Priorité d'état**. Se replie (retour à Masqué) quand le curseur quitte le panneau (petit délai de grâce anti-clignotement).

**Priorité d'état** :
Ordre de « pressant » des états d'une Session : **waiting > terminé > working > idle**. Critère unique partagé par l'Icône animée, le Liseré, le Peek et la liste Étendue (source unique `SessionState.priorityRank`, jamais recopié). Dans la liste Étendue, départage à rang égal par récence *par groupe* : `waiting` = plus ancien d'abord (anti-oubli), `terminé`/`working`/`idle` = plus frais d'abord ; ordre déterministe (départage final par id) donc pas de sautillement au rafraîchissement.

**Révélation** :
Geste qui sort l'Island de l'état Masqué à la demande : pousser le curseur contre le bord haut de l'écran (« bord franc »), dans une bande centrée ~280 pt près de la webcam. Ne se déclenche que s'il existe ≥1 Session, à tout moment (repos comme attente), plein écran compris. N'acquitte rien.
_Avoid_ : survol (ambigu), hover

**Peek** :
Sortie automatique de l'Island ~2-3 s à l'arrivée d'un Événement marquant (montre le Sprite de la Session concernée), puis retour à Masqué. Transitoire : la persistance de l'attention est portée par le Liseré, pas par le Peek.
_Avoid_ : toast, popup

**Sprite** :
Mascotte pixel-art animée représentant une Session, affichée dans le Peek et les cartes (Étendu) ; son animation encode l'état (travaille, dort, fini, question).

**Icône animée** :
Mascotte pixel-art unique dans la barre des menus (à droite, `NSStatusItem` — macOS ne permet pas le centre), reflétant l'état agrégé le plus pressant sur toutes les Sessions selon la **Priorité d'état** (waiting > terminé > working > idle), les waiting/terminé n'y pesant que tant qu'ils ne sont pas Acquittés. Idle (zéro Session ou tout acquitté) = mascotte qui dort. Affichage optionnel (réglage Island).

**Liseré** :
Contour lumineux dessiné sur les bords de l'écran tant qu'un Événement marquant n'est pas Acquitté. Orange : une Session attend une réponse. Vert : une Session a terminé.
_Avoid_ : glow, halo, bordure

**Acquittement** :
Action utilisateur qui éteint le Liseré d'une Session, **une Session à la fois** : cliquer sa carte (click-to-focus) ou refocaliser son terminal. Révéler ou survoler l'Island n'acquitte rien (regarder ≠ traiter).

**Résumé** :
Ce que l'Island affiche d'un tour terminé : extrait local du transcript (dernier message assistant, todos, fichiers modifiés). Jamais généré par un appel LLM.

**Titre de session** :
Le titre Claude Code d'une Session, affiché en haut de sa carte Étendue (le chemin du projet en dessous). Extrait localement du transcript, jamais généré par un appel LLM. Deux enregistrements JSONL DISTINCTS (vérifié sur de vrais transcripts) : `custom-title` (champ `customTitle`) = renommage manuel via `/rename`, qui PRIME toujours ; `ai-title` (champ `aiTitle`) = titre auto-généré, jamais modifié par un `/rename`. Résolution : dernier `custom-title` sinon dernier `ai-title` sinon repli sur le nom du dossier. Relu à chaque Événement et à l'ouverture Étendue — `/rename` n'émet pas de hook, donc un renommage sur une Session au repos n'apparaît qu'au survol. (NB : l'énoncé initial de l'issue #32 — « `/rename` écrit un nouvel `ai-title` » — était faux ; c'est un `custom-title`.)
_Avoid_ : nom de session, label

**Quotas** :
Jauges d'usage Claude (fenêtres 5 h et 7 jours, % de contexte) reçues via le tee de la statusline.

**Click-to-focus** :
Action de cliquer une carte de Session pour ramener le focus sur son terminal (Ghostty).

**Réponse depuis l'Island** :
Débloquer une Session « en attente » sans quitter l'Island, en injectant la frappe correspondant à l'**option d'une question** (`AskUserQuestion`) choisie dans le terminal de cette Session. **Débrayable** par un réglage du menu (défaut **on**, c'est la valeur de la feature) : off → affichage seul, le clic dégrade en Click-to-focus, aucune Injection. Requiert la **permission Accessibilité** (accordée par binaire) ; sans elle, la feature **dégrade en affichage + focus** et guide vers Réglages Système au premier usage (jamais bloquant, ADR-0009). NB : `AXIsProcessTrusted()` peut rester obsolète tant qu'`island.app` n'est pas relancée après l'octroi. **Prompt de permission escaladé** (auto-mode, rare) : ses options ne sont extractibles nulle part que l'Island puisse lire (spike #25 / ADR-0009 « Résolution #29 ») → **ni boutons ni Injection** ; l'Island **surface le message** de la permission sur la carte (affichage seul) et le clic dégrade en Click-to-focus — aucune décision de sécurité automatique (US7).
_Avoid_ : réponse inline, quick reply

**Injection** :
Envoi d'une frappe clavier au terminal d'une Session via l'API Accessibilité, effectué uniquement quand la fenêtre/onglet de cette Session est identifiée avec certitude.
_Avoid_ : automation, simulation clavier

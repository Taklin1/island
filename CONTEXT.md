# Island

App macOS qui affiche l'état des sessions Claude Code dans une interface flottante façon Dynamic Island, et rattrape l'attention quand un agent a fini ou attend une réponse.

## Language

**Island** :
L'interface flottante en haut-centre de l'écran, seule surface d'affichage de l'app.
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

**Compact** :
Mode par défaut de l'Island : micro-barre avec un Sprite par Session et un statut court. Ne s'étend jamais sans survol ou Peek.

**Étendu** :
Mode de l'Island au survol : une carte par Session (projet, dernier prompt, Résumé, badges, quotas).

**Peek** :
Expansion partielle automatique de 2-3 secondes à l'arrivée d'un Événement marquant, puis retour au Compact.
_Avoid_ : toast, popup

**Sprite** :
Mascotte pixel-art animée représentant une Session dans le mode Compact ; son animation encode l'état (travaille, dort, fini, question).

**Liseré** :
Contour lumineux dessiné sur les bords de l'écran tant qu'un Événement marquant n'est pas Acquitté. Orange : une Session attend une réponse. Vert : une Session a terminé.
_Avoid_ : glow, halo, bordure

**Acquittement** :
Action utilisateur qui éteint le Liseré et le Peek associés à une Session : survoler l'Island ou refocaliser le terminal de la Session.

**Résumé** :
Ce que l'Island affiche d'un tour terminé : extrait local du transcript (dernier message assistant, todos, fichiers modifiés). Jamais généré par un appel LLM.

**Titre de session** :
Le titre Claude Code d'une Session, affiché en haut de sa carte Étendue (le chemin du projet en dessous). Extrait localement du transcript, jamais généré par un appel LLM. Deux enregistrements JSONL DISTINCTS (vérifié sur de vrais transcripts) : `custom-title` (champ `customTitle`) = renommage manuel via `/rename`, qui PRIME toujours ; `ai-title` (champ `aiTitle`) = titre auto-généré, jamais modifié par un `/rename`. Résolution : dernier `custom-title` sinon dernier `ai-title` sinon repli sur le nom du dossier. Relu à chaque Événement et à l'ouverture Étendue — `/rename` n'émet pas de hook, donc un renommage sur une Session au repos n'apparaît qu'au survol. (NB : l'énoncé initial de l'issue #32 — « `/rename` écrit un nouvel `ai-title` » — était faux ; c'est un `custom-title`.)
_Avoid_ : nom de session, label

**Quotas** :
Jauges d'usage Claude (fenêtres 5 h et 7 jours, % de contexte) reçues via le tee de la statusline.

**Click-to-focus** :
Action de cliquer une carte de Session pour ramener le focus sur son terminal (Ghostty).

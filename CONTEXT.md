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
Geste qui sort l'Island de l'état Masqué à la demande : un **appui** du curseur contre le bord haut de l'écran (« bord franc »), maintenu un court instant dans une bande centrée ~280 pt près de la webcam — un simple passage du curseur dans la bande ne révèle pas. Après un repli, la Révélation ne se ré-arme qu'une fois le curseur reparti du bord haut (pas de redéploiement en rafale). Ne se déclenche que s'il existe ≥1 Session, à tout moment (repos comme attente), plein écran compris. N'acquitte rien.
_Avoid_ : survol (ambigu), hover, passage

**Peek** :
Sortie automatique de l'Island ~2-3 s à l'arrivée d'un Événement marquant (montre le Sprite de la Session concernée), puis retour à Masqué. Transitoire : la persistance de l'attention est portée par le Liseré, pas par le Peek.
_Avoid_ : toast, popup

**Annonce** :
Le fait, pour une Session, de surfacer un Événement marquant (Peek, notification macOS, Liseré). Une annonce (Session, état) déjà faite ne se **ré-annonce** pas : seuls un Acquittement ou un nouveau tour réel de cette Session (nouveau prompt utilisateur) la réarment. Une bascule du gate Sous-agents ou une réémission identique (hooks/statusline) ne constituent jamais une nouvelle Annonce — la persistance de l'attention est portée par le Liseré, pas par la répétition.
_Avoid_ : rappel, re-notification

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

**Canal d'installation** :
Le chemin officiel par lequel island s'installe : un script une-ligne exécuté au terminal (`curl … | sh`) qui installe la dernière Release GitHub — jamais un téléchargement navigateur mis en avant (ADR-0010). La Release (zip taggé `vX.Y.Z` sur `main`, fabriqué par la CI) est la forme téléchargeable de la prod ; `main` est sa base de vérité.
_Avoid_ : .dmg, App Store, download page

**Mise à jour** :
Remplacement d'island.app installée par la dernière Release, déclenché par un clic explicite de l'utilisateur (item du menu barre des menus « Mettre à jour vers vY.Z… », signalé par une notification macOS unique par version) et exécuté par le même script que le Canal d'installation. Jamais silencieuse, jamais montrée sur les surfaces Sessions (cartes, Peek, Liseré) ; un build de dev local (`-dev`) ne se met jamais à jour.
_Avoid_ : auto-update silencieux, upgrade

**Click-to-focus** :
Action de cliquer une carte de Session pour ramener le focus sur son terminal (Ghostty) : la **fenêtre exacte** de la Session quand elle est une Cible certaine (une seule fenêtre au cwd de la Session — même verdict d'unicité que l'Injection, sans ses gardes supplémentaires : aucune frappe en jeu, une erreur de fenêtre est bénigne), sinon l'app entière comme avant. Le ciblage fenêtre requiert la permission Accessibilité mais reste **indépendant du réglage Injection** (qui ne gouverne que les frappes) ; sans permission, le clic focus l'app immédiatement et guide une fois vers Réglages Système (latch d'onboarding **partagé** avec l'Injection — un seul guidage pour toute l'app, jamais bloquant). Limites héritées de l'Accessibilité (capture #81) : fenêtre dans un autre Space ou Session dans un onglet caché → cible incertaine → app entière.

**Réponse depuis l'Island** :
Débloquer une Session « en attente » sans quitter l'Island, en injectant la frappe correspondant à l'**option d'une question** (`AskUserQuestion`) choisie dans le terminal de cette Session. **Débrayable** par un réglage du menu (défaut **on**, c'est la valeur de la feature) : off → affichage seul, le clic dégrade en Click-to-focus, aucune Injection. Requiert la **permission Accessibilité** (accordée par binaire) ; sans elle, la feature **dégrade en affichage + focus** et guide vers Réglages Système au premier usage (jamais bloquant, ADR-0009). NB : `AXIsProcessTrusted()` peut rester obsolète tant qu'`island.app` n'est pas relancée après l'octroi. **Prompt de permission escaladé** (auto-mode, rare) : ses options ne sont extractibles nulle part que l'Island puisse lire (spike #25 / ADR-0009 « Résolution #29 ») → **ni boutons ni Injection** ; l'Island **surface le message** de la permission sur la carte (affichage seul) et le clic dégrade en Click-to-focus — aucune décision de sécurité automatique (US7).
_Avoid_ : réponse inline, quick reply

**Injection** :
Envoi d'une frappe clavier au terminal d'une Session, effectué uniquement quand la fenêtre/onglet de cette Session est identifiée avec certitude ET re-vérifiée à l'instant de l'envoi (fenêtre visible au cwd de la Session, instance active), routé au pid Ghostty (`postToPid`, jamais « l'app focalisée ») — une frappe ne peut ni se perdre dans le panneau ni fuir vers une autre app (ADR-0009 § Résolution #81). La cible n'est vérifiable que si son onglet est VISIBLE : depuis un autre onglet/fenêtre/Space, le clic dégrade en Click-to-focus, sans frappe.
_Avoid_ : automation, simulation clavier

## Totem

**Totem** :
Seconde Surface, physique : un petit objet posé sur le bureau (écran tactile) qui reflète l'état agrégé des Sessions selon la **Priorité d'état**, les compteurs par état et les **Quotas**. Afficheur pur : il n'Acquitte jamais, ne répond jamais, n'envoie rien à l'app ; le toucher n'y sert qu'à la navigation locale. Jamais de texte de Session (Résumé, prompt, Titre, options). Distinct de l'Island (panneau macOS).
_Avoid_ : mini island, gadget, widget, notch, écran, afficheur

**Halo** :
Contour lumineux du Totem, miroir du Liseré : orange tant qu'une Session attend, vert tant qu'une Session a terminé sans Acquittement, éteint sinon. S'éteint uniquement par l'Acquittement fait sur le Mac. Suit l'attention non acquittée **même si le Liseré est désactivé** sur le Mac (le réglage ne concerne que l'écran du Mac) : c'est la couleur que le Liseré aurait s'il était activé. Respire lentement (anti-brûlure AMOLED), sans jamais clignoter sur un Instantané.
_Avoid_ : liseré (réservé aux bords de l'écran Mac), glow

**Instantané** :
L'état agrégé (Priorité d'état, compteurs, Quotas) que l'app pousse au Totem à chaque changement et en battement régulier. Ne porte que des états et des pourcentages, jamais d'Événement ni de contenu de Session. Les compteurs sont l'état **brut** de chaque Session (une Session en attente acquittée compte en attente) ; seul l'état agrégé tient compte de l'Acquittement. Pas de % de contexte en v1 (il est rangé par Session). Le reset 5 h n'est affiché que comme un compte à rebours : le Totem n'a ni heure ni fuseau.
_Avoid_ : événement (réservé à l'entrée), snapshot, payload

**Relais** :
Composant de l'app qui pousse l'Instantané au Totem. Seule voie sortante d'island ; distinct de l'Adaptateur et du Serveur local, qui sont des entrées.
_Avoid_ : serveur, bridge, sync

**Déconnecté** :
État du Totem quand aucun Instantané n'est arrivé depuis un court délai (app fermée, réseau tombé) : mascotte endormie grise, Halo éteint, jauges estompées. Un Totem ne montre jamais un Halo périmé.
_Avoid_ : hors-ligne, erreur

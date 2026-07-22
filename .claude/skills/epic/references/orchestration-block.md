# Bloc ORCHESTRATION (verbatim, à insérer dans chaque prompt d'agent)

> Placeholder : `{BASE}` = branche epic (`epic/<n>-<slug>`). Le reste s'insère tel quel,
> juste après la ligne « Tâche : ... » du gabarit /prompt.

```
ORCHESTRATION (tu es un sous-agent d'une session orchestratrice ; adaptations NON-NÉGOCIABLES) :
(a) tu travailles dans un worktree git isolé : `swift build` et `swift test` tournent tels
quels dedans (chaque worktree a son propre `.build` ; la première compilation résout les
dépendances SwiftPM, laisse-la finir). ATTENTION : le worktree peut démarrer sur un commit
bootstrap SANS `Sources/` — vérifie-le d'abord (`ls Sources/`), et si l'arbre du projet
manque, rebranche ta feature depuis la base : `git checkout -b feature/<n>-<slug>
origin/{BASE}` avant tout code (base = la branche epic, qui contient le code déjà mergé) ;
(b) ta branche part de {BASE} et ta PR cible {BASE} - jamais develop, jamais main ;
(c) INTERDIT de modifier le champ de version du projet et `CHANGELOG.md` : propose ta ligne
de changelog dans le body de la PR (section « Changelog proposé »), l'orchestrateur réconcilie
au merge ;
(d) vérif locale AVANT push = `swift build` && `swift test` verts, plus le parcours de
feature (FP) de ton issue via /agentic-tests. C'est tout : pas de lint ni de CI configuré sur
island - ne suppose ni n'invente d'autre gate ;
(e) le rendu SwiftUI se vérifie visuellement (screenshots), pas en XCUITest ; l'état des
Sessions se teste par l'API locale d'événements (POST de fixtures JSON hooks -> asserter les
Sessions publiées) ;
(f) si une décision produit non tranchée ou un blocage survient : NE DEVINE PAS, arrête-toi
et termine ta réponse par un bloc « QUESTION: » (contexte, options, ta recommandation) -
la réponse de Loic te sera renvoyée et tu reprendras avec ton contexte intact ;
(g) termine ta réponse finale par : numéro de PR, branche, résumé en 3 lignes, ligne de
changelog proposée, résultats des tests (TDD/FP/swift build/swift test).
```

## Pourquoi chaque règle

Leçons génériques de flotte (héritées d'orchestrations multiagent, à ré-éprouver sur island) :

| Règle | Raison |
|---|---|
| (b) cible {BASE} | develop ne bouge qu'à la PR finale ; une PR qui vise develop court-circuite le gate humain unique |
| (c) fichiers réservés | N PR parallèles = conflits garantis sur version/CHANGELOG ; 0 conflit quand seul l'orchestrateur y touche au merge |
| (d) vérif locale bornée | la seule vérif de dev sur island = `swift build` + `swift test` (+ FP) ; inventer un gate CI/lint fait perdre du temps sur une PR |
| (e) rendu visuel | pas de XCUITest : la sortie SwiftUI se juge à l'œil, l'état des Sessions par l'API d'événements locale |
| (f) protocole QUESTION | le sous-agent n'a AUCUN canal direct vers Loic ; deviner = reprise coûteuse |

# Totem : afficheur pur, périmètre agrégé, jamais d'Acquittement

Le Totem (objet de bureau ESP32-C6 AMOLED 2,16") n'affiche que l'état agrégé des Sessions (Priorité d'état, compteurs par état), le Halo (miroir du Liseré) et les Quotas. Il n'Acquitte jamais, ne porte pas la Réponse depuis l'Island (ADR-0009) et n'a aucun canal vers l'app. Issu du grill de #154 (Loïc, 2026-09-07).

## Considered Options

- **Cartes / liste de Sessions avec Résumé ou Titre** : rejeté. Illisible sur 2,16" et duplique l'Étendu ; le Totem n'est pas une seconde Island.
- **Toucher = acquitte tout** : rejeté. Le périmètre agrégé n'identifie aucune Session ; un acquittement en bloc réintroduit le « survoler = tout acquitter » écarté par ADR-0007 (regarder ≠ traiter, une Session à la fois).
- **Toucher = Click-to-focus de la Session la plus pressante** : rejeté pour l'instant. Exige un canal Totem → app et une cible vérifiée ; réversible si le besoin apparaît.
- **Réponse au toucher** : rejeté. ADR-0009 repose sur des options affichées et une cible re-vérifiée à l'instant du post ; le Totem n'a ni l'un ni l'autre.
- **Peek sur le Totem** : rejeté. L'Annonce y est portée par le Halo et la mascotte ; l'Instantané n'a donc pas à transporter d'Événement.

## Consequences

- Aucun contenu de Session ne quitte le Mac : l'Instantané ne contient que des états et des pourcentages.
- Le firmware n'a qu'un serveur HTTP entrant ; rien sur le LAN ne peut agir sur un terminal.
- Le toucher ne sert qu'à la navigation locale (pages, luminosité).

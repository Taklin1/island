# Relais : push HTTP sur le LAN de l'app vers le Totem, Serveur local inchangé

L'app pousse l'Instantané au Totem par un POST HTTP en clair sur le LAN (adresse du Totem et token partagé en réglage), à chaque changement d'état agrégé ou de Quotas et en battement régulier (~10 s) ; à la fermeture propre, un Instantané vide. Le Totem refuse tout Instantané sans token et passe en Déconnecté sans Instantané depuis ~30 s. Le Serveur local reste sur 127.0.0.1, entrée seule : ADR-0001 est intact, le Relais est une voie sortante distincte. Issu du grill de #154 (Loïc, 2026-09-07).

## Considered Options

- **Pull HTTP : le Totem interroge l'app** : rejeté. Impose d'ouvrir le Serveur local sur le LAN, d'ajouter une route GET et d'exposer son token à l'objet — ADR-0001 (127.0.0.1, ingress) serait touché pour un gain nul.
- **BLE GATT (voie Clawdmeter)** : rejeté. CoreBluetooth dans l'app, appairage, modèle tiré par caractéristiques ; Clawdmeter le fait parce que son daemon Python n'est pas une app native — island a déjà un store et un Mac connecté au même LAN.
- **Série USB** : rejeté. Câble permanent ; contredit « objet posé ».
- **TLS** : rejeté. Hors de portée raisonnable de l'objet, contenu sans secret (états, pourcentages).
- **Push sur changement seul, sans battement** : rejeté. Halo fantôme indéfini si l'app meurt ; le battement borne la péremption.

## Consequences

- Nouveau composant `Relais` côté app, alimenté par le store (état agrégé + Quotas), jamais par les hooks directement.
- Le contrat = une fixture JSON versionnée, encodée par `swift test` et décodée par le test firmware (ADR-0015).
- Wi-Fi requis côté Totem ; l'adresse est un réglage, pas de découverte réseau en v1.

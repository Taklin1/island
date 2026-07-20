# Distribuer et mettre à jour island sans notarisation : canal terminal + certificat auto-signé stable

island est distribuée **sans compte Apple Developer** (app gratuite, pas de notarisation) : l'installation officielle est un **script une-ligne** (`curl -fsSL <install.sh> | sh`) qui télécharge le zip de la dernière **GitHub Release** — fabriquée par la CI au push d'un tag `vX.Y.Z` sur `main` — et l'installe dans `~/Applications`. La mise à jour est le **même script**, exécuté par l'app elle-même sur clic d'un item de menu (« Mettre à jour vers vY.Z… »), après détection via l'API GitHub Releases. Les binaires de release sont signés par un **certificat auto-signé stable** (secret CI), pas en ad-hoc.

## Pourquoi ça marche sans notarisation

Gatekeeper ne vérifie que les fichiers portant l'attribut `com.apple.quarantine`, posé par les applications de téléchargement (navigateurs). **`curl` ne le pose pas**, ni les téléchargements `URLSession` de l'app : le parcours terminal ne rencontre jamais Gatekeeper — c'est le mécanisme (identique au build local, qui n'a jamais eu l'attribut) qu'utilisent les installeurs d'outils dev. Le téléchargement manuel du zip dans un navigateur reste possible mais n'est pas le canal mis en avant.

## Considered Options

- **Compte Apple Developer + notarisation + Sparkle** : la voie canonique des apps macOS distribuées — rejetée : 99 $/an pour une app gratuite, et le public d'island (utilisateurs de Claude Code) vit dans le terminal ; le canal curl leur est naturel.
- **Distribution .dmg/.zip par navigateur, friction Gatekeeper documentée** (clic droit → Ouvrir) : rejetée comme canal principal — friction durcie sur les macOS récents, première impression dégradée, et inutile puisque le canal terminal la contourne proprement.
- **Signature ad-hoc en CI** (statu quo du packaging local, ADR-0005) : rejetée pour les releases — la permission **Accessibilité est liée à l'identité de signature** ; une signature ad-hoc change à chaque build, donc chaque mise à jour ferait perdre la permission et casserait la Réponse depuis l'Island. Le certificat auto-signé stable donne une identité constante entre versions. *(L'ad-hoc reste le mode du packaging local de dev, ADR-0005 inchangé pour ce cas.)*
- **Mise à jour silencieuse** : rejetée — une app qui détient Accessibilité et injecte des frappes ne se remplace pas sans consentement explicite. Une seule notification macOS par nouvelle version + item de menu ; le clic déclenche.

## Consequences

- **Le certificat est un engagement** : en changer plus tard fait perdre la permission Accessibilité à tous les utilisateurs installés (re-octroi manuel général). Sa stabilité est validée par un **spike bloquant** avant toute release publique (permission conservée entre deux builds signés du même certificat ?).
- Le tag `vX.Y.Z` sur `main` est **le geste de release** ; la CI vérifie tag == version en tête de `CHANGELOG.md` (source de vérité existante, lue par `package_app.sh`). La règle « seul l'orchestrateur d'epic bump la version » (CLAUDE.md) est inchangée.
- Prérequis : **repo public** (API Releases sans auth, runner macOS gratuit, script auditable avant pipe — standard du genre).
- Un build **non-CI** (dev local, version suffixée `-dev`) ne propose et n'applique **jamais** de mise à jour — il s'écraserait avec la prod. Coexistence develop/main en local par alternance manuelle (port 41414 unique).
- La mise à jour se montre **uniquement** dans le menu barre des menus (+ une notification macOS) — jamais sur les surfaces Sessions (cartes, Peek, Liseré), qui restent sémantiquement réservées aux agents.
- Remplacement à chaud assumé : l'état en mémoire se repeuple au fil des hooks ; une Session « en attente » redevient invisible jusqu'à son prochain événement (limite documentée ; garde douce possible plus tard).
- URL courte (`taklin.dev/install.sh`) greffable à tout moment : l'URL n'est qu'une porte d'entrée vers le script versionné dans le repo.

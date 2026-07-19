# Empaquetage en `.app` ad-hoc pour usage personnel local

island tourne chez Loïc, en local. On l'empaquette dans un vrai bundle
`island.app` signé **ad-hoc** (`codesign -s -`), installé dans `~/Applications`
(sans sudo), via le script répétable `scripts/package_app.sh`. Pas de
notarisation, pas de Developer ID, pas de DMG ni d'App Store. Un bundle est
**nécessaire** (le binaire SwiftPM nu ne suffit pas) : `SMAppService` (login
item, issue #6) exige un `.app` avec un `Info.plist` et un identifiant stables,
et `LSUIElement=true` fait de l'app une accessory (pas d'icône Dock, aligné sur
`setActivationPolicy(.accessory)` de `main.swift`).

## Considered Options

- **Binaire SwiftPM nu** (`.build/release/Island`) : rejeté — `SMAppService.register()`
  renvoie `Invalid argument` (pas de bundle), donc pas de login item ; pas
  d'icône, pas de cycle de vie propre. C'est la limitation connue de #6.
- **Notarisation / Developer ID / DMG** : hors périmètre — usage perso local,
  aucune distribution. La signature ad-hoc suffit : une app construite localement
  n'a pas de quarantine, donc aucun blocage Gatekeeper à l'ouverture.

## Consequences

- **Version** : `CFBundleShortVersionString` repris du haut de `CHANGELOG.md`
  (source unique). Bundle id `com.taklin.island`. Pas de sandbox : l'app lit
  `~/.claude` et, plus tard (#22), utilisera l'Accessibilité.
- **Piège vérifié — placement de la resource bundle vs codesign.** L'accessor
  `Bundle.module` généré par SwiftPM résout la resource bundle à la **racine** du
  `.app` (`Bundle.main.bundleURL/Island_IslandUI.bundle`), mais `codesign` refuse
  tout contenu à la racine d'un bundle (`unsealed contents present in the bundle
  root`) — même un symlink. On place donc la resource bundle dans
  `Contents/Resources/` (seul emplacement signable) et `IslandUI` la résout
  côté code (`SpriteSheet.resourceURL` : `Bundle.main.resourceURL` d'abord, repli
  `Bundle.module` pour le dev/les tests). Sans ce repli, l'app packagée
  `fatalError` au lancement (l'accessor ne regarde jamais `Contents/Resources`).
  Couvert par `SpriteTests` (résolution des sheets en contexte test) et par le FP
  (sprites visibles dans l'app packagée) ; non simulable en pur test unitaire,
  car `Bundle.main` y est `xctest`.
- **Login item : limitation #6 levée.** Depuis le `.app` installé,
  `SMAppService.mainApp.register()` réussit (trace `island: login item
  registered`, entrée BTM `com.taklin.island → ~/Applications/island.app` visible
  via `sfltool dumpbtm`). L'app démarre à la connexion ; ses préférences vivent
  dans le domaine `defaults` `com.taklin.island` (et non plus `Island` du binaire
  nu).
- **Icône** : `.icns` généré depuis le sprite `isle` (même dessin que le logo
  Island) par `scripts/generate_icon.py`, committé dans `packaging/island.icns`.

# Spike #87 — Certificat auto-signé stable : la permission Accessibilité survit au remplacement

> Epic #85 · PRD #86 · ADR-0010 (distribution sans notarisation) · ADR-0005 (ad-hoc = mode dev).
> Spike HITL du 2026-07-21 (macOS Darwin 25.2.0) — builds jetables, aucun code de production
> touché. Gestes Réglages Système par le mainteneur ; tout le reste scripté et rejouable.

## Verdict (2026-07-21)

**La promesse de l'epic TIENT.** La permission Accessibilité (TCC) accordée à `island.app`
signée du certificat auto-signé stable `island-release` **survit au remplacement complet**
de `~/Applications/island.app` par un build différent signé du **même** certificat —
trace `island: accessibility permission granted` à la relance, **sans aucun re-octroi**.

**Contraste ad-hoc confirmé** : entre deux builds ad-hoc (`codesign -s -`) au contenu
différent, la permission est **perdue** (trace `absent`) — chaque build ad-hoc a un CDHash
donc une identité TCC différente. La décision ADR-0010 (cert stable pour les releases,
ad-hoc réservé au dev local) est validée ; pas de re-triage de l'epic.

Preuves chiffrées (SHA-256 du binaire `Contents/MacOS/island`) :

| Build | Signature | Binaire | Trace à la relance | Geste mainteneur |
|---|---|---|---|---|
| A | `island-release` | `2660ca66…` | `absent` (post-reset TCC) puis `granted` | octroi initial (ajout dans Réglages) |
| B | `island-release` | `c4c6f3e2…` (≠ A) | **`granted`** | **aucun** ← le verdict |
| C | ad-hoc `-` | `3a478781…` | `absent` (identité changée) puis `granted` | suppression + ré-ajout (le toggle ne suffit pas, cf. pièges) |
| D | ad-hoc `-` | C + marqueur Info.plist (CDHash ≠) | **`absent`** | — (constat : perte) |
| B (final) | `island-release` | `c4c6f3e2…` | `absent` puis `granted` | suppression + ré-ajout final |

État final laissé en place : build B (`island-release`) installé dans `~/Applications`,
permission accordée — les prochains builds signés `island-release` la conservent.

## Contrat livré à #90 (noms FIGÉS)

Secrets GitHub posés sur `Taklin1/island` (`gh secret list` en fait foi, 2026-07-21) :

- **`ISLAND_CERT_P12`** — le fichier `.p12` (clé privée + certificat) **encodé base64**,
  exporté au format **legacy** (voir pièges : indispensable pour `security import`).
- **`ISLAND_CERT_P12_PASSWORD`** — le mot de passe du `.p12` (généré `openssl rand -base64 24`).

Identité à passer à `codesign -s` : **`island-release`** (le Common Name).
Empreinte SHA-1 : `39FF511D998AFF86A3D38C4CF6451441C31EDD0A`. Expire le **2036-07-18**
(validité 10 ans — le cert est un engagement, ADR-0010 : en changer = re-octroi général).

Import CI (séquence validée conceptuellement ici, à câbler dans `release.yml` par #90) :
keychain jetable → `security import cert.p12 -P "$ISLAND_CERT_P12_PASSWORD" -k <kc>
-T /usr/bin/codesign` → `security set-key-partition-list -S apple-tool:,apple:` (sinon
codesign prompte et bloque le runner) → destruction du keychain en `if: always()`.

## Protocole rejouable

### 1. Générer le certificat (UNE fois — ne pas rejouer tant que l'identité vit)

```bash
cat > openssl.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_codesign
prompt = no
[dn]
CN = island-release
[v3_codesign]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
subjectKeyIdentifier = hash
EOF
openssl req -x509 -newkey rsa:2048 -keyout island-release.key.pem \
    -out island-release.cert.pem -days 3650 -nodes -config openssl.cnf
openssl rand -base64 24 > p12-password.txt && chmod 600 p12-password.txt island-release.key.pem
# -legacy OBLIGATOIRE avec OpenSSL 3 (Homebrew) : sans lui, security import échoue
# « MAC verification failed during PKCS12 import (wrong password?) » — message trompeur.
openssl pkcs12 -export -legacy -inkey island-release.key.pem -in island-release.cert.pem \
    -name "island-release" -out island-release.p12 -passout "pass:$(cat p12-password.txt)"
```

### 2. Importer + truster localement, poser les secrets

```bash
security import island-release.p12 -k ~/Library/Keychains/login.keychain-db \
    -P "$(cat p12-password.txt)" -T /usr/bin/codesign
# Sans trust, codesign refuse un cert auto-signé (CSSMERR_TP_NOT_TRUSTED).
# Domaine utilisateur (pas -d) ; dialogue mot de passe macOS possible.
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db island-release.cert.pem
security find-identity -v -p codesigning   # → « island-release » = 1 valid identity

base64 -i island-release.p12 | gh secret set ISLAND_CERT_P12 --repo Taklin1/island
gh secret set ISLAND_CERT_P12_PASSWORD --repo Taklin1/island < p12-password.txt
```

La clé privée vit dans le trousseau login (store canonique local) + dans le secret GitHub ;
les fichiers de travail étaient sous scratchpad jetable, non conservés, non commités.

### 3. Builder et signer (re-signature par-dessus l'ad-hoc du script)

`scripts/package_app.sh` signe ad-hoc en dur (la paramétrisation `ISLAND_CODESIGN_IDENTITY`
arrive avec #90) — le spike re-signe le bundle produit :

```bash
scripts/package_app.sh --no-install
codesign --force --deep --sign "island-release" .build/dist/island.app
codesign -dvv .build/dist/island.app 2>&1 | grep Authority   # → Authority=island-release
```

### 4. Mesurer la permission — instrument LaunchAgent (PAS nohup, cf. pièges)

```bash
# Remplacement à chaud (identique au parcours de mise à jour réel) :
pkill -f "Applications/island.app" || true; sleep 1
rm -rf ~/Applications/island.app
ditto .build/dist/island.app ~/Applications/island.app

# Lancement via launchd : island est alors son PROPRE « responsible process » TCC,
# et StandardOutPath capture la trace `island: accessibility permission …`.
launchctl bootstrap "gui/$(id -u)" dev.island.spike87.plist   # 1re fois
launchctl kickstart -k "gui/$(id -u)/dev.island.spike87"      # relances suivantes
grep "island: accessibility" /tmp/island-spike87.log
# Fin de campagne : launchctl bootout gui/$(id -u)/dev.island.spike87 && open ~/Applications/island.app
```

Plist minimal : `Label=dev.island.spike87`, `ProgramArguments=[…/island.app/Contents/MacOS/island]`,
`RunAtLoad=true`, `KeepAlive=false`, `StandardOutPath=/tmp/island-spike87.log`.
État propre avant l'expérience : `tccutil reset Accessibility com.taklin.island`.

## Pièges découverts (capitalisés)

1. **`nohup` depuis le terminal fausse la mesure TCC.** Lancée depuis un shell, island
   hérite du « responsible process » du terminal (ici Ghostty, qui A l'Accessibilité) :
   `AXIsProcessTrusted()` répond `granted` **même après `tccutil reset`**. La méthode
   HITL de `docs/agents/agentic-driving.md` (nohup + redirection) reste valable pour
   *observer une app déjà autorisée*, mais est **inutilisable pour mesurer l'absence**
   de permission → LaunchAgent obligatoire (amendement porté dans agentic-driving.md).
2. **`openssl pkcs12 -export` sans `-legacy`** (OpenSSL 3 / Homebrew) produit un `.p12`
   que `security import` rejette (« MAC verification failed… wrong password? » — le mot
   de passe n'y est pour rien). Le `.p12` du secret `ISLAND_CERT_P12` est au format legacy.
3. **L'UI Réglages ment quand l'identité change.** La case island reste **cochée** alors
   que la trace dit `absent` (constaté deux fois : island-release→ad-hoc et ad-hoc C→D).
   Pire : **décocher/recocher ne suffit PAS** à re-octroyer sur une entrée périmée —
   il faut **supprimer la ligne (−) puis ré-ajouter l'app (+)**. À documenter pour les
   utilisateurs si le certificat devait un jour changer (conséquence ADR-0010).
4. **Le build incrémental Swift est reproductible.** `touch` d'une source + rebuild peut
   redonner un binaire **bit-identique** (SHA identique C/D au premier essai) → même
   CDHash → « la permission survit » ne prouverait rien. Vérifier le SHA-256 entre deux
   builds du protocole ; au besoin forcer la différence (le spike a ajouté une clé
   marqueur dans l'Info.plist du bundle jetable avant re-signature). Entre vraies
   releases le problème ne se pose pas (la version dans Info.plist change le CDHash).

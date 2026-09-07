# web-app — le site vitrine d'island

Portage React de la landing page validée (issue #117). Page statique, aucun
service à faire tourner : le build produit un dossier `dist/` à déposer tel quel
sur n'importe quel hébergeur — un serveur perso, un bucket, GitHub Pages.

## Développer

```sh
cd web-app
npm install
npm run dev      # http://localhost:5173
```

## Construire et publier

```sh
npm run build    # typecheck puis build → web-app/dist/
npm run preview  # sert dist/ en local pour vérifier avant publication
```

`dist/` se copie ensuite sur le serveur (`rsync -av dist/ user@host:/var/www/island/`).
La `base` de Vite est relative (`./`), donc le site fonctionne à la racine d'un
domaine **comme** dans un sous-dossier, sans rebuild.

## Ce qui est porté depuis l'artefact

- **Le panneau vivant** (`components/IslandStage.tsx`) : Masqué au repos, Peek au
  chargement, Révélation au survol du bord haut de la scène, repli avec délai de
  grâce — les trois surfaces de l'app réelle (ADR-0007). Un curseur fantôme
  démontre le geste tant qu'un vrai pointeur n'a pas pris la main.
- **Les Sprites** (`sprites.ts`) : le moteur pixel-art des planches de l'issue
  #11, redessiné dans un backing store 16×16 que le CSS agrandit
  (`image-rendering: pixelated`). Aucune image n'est livrée.
- **Le Liseré** : le contour d'écran orange, éteint par l'Acquittement (clic sur
  la carte en attente), qui bascule aussi la mascotte de la barre des menus.
- **La ligne d'install** cliquable-pour-copier, rétrécie pour tenir sur une ligne.

## Vocabulaire

La page est en anglais (ADR-0011). `CONTEXT.md` reste la source de vérité du
vocabulaire, listes _Avoid_ comprises : jamais notch/encoche/widget pour désigner
le produit.

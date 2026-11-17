# J2 — Sécurité des images

Les images scannées sont `quiz-backend:local` et `quiz-frontend:local`, celles du Compose.

## Résultats

| Image | Avant | Après |
|---|---|---|
| backend | 55 vulnérabilités (1 CRITICAL, 17 HIGH, 24 MEDIUM, 13 LOW) | 2 MEDIUM, 0 HIGH, 0 CRITICAL |
| frontend | 61 vulnérabilités (1 CRITICAL, 12 HIGH, 4 MEDIUM, 44 LOW) | 0 |

Rapports complets : `trivy-backend-avant.txt`, `trivy-backend-apres.txt`, `trivy-frontend-avant.txt`, `trivy-frontend-apres.txt` (toutes sévérités).

Tailles (colonne disque de `docker images`) :

| Image | Avant | Après |
|---|---|---|
| backend | 269 MB | 280 MB |
| frontend | non relevé | 100 MB |

## Origine des vulnérabilités

- **Backend, Node** : toutes les HIGH et la CRITICAL (`tar` 7.5.11, CVE-2026-59873) étaient dans **npm**, embarqué par l'image de base `node` (`usr/local/lib/node_modules/npm/...`). Aucune n'était dans les dépendances de l'application (`app/node_modules` : 0 vulnérabilité HIGH ou CRITICAL). `npm audit fix` n'aurait donc rien corrigé.
- **Backend et frontend, système** : paquets Alpine (openssl, musl, zlib côté backend ; brotli-libs, curl, expat, libxslt, musl, zlib côté frontend). Toutes avaient un correctif publié.
- **Frontend** : aucun paquet Node dans l'image finale (build multi-étapes). Seule la CRITICAL venait de `brotli-libs`.

## Corrections

1. **Suppression de npm, npx, corepack et yarn de l'image backend**, dans la même instruction `RUN` que `npm ci`. Au runtime, seul `node server.js` est utilisé. Résultat : la CRITICAL et les 12 HIGH Node disparaissent.
2. **`apk upgrade --no-cache`** dans les deux images, pour récupérer les paquets système corrigés.
3. **Frontend** : passage temporaire en `USER root` pour `apk upgrade`, puis retour à `USER nginx`. Vérifié : le processus tourne bien avec l'utilisateur `nginx`.
4. Rappel des mesures déjà en place depuis J1 : build multi-étapes du frontend, `npm ci --omit=dev`, utilisateurs non-root, `.dockerignore`, tags exacts, `read_only`, `cap_drop: ALL`.

Compromis : avec `apk upgrade`, le build dépend de l'état du dépôt Alpine à la date de construction, il est donc moins figé que l'image de base seule. Autre limite : supprimer npm dans une couche ultérieure ne réduit pas la taille de l'image, les fichiers restent dans la couche de base (la taille du backend a augmenté de 269 à 280 MB). Les fichiers n'existent plus dans le système de fichiers final, donc ni Trivy ni le conteneur ne les voient.

## Commandes

```bash
trivy image quiz-backend:local > preuves/J2/trivy-backend-avant.txt     # avant les corrections
trivy image quiz-frontend:local > preuves/J2/trivy-frontend-avant.txt
docker build --no-cache -t quiz-backend:local backend
docker build --no-cache -t quiz-frontend:local .
trivy image quiz-backend:local > preuves/J2/trivy-backend-apres.txt
trivy image quiz-frontend:local > preuves/J2/trivy-frontend-apres.txt
trivy image --severity CRITICAL --exit-code 1 quiz-backend:local        # code 0 après correction
(cd backend && npm audit --omit=dev)
```

Politique prévue pour la CI : `trivy image --severity CRITICAL --exit-code 1`. Avant correction, chaque image contenait 1 CRITICAL, le contrôle aurait donc échoué ; après correction il retourne 0.

## Vulnérabilités résiduelles

Backend : 2 MEDIUM, détaillées dans `trivy-backend-apres.txt`. `npm audit` signale 4 vulnérabilités moderate : `glob` (contournement d'annulation par AbortSignal), `minimatch` (déni de service) et deux paquets qui en dépendent (`js-beautify`, `editorconfig`). Ce sont des dépendances transitives : `server.js` n'en importe aucune.

Décision : non corrigées. `npm audit fix` modifierait le lockfile sur des paquets tiers, hors du périmètre de l'exercice (pas de changement applicatif). Sévérité moderate, donc sous le seuil bloquant de la CI (CRITICAL). À réévaluer quand le paquet parent publiera une version mise à jour.

## Vérification fonctionnelle après correction

Compose relancé avec les nouvelles images : `/health` renvoie 200, les conteneurs sont `healthy`, les données PostgreSQL sont intactes (le volume n'a pas été touché).
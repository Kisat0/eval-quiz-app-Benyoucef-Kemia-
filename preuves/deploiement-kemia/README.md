# Déploiement `acrquizbenyoucefkemia` (Kemia)

Ce dossier documente un second déploiement Azure, réalisé avec `scripts/deploy.sh`, en parallèle de l'infrastructure de référence du groupe (`kisat0quizacr`, preuves dans `preuves/J3` à `preuves/J5`).

| Jalon | Preuves |
|---|---|
| J3 — Azure CLI et ACR | [J3/README.md](J3/README.md) |
| J4 — Azure Container Apps | [J4/README.md](J4/README.md) |
| J5 — PostgreSQL cloud (Neon) | [J5/README.md](J5/README.md) |

| Ressource | Nom |
|---|---|
| Groupe de ressources | `rg-quiz-app` (abonnement Azure for Students, `francecentral`) |
| Registre | `acrquizbenyoucefkemia` |
| Environnement | `cae-quiz-app` (mode WorkloadProfiles) |
| Applications | `quiz-backend` (ingress interne), `quiz-frontend` (ingress externe) |

**Historique de la configuration Nginx :** les preuves J3 et J4 ont été produites avec un template utilisant `BACKEND_URL`. Depuis le commit `aabd6a3` (fusion de `main`), le déploiement utilise le template du groupe : `deploy.sh` passe `BACKEND_SCHEME=http`, `BACKEND_HOST=quiz-backend` et `BACKEND_PORT=80` au frontend. Le principe est inchangé : le frontend joint le backend interne par son nom d'application, et l'en-tête `Host` désigne le backend pour qu'Envoy route correctement.

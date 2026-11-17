# Lancement, déploiement et nettoyage

## En local (Docker Compose)

```bash
cp .env.example .env     # puis remplacer JWT_SECRET et ADMIN_PASSWORD
docker compose up -d --build --wait
```

Application : http://localhost:8087, administration : http://localhost:8087/gestion-quiz. Les données sont dans le volume `quiz-app_pgdata` : `docker compose down` les conserve, `down -v` les supprime.

## Sur Azure

- **Automatique** : chaque fusion dans `main` déclenche `.github/workflows/cd.yml` (build, scan Trivy bloquant sur CRITICAL, publication dans l'ACR avec le hash du commit, mise à jour des deux Container Apps, test de `/health`).
- **Manuel** : `scripts/deploy.sh <tag>` (Azure CLI). Prérequis : `az login` (MFA exigée sur le tenant), les variables `DATABASE_URL`, `ADMIN_PASSWORD`, `JWT_SECRET`, `RESEND_API_KEY`, des images déjà dans l'ACR. Ce script rassemble les commandes exécutées à la main pendant le projet ; il n'a pas été lancé de bout en bout.
- **Base** : créer le schéma une seule fois : `psql "<chaîne de connexion>" -f database/init.sql`.
- **Identité de la CD** : identité managée `id-quiz-github-deploy` avec un identifiant fédéré dont le sujet est celui présenté par GitHub (`repo:<owner>@<id>/<repo>@<id>:ref:refs/heads/main`), rôles AcrPush (ACR) et Contributor (groupe). Secrets GitHub : `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

## Nettoyage

`scripts/destroy.sh` supprime le groupe `rg-quiz-app` et tout son contenu. À lancer après sauvegarde des preuves et accord du formateur. Penser aussi à changer le mot de passe du rôle Neon.
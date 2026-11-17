# J4 — Frontend et backend dans Azure Container Apps

Date : 2026-11-17. Région : francecentral. URL du frontend : https://frontend.happyground-310d0cc5.francecentral.azurecontainerapps.io

## Résultat

| Élément | Valeur |
|---|---|
| Environnement | `cae-quiz-app` (type Express) |
| Registre | `kisat0quizacr` (images tirées avec une identité managée, rôle AcrPull, sans mot de passe) |
| Backend | app `backend`, port 3007, 0,25 vCPU, 0,5 Gi, secrets Azure pour le JWT, le mot de passe admin et la clé Resend |
| Frontend | app `frontend`, Nginx non-root port 8080, ingress externe |
| Révisions | `backend--latest` et `frontend--latest` : Healthy, 100 % du trafic |
| Test | `GET /health` via le frontend : 200, `{"status":"ok"}` (`health.txt`) |

Fichiers : `health.txt`, `health-backend.txt`, `revisions-*.txt`, `config-*.txt`, `logs-*.txt`.

Le backend démarre sans PostgreSQL : `/health` ne touche pas la base, et le pool de connexions ne se connecte qu'à la première requête. Les routes qui lisent ou écrivent en base échouent tant que la base cloud n'est pas branchée (J5).

## Diagnostic

1. **Nginx en boucle de redémarrage** (`host not found in upstream "backend:80"`) : le nom court `backend` ne se résout pas dans cet environnement.
2. **502 en HTTPS** : l'image déployée envoyait du HTTP sur le port 443. Le template Nginx a été paramétré (`BACKEND_SCHEME`, `BACKEND_HOST`, `BACKEND_PORT`), et l'image reconstruite.
3. **404 sur `/health`** malgré les bons noms, avec un `404 {"error":"Not found"}` renvoyé par le proxy d'Azure, pas par l'application.
4. **Cause** : l'environnement créé par défaut est de type **Express**, qui ne prend pas en charge la découverte de services entre apps (documentation Azure Container Apps Express). Un ingress interne n'y est donc pas joignable depuis le frontend. Autre symptôme du même type d'environnement : `--allow-insecure` y est refusé.
5. **Correctif** : ingress du backend passé en externe. Le frontend l'appelle par son nom public, en HTTPS.

## Compromis de sécurité

- Le backend est joignable depuis Internet. L'API est déjà exposée par le proxy `/api/` du frontend, donc seule l'entrée directe s'ajoute. Protections : rate limiting et JWT pour les routes d'administration.
- Nginx ne vérifie pas le certificat du backend. Le trafic va vers le nom public de l'app, dont le certificat est valide, et la vérification peut être ajoutée.
- En production : environnement standard avec ingress interne, ou restriction par IP.

## Commandes principales

```bash
az containerapp env create --name cae-quiz-app --resource-group rg-quiz-app --location francecentral
az containerapp create --name backend ...   # ingress, identité managée, secrets
az containerapp create --name frontend ...
az containerapp ingress update -n backend -g rg-quiz-app --type external
az containerapp update -n frontend -g rg-quiz-app --image kisat0quizacr.azurecr.io/quiz-frontend:<tag>
```
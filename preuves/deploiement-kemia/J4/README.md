# J4 — Frontend et backend dans Azure Container Apps

**URL du frontend :** https://quiz-frontend.whitemeadow-b21d8a24.francecentral.azurecontainerapps.io

## Architecture

```
Internet ──HTTPS──▶ quiz-frontend (ingress EXTERNE, port 8080, Nginx)
                        ├─ /, /gestion-quiz  → fichiers statiques
                        └─ /api/, /health    → proxy_pass ${BACKEND_URL} = http://quiz-backend
                                                   │  (Envoy, réseau interne de l'environnement)
                                                   ▼
                                quiz-backend (ingress INTERNE, port 3007, Node/Express)
                                                   │
                                                   └──▶ PostgreSQL : non branché au J4 (J5 : Neon)

Environnement Container Apps : cae-quiz-app (mode WorkloadProfiles, profil Consumption)
Images tirées depuis acrquizbenyoucefkemia.azurecr.io par identité managée (AcrPull)
```

## Configuration des applications

```
$ az containerapp list -g rg-quiz-app --query "[].{app:name, externe:...ingress.external, port:...ingress.targetPort, image:..., registre:...registries[0].identity}" -o table
App            Externe    Port    Image                                                   Registre
-------------  ---------  ------  ------------------------------------------------------  ----------
quiz-backend   False      3007    acrquizbenyoucefkemia.azurecr.io/quiz-backend:d260acc   system
quiz-frontend  True       8080    acrquizbenyoucefkemia.azurecr.io/quiz-frontend:d260acc  system

$ az containerapp env show -n cae-quiz-app -g rg-quiz-app --query "{mode:properties.environmentMode, region:location}" -o table
Mode              Region
----------------  --------------
WorkloadProfiles  France Central
```

| Paramètre | Valeur | Justification |
|---|---|---|
| Ingress backend | interne | le backend n'a pas à être joignable depuis Internet ; seul le frontend l'appelle |
| Ingress frontend | externe, HTTPS géré par Azure | seul point d'entrée public |
| CPU / mémoire | 0,25 vCPU / 0,5 Gi par app | configuration minimale (maîtrise des crédits) |
| Réplicas | min 0, max 1 | scale-to-zero : pas de facturation de calcul sans trafic |
| Secrets backend | `jwt-secret`, `admin-password`, `resend-api-key` | stockés comme secrets de la Container App, injectés via `secretref:` |

## Communication frontend → backend

En local (Compose), Nginx joignait `backend:3007`. Ce nom n'existe pas sur Azure. La configuration Nginx est donc devenue un **template** (`nginx/default.conf.template`) :

- l'image nginx exécute `envsubst` au démarrage et remplace `${BACKEND_URL}` ;
- Compose : `BACKEND_URL=http://backend:3007` ;
- Container Apps : `BACKEND_URL=http://quiz-backend` (une app joint une autre app du même environnement par son nom, sur le port 80 ; Envoy redirige vers le port cible 3007).

La directive `proxy_set_header Host $host` a été retirée : Envoy aiguille les requêtes selon l'en-tête `Host`, et transmettre l'hôte du frontend enverrait la requête au mauvais service.

## Test de `/health`

```
$ curl -s -w ' HTTP %{http_code}\n' https://quiz-frontend.whitemeadow-b21d8a24.francecentral.azurecontainerapps.io/health
{"status":"ok"} HTTP 200

$ curl ... /             -> 200
$ curl ... /gestion-quiz -> 200
```

La requête traverse le frontend Nginx puis le backend : la réponse `{"status":"ok"}` est produite par `backend/server.js`. Cette route ne fait aucune requête à PostgreSQL : elle prouve que le serveur démarre et répond, **pas** que la base est disponible.

**Démarrage sans base :** le backend démarre sans `DATABASE_URL`, car `pg.Pool` ne se connecte qu'à la première requête SQL. Une clé Resend factice est fournie, car `new Resend(undefined)` fait planter le module au démarrage (diagnostic du J1).

**Premier appel lent :** lors d'un test à 13:46 UTC, le premier appel a répondu en 25,1 s, le suivant en 0,4 s. Le premier appel du script de déploiement a lui aussi dépassé 20 s avant de réussir à la tentative suivante. Le script réessaie donc jusqu'à 12 fois.

## Backend non exposé

```
$ curl -s -o /dev/null -w '%{http_code}\n' https://quiz-backend.internal.whitemeadow-b21d8a24.francecentral.azurecontainerapps.io/health
404
```

L'adresse interne du backend n'est pas joignable depuis Internet.

## Révisions

Après le premier déploiement, puis après relance de `deploy.sh` (tâche de mise à jour) :

```
$ az containerapp revision list -n quiz-backend -g rg-quiz-app --all -o table
Rev                                Active    Sante    Image                                                  Cree
quiz-backend--ekzjgko              False     Healthy  mcr.microsoft.com/k8se/quickstart:latest               13:15:17
quiz-backend--0000001              False     Healthy  acrquizbenyoucefkemia.azurecr.io/quiz-backend:d260acc  13:15:41
quiz-backend--rd260acc-1794922777  False     Healthy  acrquizbenyoucefkemia.azurecr.io/quiz-backend:d260acc  13:40:11
quiz-backend--rd260acc-1794923447  True      Healthy  acrquizbenyoucefkemia.azurecr.io/quiz-backend:d260acc  13:51:19

$ az containerapp revision list -n quiz-frontend -g rg-quiz-app -o table
Rev                                 Active    Replicas    Etat
quiz-frontend--rd260acc-1794923512  True      1           RunningAtMaxScale
```

- La révision `quickstart` est l'image provisoire qu'Azure CLI utilise le temps d'attribuer le rôle `AcrPull` à l'identité managée.
- Chaque relance de `deploy.sh` crée une nouvelle révision nommée `r<commit>-<horodatage>`.
- Mode `Single` : seule la dernière révision est active et reçoit 100 % du trafic.

## Logs des révisions

```
$ az containerapp logs show -n quiz-backend -g rg-quiz-app --tail 10
... stdout F Server running on port 3007

$ az containerapp logs show -n quiz-frontend -g rg-quiz-app --tail 15
... [notice] 1#1: start worker processes
```

Aucune erreur `host not found in upstream` côté Nginx : `http://quiz-backend` est bien résolu.

## Sécurité des secrets

Les secrets sont lus dans `.env.azure` (ignoré par Git, droits 600) et ne sont jamais affichés :

```
JWT_SECRET     dans la sortie de deploy.sh : 0 occurrence | dans az containerapp show : 0
ADMIN_PASSWORD dans la sortie de deploy.sh : 0 occurrence | dans az containerapp show : 0
```

## Incident : environnement en mode Express

Premier déploiement :

```
ERROR: (ExpressRegistrySystemIdentityNotSupported) System-assigned managed identity for container
registry authentication is not supported for container app 'quiz-backend' on express environments.
```

- **Cause :** `az containerapp env create` crée désormais par défaut un environnement en mode `Express`, qui n'accepte pas l'identité managée pour tirer les images d'un ACR.
- **Alternative écartée :** activer le compte admin de l'ACR aurait fonctionné, mais imposait de stocker un mot de passe de registre.
- **Correction :** création de l'environnement avec `--environment-mode WorkloadProfiles` (profil Consumption facturé à l'usage). Le script vérifie désormais le mode et s'arrête avec un message clair si un environnement Express existe déjà. L'app incomplète et l'environnement Express ont été supprimés, puis le script relancé (commit `d260acc`).

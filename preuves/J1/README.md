# J1 — Conteneurisation locale


## Démarrage

```bash
cp .env.example .env      # puis remplacer JWT_SECRET par une valeur aléatoire
docker compose up -d --build --wait
```

Le Compose lance trois services : `db` (PostgreSQL 17.12), `backend` (Node 22) et `frontend` (Nginx non-root). L'application est servie sur http://localhost:8087.

## État des services

```
NAME            IMAGE                   SERVICE    STATUS                    PORTS
quiz-backend    quiz-backend:local      backend    Up 29 seconds (healthy)   3007/tcp
quiz-db         postgres:17.12-alpine   db         Up 40 seconds (healthy)   5432/tcp
quiz-frontend   quiz-frontend:local     frontend   Up 24 seconds (healthy)   0.0.0.0:8087->8080/tcp
```

Seul le frontend publie un port. La base et le backend ne sont joignables que sur le réseau interne de Compose.

## Tests

| Test | Résultat |
|---|---|
| `GET /` (via Nginx) | 200 |
| `GET /health` (Nginx puis backend) | 200, `{"status":"ok"}` |
| `GET /gestion-quiz` | 200 |
| Utilisateur du backend | `uid=1000(node)` |
| Tables créées par `init.sql` | `users`, `quiz_results`, `answers` |

## Persistance

Données avant `docker compose down` :

```
 id | firstname  |         created_at
  1 | Ben Youcef | 2026-11-17 10:22:44.647982

 id | user_id | score | total_questions
  1 |       1 |    10 |              20
```

Commandes :

```bash
docker compose down            # sans -v : le volume est conservé
docker volume ls | grep pgdata # quiz-app_pgdata est toujours présent
docker compose up -d --wait
```

Après recréation des conteneurs, les mêmes lignes sont retrouvées, avec le même `created_at`.

Explication : les données de PostgreSQL sont dans le volume nommé `quiz-app_pgdata` (`/var/lib/postgresql/data`), qui existe indépendamment des conteneurs. `docker compose down` supprime les conteneurs et le réseau, pas le volume. `init.sql` n'est exécuté que sur un volume vide, donc il n'est pas rejoué.

## Diagnostic

Le backend plante au démarrage si `RESEND_API_KEY` est absente (`new Resend(undefined)` lève `Missing API key`). La variable est donc obligatoire dans Compose. Avec une clé factice, le serveur démarre sans PostgreSQL, et `/health` ne touche pas la base. L'envoi d'email échoue alors proprement dans un `try/catch`, sans empêcher l'enregistrement du résultat.

## Captures

- `quiz-resultat.png` : résultat du quiz
- `admin-liste.png` : liste des résultats dans l'administration (email masqué)
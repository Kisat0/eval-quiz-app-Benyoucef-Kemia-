# J5 — PostgreSQL cloud (Neon) sur le déploiement `acrquizbenyoucefkemia`

Date des tests : 2026-11-17 (15:41 UTC). Version déployée : commit `aabd6a3`.
Frontend : https://quiz-frontend.whitemeadow-b21d8a24.francecentral.azurecontainerapps.io

## Résultat

| Élément | Valeur |
|---|---|
| Base | Neon, PostgreSQL 18.7, région AWS `eu-central-1` (Francfort) |
| Connexion | point d'accès direct (sans pooler), `?sslmode=require` |
| Chiffrement | TLSv1.3, `TLS_AES_256_GCM_SHA384` ; connexion sans TLS refusée par Neon |
| Schéma | `database/init.sql` exécuté une fois avec `psql` |
| Secret | chaîne de connexion stockée en secret de Container App (`database-url`), lue via `secretref` |
| Inscription | `POST /api/users` → HTTP 201 |
| Résultat | `POST /api/results` → HTTP 201, ligne dans `quiz_results` et `answers` |
| Persistance | données identiques après redémarrage de la révision backend |

## 1. Création de la base et initialisation du schéma

Projet Neon `quiz-app`, région Europe (Francfort, la plus proche de `francecentral`). Le paramètre `&channel_binding=require` fourni par Neon a été retiré : il n'est pas utile au pilote `pg` du backend, et le TLS reste imposé par `sslmode=require`.

Contrairement au Compose local, Neon n'exécute pas `init.sql` automatiquement. Le schéma est créé une fois, à la main :

```bash
read -rs NEON_URL && export NEON_URL     # la chaîne n'est ni affichée ni gardée dans l'historique
psql "$NEON_URL" -f database/init.sql
psql "$NEON_URL" -c '\dt'
```

```
 Schema |     Name     | Type  |    Owner
--------+--------------+-------+--------------
 public | answers      | table | neondb_owner
 public | quiz_results | table | neondb_owner
 public | users        | table | neondb_owner
```

## 2. Connexion chiffrée

Vue côté client (`psql -c '\conninfo'`, hôte masqué) :

```
 Host                 | ep-***.c-8.eu-central-1.aws.neon.tech
 SSL Connection       | true
 SSL Protocol         | TLSv1.3
 SSL Cipher           | TLS_AES_256_GCM_SHA384
```

Tentative sans TLS (`sslmode=disable`) :

```
psql: error: connection to server at "ep-***.c-8.eu-central-1.aws.neon.tech" (...), port 5432 failed:
ERROR:  connection is insecure (try using `sslmode=require`)
```

Neon refuse toute connexion non chiffrée : le TLS ne dépend donc pas seulement de la configuration du client.

**Diagnostic :** la requête `SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()` renvoie `ssl = f` sur Neon. Ce n'est pas une connexion en clair : le client se connecte en TLS au proxy de Neon, qui ouvre ensuite sa propre connexion vers le serveur PostgreSQL. `pg_stat_ssl` ne voit que ce second tronçon interne. La preuve valable est donc côté client (`\conninfo`) et par le refus de `sslmode=disable`.

## 3. Gestion du secret

1. La chaîne est saisie dans `.env.azure`, à la racine du dépôt. Ce fichier est ignoré par Git (`git check-ignore .env.azure`) et protégé en `chmod 600`.
2. `scripts/deploy.sh` la transmet comme **secret de la Container App** (`database-url`), et la variable du conteneur y fait référence :

```
$ az containerapp show -n quiz-backend -g rg-quiz-app --query "properties.template.containers[0].env[].{nom:name, secret:secretRef}" -o table
Nom             Secret
--------------  --------------
PORT
NODE_ENV
ADMIN_USERNAME
JWT_SECRET      jwt-secret
ADMIN_PASSWORD  admin-password
RESEND_API_KEY  resend-api-key
DATABASE_URL    database-url
```

3. Contrôle de fuite (nombre d'occurrences, aucune valeur affichée) :

```
Sortie de deploy.sh       -> DATABASE_URL : 0 | mot de passe Neon : 0 | JWT_SECRET : 0
az containerapp show      -> DATABASE_URL : 0 | mot de passe Neon : 0
```

**Piège rencontré :** un premier contrôle a renvoyé 249 et 327 occurrences. La variable `$DATABASE_URL` n'était pas chargée dans le terminal (fichier `.env.azure` non sourcé) : `grep -cF ""` trouve alors un motif vide dans chaque ligne, et 249 et 327 étaient simplement le nombre de lignes des deux sorties. Après `set -a; source .env.azure; set +a`, le contrôle donne bien 0.

## 4. Tests fonctionnels sur Azure

```bash
FQDN=quiz-frontend.whitemeadow-b21d8a24.francecentral.azurecontainerapps.io

curl -s -X POST https://$FQDN/api/users -H "Content-Type: application/json" \
  -d '{"firstname":"TestJ5","email":"test-j5@example.com"}'
# -> HTTP 201, id 3

curl -s -X POST https://$FQDN/api/results -H "Content-Type: application/json" \
  -d '{"userId":3,"score":1,"totalQuestions":1,"answers":[{"questionIndex":0,"questionText":"Test J5","userAnswer":"A","correctAnswer":"A","isCorrect":true,"timeSpentMs":1000}]}'
# -> {"message":"Results saved and email sent","quizResultId":3} HTTP 201
```

Le message « email sent » est un texte fixe du backend : la clé Resend étant factice, l'envoi échoue, mais l'erreur est interceptée et le résultat est bien enregistré (comportement vérifié au J1).

## 5. Persistance

Requête de vérification (sans colonne email) :

```sql
SELECT u.id, u.firstname, qr.score, qr.total_questions, qr.completed_at,
       (SELECT count(*) FROM answers a WHERE a.quiz_result_id = qr.id) AS reponses
FROM users u JOIN quiz_results qr ON qr.user_id = u.id WHERE u.id = 3;
```

Avant redémarrage :

```
 id | firstname | score | total_questions |       completed_at        | reponses
  3 | TestJ5    |     1 |               1 | 2026-11-17 15:41:09.02117 |        1
```

Redémarrage du backend :

```bash
az containerapp revision restart -n quiz-backend -g rg-quiz-app --revision quiz-backend--raabd6a3-1794929883
```

Après redémarrage : même ligne, même `completed_at`.

```
 id | firstname | score | total_questions |       completed_at        | reponses
  3 | TestJ5    |     1 |               1 | 2026-11-17 15:41:09.02117 |        1
```

Lecture par l'API d'administration après redémarrage (`POST /api/admin/login` puis `GET /api/admin/results`) :

```
total utilisateurs avec résultats: 2
- TestJ5 2 tentative(s), meilleur 1 / 1
```

Les deux tentatives correspondent à un test manuel antérieur et au test ci-dessus (même email de test, regroupé par l'API).

Logs du backend après redémarrage : `Server running on port 3007`, aucune erreur de connexion.

## 6. Diagnostic : réveil de la base

Neon met la base en veille après quelques minutes sans activité. Le backend abandonne une tentative de connexion au bout de 2 secondes (`connectionTimeoutMillis: 2000` dans `server.js`). La première requête après une pause peut donc échouer (HTTP 500), puis réussir à la suivante. Ce paramètre relève du code applicatif et n'a pas été modifié.

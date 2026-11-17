# J5 — PostgreSQL cloud (Neon)

Date : 2026-11-17.

## Résultat

| Élément | Valeur |
|---|---|
| Base | Neon, PostgreSQL 17, région Europe |
| Connexion | chaîne directe (sans pooler), TLS obligatoire (`sslmode=require`) |
| Schéma | `database/init.sql` exécuté une fois avec `psql` : tables `users`, `quiz_results`, `answers` (`schema.txt`) |
| Secret | la chaîne de connexion est un secret Azure (`database-url`) lu par le backend via `secretref` ; aucune valeur dans le dépôt |
| Test | inscription et quiz complet sur le frontend Azure ; données retrouvées en base (`donnees-avant-redemarrage.txt`) |
| Persistance | backend redémarré, mêmes lignes et même `created_at` (`donnees-apres-redemarrage.txt`) |

Captures : `quiz-azure.png`, `admin-azure.png` (email masqué).

## Choix et diagnostic

- **Pooler écarté** : le backend ouvre des transactions explicites (`BEGIN`/`COMMIT`), donc la connexion directe évite les surprises du pooler.
- **`channel_binding=require` retiré** : le pilote `pg` du backend ne le gère pas ; le TLS reste obligatoire.
- **Sans `DATABASE_URL`**, le backend démarrait mais l'inscription échouait en 500 (connexion refusée sur `127.0.0.1:5432`) : `/health` ne touche pas la base.
- **Réveil de Neon** : la base se met en veille ; la première requête après une pause peut échouer, car le backend abandonne une connexion après 2 secondes. Elle réussit à la tentative suivante.
- Le schéma est créé à la main une seule fois : contrairement au Compose local, Neon n'exécute pas `init.sql` tout seul.
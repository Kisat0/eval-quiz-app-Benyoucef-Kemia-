# Architecture cloud

```mermaid
flowchart LR
  U["Navigateur"] -->|HTTPS| F["frontend (Container App)<br/>Nginx non-root, port 8080"]
  F -->|"HTTPS : proxy /api/ et /health"| B["backend (Container App)<br/>Node / Express, port 3007"]
  B -->|"TLS (sslmode=require)"| N[("Neon<br/>PostgreSQL 17")]
  B -.->|API externe| R["Resend (emails)"]
  GH["GitHub Actions (CD sur main)"] -->|"OIDC, sans mot de passe"| AZ["Azure"]
  GH -->|"push, tag = commit"| ACR[("ACR kisat0quizacr")]
  ACR -->|"pull, identité managée AcrPull"| F
  ACR -->|"pull, identité managée AcrPull"| B
  GH -->|az containerapp update| F
  GH -->|az containerapp update| B
```

## Choix

- Région `francecentral`, imposée par une politique d'abonnement (5 régions autorisées).
- Environnement Container Apps de type Express (créé par défaut) : pas de découverte de services entre apps, donc le backend est en ingress externe et le frontend l'appelle par son nom public, en HTTPS. Compromis de sécurité documenté dans `preuves/J4`.
- Images tirées de l'ACR avec une identité managée (rôle AcrPull) : aucun mot de passe de registre.
- Secrets (JWT, mot de passe admin, clé Resend, chaîne de connexion Neon) stockés comme secrets Azure, lus par le backend via `secretref`. Aucun dans le dépôt.
- CD authentifiée par OIDC avec une identité managée dédiée (`id-quiz-github-deploy`), limitée à la branche `main` du fork. Les droits : AcrPush sur l'ACR et Contributor sur le groupe `rg-quiz-app`. La création d'applications Entra est interdite sur le tenant, d'où l'identité managée.
- Base Neon : connexion directe (sans pooler), TLS obligatoire. Le schéma est créé une fois à la main avec `database/init.sql`.
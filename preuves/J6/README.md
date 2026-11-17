# J6 — CI/CD

## J6-A : CI sur Pull Request

Workflow : `.github/workflows/ci.yml` (déclenché sur les PR vers `main`). Contrôles : `build-and-scan (backend)`, `build-and-scan (frontend)`, `compose-config`. Trivy est lancé sur les images construites et échoue sur une CRITICAL (`--exit-code 1`, sans `continue-on-error`).

- `main` protégé : PR obligatoire, contrôles obligatoires, pas de contournement. Un push direct est refusé (capture : `push-refuse.png`).
- Contrôle échoué puis réussi : scénario contrôlé, le seuil Trivy a été abaissé à MEDIUM sur la PR de démo pour faire échouer le backend (2 MEDIUM résiduelles du J2), fusion bloquée (`ci-echec.png`), puis seuil remis à CRITICAL (`ci-ok.png`). Aucune image dangereuse n'a été publiée.
- Limite : une PR ne peut pas être approuvée par son auteur ; sans second collaborateur, l'approbation n'est pas exigée.

## J6-B : CD après fusion dans `main`

Workflow : `.github/workflows/cd.yml`. Connexion Azure par OIDC, build, scan Trivy, publication dans l'ACR avec le hash du commit, mise à jour du frontend et du backend, test de `/health`.

- Tags dans l'ACR : `acr-tags-backend.txt`, `acr-tags-frontend.txt`.
- Révisions : `revisions-backend.txt`, `revisions-frontend.txt`.
- Exécution de la CD : `cd-execution.png`. Question modifiée visible dans l'application : `question-modifiee.png`.
- Diagnostic : la première exécution a échoué (`AADSTS700213`) parce que le sujet de l'identifiant fédéré n'était pas celui que GitHub présente (il contient des identifiants numériques) ; corrigé avec le sujet du log.

## Liens

- PR de démo : (colle l'URL ici)
- Exécution de la CD : (colle l'URL ici)
# J3 — Azure CLI et Azure Container Registry

## Ressources créées avec Azure CLI

Toutes les ressources sont créées par `scripts/deploy.sh` (Azure CLI uniquement, pas de portail).

| Ressource | Nom | Paramètres |
|---|---|---|
| Groupe de ressources | `rg-quiz-app` | région `francecentral` |
| Azure Container Registry | `acrquizbenyoucefkemia` | SKU `Basic`, compte admin **désactivé** |

**Région :** l'abonnement Azure for Students est soumis à la policy « Allowed resource deployment regions » (austriaeast, francecentral, spaincentral, belgiumcentral, switzerlandnorth). `francecentral` est autorisée et propose ACR et Container Apps.

## Commandes

```bash
az login --use-device-code
cp scripts/env.azure.example .env.azure   # puis renseigner les secrets (fichier ignoré par Git)
./scripts/deploy.sh
```

Étapes J3 du script :

```bash
az group create --name rg-quiz-app --location francecentral
az acr create --name acrquizbenyoucefkemia --resource-group rg-quiz-app --sku Basic --admin-enabled false
az acr login --name acrquizbenyoucefkemia            # jeton Entra ID temporaire, aucun mot de passe
docker build --pull -t acrquizbenyoucefkemia.azurecr.io/quiz-backend:<sha> ./backend
docker build --pull -t acrquizbenyoucefkemia.azurecr.io/quiz-frontend:<sha> .
docker push ...
```

## Configuration de l'ACR

```
$ az acr show -n acrquizbenyoucefkemia --query "{sku:sku.name, admin:adminUserEnabled, region:location}" -o table
Sku    Admin    Region
-----  -------  -------------
Basic  False    francecentral
```

## Images et tags

Le tag d'une image est le **hash court du commit Git** (`git rev-parse --short HEAD`), avec le suffixe `-dirty` si l'arbre de travail contient des modifications non commitées. On sait ainsi exactement quel code tourne dans chaque image ; `latest` n'est jamais utilisé.

```
$ git rev-parse --short HEAD
d260acc

$ az acr repository show-tags -n acrquizbenyoucefkemia --repository quiz-backend -o tsv
d260acc
df07ddd

$ az acr repository show-tags -n acrquizbenyoucefkemia --repository quiz-frontend -o tsv
d260acc
df07ddd
```

- `df07ddd` : commit `feat(azure): scripts deploy.sh et destroy.sh` (première tentative de déploiement, voir incidents).
- `d260acc` : commit `fix(azure): environnement Container Apps en mode WorkloadProfiles` (version déployée).

## Accès au registre sans mot de passe

Le compte admin de l'ACR est désactivé. Les Container Apps tirent les images avec leur **identité managée système**, à laquelle Azure attribue le rôle `AcrPull` sur le registre (`--registry-identity system`). Aucun identifiant de registre n'est stocké dans le dépôt, dans les scripts ni dans la configuration des applications.

## Incident : push interrompu

Lors du premier lancement, le push de l'image backend a échoué sur la couche la plus lourde (image de base Node) :

```
failed commit on ref "layer-sha256:f9480d20...": ... net/http: timeout awaiting response headers
```

- **Cause :** connexion montante lente ; Docker envoie plusieurs couches en parallèle et la plus grosse a dépassé le délai.
- **Effet :** grâce à `set -euo pipefail`, le script s'est arrêté immédiatement ; seuls le groupe de ressources et l'ACR existaient.
- **Résolution :** relance de `deploy.sh`. Le script est idempotent (ressources existantes détectées), le build est en cache et les couches déjà présentes dans l'ACR ne sont pas renvoyées (`Layer already exists`). Si l'erreur persiste, on peut limiter Docker à un envoi à la fois (`"max-concurrent-uploads": 1` dans la configuration du moteur Docker).

## Suppression

`scripts/destroy.sh` supprime le groupe de ressources entier (ACR et images compris) après confirmation par saisie du nom du groupe. Il ne sera lancé qu'après validation des preuves par le formateur, car l'ACR est nécessaire à la CI/CD (J6).

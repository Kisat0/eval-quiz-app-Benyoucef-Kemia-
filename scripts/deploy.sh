#!/usr/bin/env bash
# Déploie Quiz App sur Azure Container Apps (Azure CLI uniquement).
# Prérequis : `az login` fait, droits sur l'abonnement, images déjà publiées dans l'ACR par la CD.
# Les secrets passent par variables d'environnement, jamais dans le dépôt.
# Usage : DATABASE_URL=... ADMIN_PASSWORD=... JWT_SECRET=... RESEND_API_KEY=... ./scripts/deploy.sh <tag>
set -euo pipefail

TAG="${1:?Usage : ./scripts/deploy.sh <tag-image>}"
: "${DATABASE_URL:?DATABASE_URL manquante}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD manquante}"
: "${JWT_SECRET:?JWT_SECRET manquante}"
: "${RESEND_API_KEY:?RESEND_API_KEY manquante}"

LOCATION="${LOCATION:-francecentral}"
RG="${RG:-rg-quiz-app}"
ACR="${ACR:-kisat0quizacr}"
ENV_NAME="${ENV_NAME:-cae-quiz-app}"
PULL_IDENTITY="${PULL_IDENTITY:-id-quiz-acr-pull}"
REGISTRY="$ACR.azurecr.io"

echo "==> Fournisseurs et extension"
for p in Microsoft.ContainerRegistry Microsoft.App Microsoft.OperationalInsights Microsoft.ManagedIdentity; do
  az provider register --namespace "$p" --wait
done
az extension add --name containerapp --upgrade --yes

echo "==> Groupe de ressources"
az group create --name "$RG" --location "$LOCATION" -o none

echo "==> Registre (ACR)"
az acr show --name "$ACR" >/dev/null 2>&1 || \
  az acr create --resource-group "$RG" --name "$ACR" --sku Basic --admin-enabled false -o none

echo "==> Identité de lecture du registre (rôle AcrPull)"
az identity show -g "$RG" -n "$PULL_IDENTITY" >/dev/null 2>&1 || \
  az identity create -g "$RG" -n "$PULL_IDENTITY" --location "$LOCATION" -o none
IDENTITY_ID=$(az identity show -g "$RG" -n "$PULL_IDENTITY" --query id -o tsv)
PRINCIPAL_ID=$(az identity show -g "$RG" -n "$PULL_IDENTITY" --query principalId -o tsv)
ACR_ID=$(az acr show --name "$ACR" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role AcrPull --scope "$ACR_ID" -o none
sleep 30

echo "==> Environnement Container Apps"
az containerapp env show -g "$RG" -n "$ENV_NAME" >/dev/null 2>&1 || \
  az containerapp env create -g "$RG" -n "$ENV_NAME" --location "$LOCATION" -o none

echo "==> Backend"
if az containerapp show -g "$RG" -n backend >/dev/null 2>&1; then
  az containerapp secret set -g "$RG" -n backend --secrets \
    database-url="$DATABASE_URL" jwt-secret="$JWT_SECRET" \
    admin-password="$ADMIN_PASSWORD" resend-key="$RESEND_API_KEY" -o none
  az containerapp update -g "$RG" -n backend --image "$REGISTRY/quiz-backend:$TAG" -o none
else
  az containerapp create -g "$RG" -n backend --environment "$ENV_NAME" \
    --image "$REGISTRY/quiz-backend:$TAG" \
    --user-assigned "$IDENTITY_ID" --registry-server "$REGISTRY" --registry-identity "$IDENTITY_ID" \
    --ingress external --target-port 3007 --transport http \
    --cpu 0.25 --memory 0.5Gi --min-replicas 1 --max-replicas 1 \
    --secrets database-url="$DATABASE_URL" jwt-secret="$JWT_SECRET" \
      admin-password="$ADMIN_PASSWORD" resend-key="$RESEND_API_KEY" \
    --env-vars PORT=3007 ADMIN_USERNAME=admin DATABASE_URL=secretref:database-url \
      JWT_SECRET=secretref:jwt-secret ADMIN_PASSWORD=secretref:admin-password \
      RESEND_API_KEY=secretref:resend-key -o none
fi
BACKEND_FQDN=$(az containerapp show -g "$RG" -n backend \
  --query properties.configuration.ingress.fqdn -o tsv)

echo "==> Frontend"
if az containerapp show -g "$RG" -n frontend >/dev/null 2>&1; then
  az containerapp update -g "$RG" -n frontend --image "$REGISTRY/quiz-frontend:$TAG" \
    --set-env-vars BACKEND_SCHEME=https BACKEND_HOST="$BACKEND_FQDN" BACKEND_PORT=443 -o none
else
  az containerapp create -g "$RG" -n frontend --environment "$ENV_NAME" \
    --image "$REGISTRY/quiz-frontend:$TAG" \
    --user-assigned "$IDENTITY_ID" --registry-server "$REGISTRY" --registry-identity "$IDENTITY_ID" \
    --ingress external --target-port 8080 --transport http \
    --cpu 0.25 --memory 0.5Gi --min-replicas 1 --max-replicas 1 \
    --env-vars BACKEND_SCHEME=https BACKEND_HOST="$BACKEND_FQDN" BACKEND_PORT=443 -o none
fi

FRONT_FQDN=$(az containerapp show -g "$RG" -n frontend \
  --query properties.configuration.ingress.fqdn -o tsv)
echo "Frontend : https://$FRONT_FQDN"
sleep 30
curl -fsS -m 20 "https://$FRONT_FQDN/health" && echo
echo "Rappel : le schéma de la base (database/init.sql) se crée une seule fois, à la main, avec psql."
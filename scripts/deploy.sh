#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Déploiement de Quiz App sur Azure (J3 + J4)
#
#   1. Groupe de ressources + Azure Container Registry (ACR)
#   2. Build des images, tag = commit Git, push dans ACR
#   3. Environnement Azure Container Apps (+ Log Analytics)
#   4. Container App backend  (ingress INTERNE, port 3007)
#   5. Container App frontend (ingress EXTERNE, port 8080)
#
# Script idempotent : relancé, il met à jour les applications existantes
# (nouvelle image => nouvelle révision).
#
# Prérequis : az (connecté : az login), docker, git.
# Secrets   : lus dans l'environnement ou dans le fichier .env.azure
#             (ignoré par Git, voir scripts/env.azure.example).
#             Aucun secret n'est écrit dans ce script.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Chargement optionnel des secrets depuis .env.azure (non versionné)
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env.azure}"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

# ---- Paramètres (surchargeables par variables d'environnement) --------------
LOCATION="${LOCATION:-francecentral}"        # régions autorisées : policy Azure for Students
RG="${RG:-rg-quiz-app}"
ACR_NAME="${ACR_NAME:-acrquizbenyoucefkemia}" # unique dans tout Azure, alphanumérique
ENV_NAME="${ENV_NAME:-cae-quiz-app}"
BACKEND_APP="${BACKEND_APP:-quiz-backend}"
FRONTEND_APP="${FRONTEND_APP:-quiz-frontend}"
MIN_REPLICAS="${MIN_REPLICAS:-0}"            # 0 = scale-to-zero (économie de crédits)

# Tag traçable : commit Git (+ "-dirty" si modifications non commitées)
TAG="${TAG:-$(git rev-parse --short HEAD)}"
if [[ -n "$(git status --porcelain)" && "$TAG" != *-dirty ]]; then
  TAG="${TAG}-dirty"
fi

# Configuration applicative
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
FROM_EMAIL="${FROM_EMAIL:-}"
DATABASE_URL="${DATABASE_URL:-}"   # optionnel au J4, requis au J5 (Neon)

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mERREUR : %s\033[0m\n' "$*" >&2; exit 1; }

# ---- Vérifications -----------------------------------------------------------
for cmd in az docker git curl; do
  command -v "$cmd" >/dev/null || fail "commande '$cmd' introuvable"
done
for var in JWT_SECRET ADMIN_PASSWORD RESEND_API_KEY; do
  [[ -n "${!var:-}" ]] || fail "variable $var manquante (environnement ou $ENV_FILE)"
done
az account show >/dev/null 2>&1 || fail "non connecté à Azure : lancez 'az login'"

log "Abonnement : $(az account show --query name -o tsv) | région : $LOCATION | tag : $TAG"
az extension add --name containerapp --upgrade --only-show-errors --yes

# ---- 1. Groupe de ressources + ACR -----------------------------------------
log "Groupe de ressources $RG"
az group create --name "$RG" --location "$LOCATION" --output none

log "Azure Container Registry $ACR_NAME (SKU Basic, compte admin désactivé)"
if ! az acr show --name "$ACR_NAME" --resource-group "$RG" --output none 2>/dev/null; then
  az acr create --name "$ACR_NAME" --resource-group "$RG" --location "$LOCATION" \
    --sku Basic --admin-enabled false --output none
fi
ACR_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"

# ---- 2. Build + push des images ---------------------------------------------
BACKEND_IMAGE="$ACR_SERVER/quiz-backend:$TAG"
FRONTEND_IMAGE="$ACR_SERVER/quiz-frontend:$TAG"

log "Connexion Docker à $ACR_SERVER (jeton Entra ID temporaire)"
az acr login --name "$ACR_NAME"

log "Build + push $BACKEND_IMAGE"
docker build --pull -t "$BACKEND_IMAGE" ./backend
docker push "$BACKEND_IMAGE"

log "Build + push $FRONTEND_IMAGE"
docker build --pull -t "$FRONTEND_IMAGE" .
docker push "$FRONTEND_IMAGE"

# ---- 3. Environnement Container Apps ------------------------------------------
log "Environnement Container Apps $ENV_NAME"
if ! az containerapp env show --name "$ENV_NAME" --resource-group "$RG" --output none 2>/dev/null; then
  # Mode WorkloadProfiles (profil "Consumption" facturé à l'usage) et non le mode
  # "Express" par défaut : Express refuse l'identité managée pour tirer depuis ACR
  # (erreur ExpressRegistrySystemIdentityNotSupported).
  # Crée aussi un espace Log Analytics dans le même groupe (logs des révisions).
  az containerapp env create --name "$ENV_NAME" --resource-group "$RG" \
    --location "$LOCATION" --environment-mode WorkloadProfiles \
    --logs-destination log-analytics --output none
fi
ENV_MODE="$(az containerapp env show --name "$ENV_NAME" --resource-group "$RG" \
  --query properties.environmentMode -o tsv)"
[[ "$ENV_MODE" != "Express" ]] || fail "l'environnement $ENV_NAME est en mode Express \
(incompatible avec l'identité managée ACR) : supprimez-le puis relancez le script"

# ---- 4. Backend (ingress interne) --------------------------------------------
# Les secrets sont stockés comme secrets de la Container App et injectés
# via "secretref:" : ils n'apparaissent pas en clair dans la configuration.
BACKEND_SECRETS=(
  "jwt-secret=$JWT_SECRET"
  "admin-password=$ADMIN_PASSWORD"
  "resend-api-key=$RESEND_API_KEY"
)
BACKEND_ENV=(
  "PORT=3007"
  "NODE_ENV=production"
  "ADMIN_USERNAME=$ADMIN_USERNAME"
  "JWT_SECRET=secretref:jwt-secret"
  "ADMIN_PASSWORD=secretref:admin-password"
  "RESEND_API_KEY=secretref:resend-api-key"
)
[[ -n "$FROM_EMAIL" ]] && BACKEND_ENV+=("FROM_EMAIL=$FROM_EMAIL")
if [[ -n "$DATABASE_URL" ]]; then
  BACKEND_SECRETS+=("database-url=$DATABASE_URL")
  BACKEND_ENV+=("DATABASE_URL=secretref:database-url")
fi

log "Container App backend $BACKEND_APP ($BACKEND_IMAGE)"
if az containerapp show --name "$BACKEND_APP" --resource-group "$RG" --output none 2>/dev/null; then
  az containerapp secret set --name "$BACKEND_APP" --resource-group "$RG" \
    --secrets "${BACKEND_SECRETS[@]}" --output none
  az containerapp update --name "$BACKEND_APP" --resource-group "$RG" \
    --image "$BACKEND_IMAGE" --set-env-vars "${BACKEND_ENV[@]}" \
    --revision-suffix "r${TAG//[^a-z0-9]/}-$(date +%s)" --output none
else
  # --registry-identity system : identité managée + rôle AcrPull,
  # aucun mot de passe de registre n'est stocké.
  az containerapp create --name "$BACKEND_APP" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$BACKEND_IMAGE" \
    --registry-server "$ACR_SERVER" --registry-identity system \
    --ingress internal --target-port 3007 \
    --cpu 0.25 --memory 0.5Gi --min-replicas "$MIN_REPLICAS" --max-replicas 1 \
    --secrets "${BACKEND_SECRETS[@]}" --env-vars "${BACKEND_ENV[@]}" \
    --output none
fi

# ---- 5. Frontend (ingress externe) --------------------------------------------
# Dans un même environnement, une app joint une autre par http://<nom-app>
# (port 80, routé par Envoy vers le target-port 3007 du backend).
FRONTEND_ENV=("BACKEND_URL=http://$BACKEND_APP")

log "Container App frontend $FRONTEND_APP ($FRONTEND_IMAGE)"
if az containerapp show --name "$FRONTEND_APP" --resource-group "$RG" --output none 2>/dev/null; then
  az containerapp update --name "$FRONTEND_APP" --resource-group "$RG" \
    --image "$FRONTEND_IMAGE" --set-env-vars "${FRONTEND_ENV[@]}" \
    --revision-suffix "r${TAG//[^a-z0-9]/}-$(date +%s)" --output none
else
  az containerapp create --name "$FRONTEND_APP" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$FRONTEND_IMAGE" \
    --registry-server "$ACR_SERVER" --registry-identity system \
    --ingress external --target-port 8080 \
    --cpu 0.25 --memory 0.5Gi --min-replicas "$MIN_REPLICAS" --max-replicas 1 \
    --env-vars "${FRONTEND_ENV[@]}" \
    --output none
fi

# ---- Vérification ------------------------------------------------------------
FQDN="$(az containerapp show --name "$FRONTEND_APP" --resource-group "$RG" \
  --query properties.configuration.ingress.fqdn -o tsv)"

log "Test de https://$FQDN/health (frontend -> backend)"
for i in {1..12}; do
  if body="$(curl -fsS --max-time 20 "https://$FQDN/health")"; then
    echo "HTTP 200 : $body"; break
  fi
  echo "tentative $i/12 : pas encore prêt (démarrage à froid), nouvel essai dans 10 s"
  sleep 10
done

log "Terminé"
echo "Frontend : https://$FQDN"
echo "Images   : $BACKEND_IMAGE"
echo "           $FRONTEND_IMAGE"

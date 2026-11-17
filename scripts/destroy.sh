#!/usr/bin/env bash
# =============================================================================
# destroy.sh — Suppression de TOUTES les ressources Azure de Quiz App
#
# Supprime le groupe de ressources entier : ACR (et ses images), environnement
# Container Apps, Container Apps, Log Analytics. Opération IRRÉVERSIBLE.
# À lancer seulement après avoir sauvegardé les preuves et avec l'accord du formateur.
#
# Usage : ./scripts/destroy.sh            (demande confirmation)
#         RG=autre-groupe ./scripts/destroy.sh
# =============================================================================
set -euo pipefail

RG="${RG:-rg-quiz-app}"

az account show >/dev/null 2>&1 || { echo "Non connecté à Azure : lancez 'az login'" >&2; exit 1; }

if ! az group show --name "$RG" --output none 2>/dev/null; then
  echo "Le groupe de ressources '$RG' n'existe pas : rien à supprimer."
  exit 0
fi

echo "Ressources qui seront supprimées dans '$RG' :"
az resource list --resource-group "$RG" --query "[].{nom:name, type:type}" -o table

read -r -p "Taper le nom du groupe ('$RG') pour confirmer : " answer
[[ "$answer" == "$RG" ]] || { echo "Annulé."; exit 1; }

az group delete --name "$RG" --yes --no-wait
echo "Suppression de '$RG' lancée (quelques minutes)."
echo "Suivi : az group show --name $RG --query properties.provisioningState -o tsv"

#!/usr/bin/env bash
# Supprime le groupe de ressources et tout ce qu'il contient (ACR, environnement, apps, identités).
# À lancer seulement après sauvegarde des preuves et accord du formateur.
set -euo pipefail

RG="${RG:-rg-quiz-app}"
echo "Suppression de $RG : registre, environnement, apps, identités et secrets seront perdus."
read -r -p "Tape le nom du groupe pour confirmer : " CONFIRM
[ "$CONFIRM" = "$RG" ] || { echo "Annulé."; exit 1; }
az group delete --name "$RG" --yes --no-wait
echo "Suppression lancée (quelques minutes)."
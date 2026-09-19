#!/usr/bin/env bash
set -euo pipefail

STATUS="${1:-applied}"
REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BETA_DIR="$REPO_ROOT/environments/beta"

TABLE_NAME="$(terraform -chdir="$BETA_DIR" output -raw beta_applicants_table_name)"
VALUES="$(printf '{\":status\":{\"S\":\"%s\"}}' "$STATUS")"

aws dynamodb query \
  --region "$REGION" \
  --table-name "$TABLE_NAME" \
  --index-name status-createdAt \
  --key-condition-expression '#status = :status' \
  --expression-attribute-names '{"#status":"status"}' \
  --expression-attribute-values "$VALUES" \
  --no-scan-index-forward \
  --query 'Items[].{Email:email.S,Status:status.S,Created:createdAt.S,Platform:platform.S,Vehicle:vehicleModel.S,Phone:deviceModel.S,Android:androidVersion.S,Battery:batteryVoltage.S,Region:region.S,FirstAd:firstAdId.S,LatestAd:latestAdId.S}' \
  --output table

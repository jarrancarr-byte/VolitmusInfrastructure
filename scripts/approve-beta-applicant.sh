#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 rider@example.com" >&2
  exit 2
fi

EMAIL="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | xargs)"
REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BETA_DIR="$REPO_ROOT/environments/beta"

TABLE_NAME="$(terraform -chdir="$BETA_DIR" output -raw beta_applicants_table_name)"
USER_POOL_ID="$(terraform -chdir="$BETA_DIR" output -raw cognito_user_pool_id)"
KEY="$(printf '{\"email\":{\"S\":\"%s\"}}' "$EMAIL")"

ITEM_COUNT="$(aws dynamodb get-item \
  --region "$REGION" \
  --table-name "$TABLE_NAME" \
  --key "$KEY" \
  --consistent-read \
  --query 'length(Item)' \
  --output text)"

if [[ "$ITEM_COUNT" == "0" || "$ITEM_COUNT" == "None" ]]; then
  echo "No beta application exists for $EMAIL" >&2
  exit 1
fi

STATUS="$(aws dynamodb get-item \
  --region "$REGION" \
  --table-name "$TABLE_NAME" \
  --key "$KEY" \
  --consistent-read \
  --query 'Item.status.S' \
  --output text)"

if [[ "$STATUS" == "invited" || "$STATUS" == "active" ]]; then
  echo "$EMAIL is already $STATUS. No new invitation was sent."
  exit 0
fi

if [[ "$STATUS" != "applied" && "$STATUS" != "approved" ]]; then
  echo "Applicant status '$STATUS' is not eligible for Android beta invitation." >&2
  exit 1
fi

if ! aws cognito-idp admin-get-user \
  --region "$REGION" \
  --user-pool-id "$USER_POOL_ID" \
  --username "$EMAIL" >/dev/null 2>&1; then

  echo "Creating Cognito beta user and sending invitation..."
  aws cognito-idp admin-create-user \
    --region "$REGION" \
    --user-pool-id "$USER_POOL_ID" \
    --username "$EMAIL" \
    --user-attributes "Name=email,Value=$EMAIL" "Name=email_verified,Value=true" \
    --desired-delivery-mediums EMAIL >/dev/null
else
  echo "Cognito user already exists; keeping the existing user."
fi

NOW="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
VALUES="$(printf '{\":status\":{\"S\":\"invited\"},\":now\":{\"S\":\"%s\"}}' "$NOW")"

aws dynamodb update-item \
  --region "$REGION" \
  --table-name "$TABLE_NAME" \
  --key "$KEY" \
  --update-expression 'SET #status = :status, invitedAt = :now, updatedAt = :now' \
  --expression-attribute-names '{"#status":"status"}' \
  --expression-attribute-values "$VALUES" >/dev/null

echo "Done. $EMAIL is now marked invited."

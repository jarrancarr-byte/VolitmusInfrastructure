#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BETA_DIR="$REPO_ROOT/environments/beta"
BASE_URL="${1:-$(terraform -chdir="$BETA_DIR" output -raw beta_api_base_url)}"
BASE_URL="${BASE_URL%/}"

echo "GET $BASE_URL/health"
curl --fail --silent --show-error "$BASE_URL/health"
echo

echo "GET $BASE_URL/mobile-config"
curl --fail --silent --show-error "$BASE_URL/mobile-config"
echo

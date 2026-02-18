#!/bin/bash

# -x echos all lines for debug
# set -x

set -o errexit -o nounset -o pipefail
command -v shellcheck >/dev/null && shellcheck "$0"

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
# shellcheck source=../helper.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../helper.sh"

# shellcheck source=./foundry_profile.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/./foundry_profile.sh"

# Parse command line arguments in key=value format
parse_args "$@"

# Check required parameters with defaults
check_param "DEPLOY_ENV" "${DEPLOY_ENV:-LOCAL}"

DEFAULT_POA_STAKER_REGISTRY=$(jq -r '.addresses.POAStakeRegistry' "$HOME/.nodes/poa_deploy.json" 2>/dev/null || true)
check_param "POA_STAKER_REGISTRY_ADDRESS" "${POA_STAKER_REGISTRY_ADDRESS:-$DEFAULT_POA_STAKER_REGISTRY}"

# Set up environment based on DEPLOY_ENV
setup_environment

# Read the operator private key
check_param "OPERATOR_KEY" "${OPERATOR_KEY:-$1}"
operator_address=$(cast wallet address "$OPERATOR_KEY")
echo "Operator address: $operator_address"

ensure_balance "$operator_address"

# BLS key and signature proof must be provided as hex-encoded bytes
check_param "BLS_PUBKEY" "${BLS_PUBKEY:-$2}"
check_param "BLS_SIG_PROOF" "${BLS_SIG_PROOF:-$3}"

echo "Updating BLS signing key"
cast send "$POA_STAKER_REGISTRY_ADDRESS" "updateOperatorSigningKey(bytes,bytes)" "$BLS_PUBKEY" "$BLS_SIG_PROOF" --private-key "$OPERATOR_KEY" --rpc-url "$RPC_URL"

echo "BLS signing key updated successfully"

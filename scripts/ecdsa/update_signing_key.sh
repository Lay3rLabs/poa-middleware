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

# Read the deployer private key
check_param "OPERATOR_KEY" "${OPERATOR_KEY:-$1}"
operator_address=$(cast wallet address "$OPERATOR_KEY")
echo "Operator address: $operator_address"

ensure_balance "$operator_address"

check_param "SIGNING_KEY" "${SIGNING_KEY:-$1}"
signing_address=$(cast wallet address "$SIGNING_KEY")
echo "Signing address: $signing_address"

encoded_operator_address=$(cast abi-encode "f(address)" "$operator_address")
signing_message=$(cast keccak "$encoded_operator_address")
signing_signature=$(cast wallet sign --no-hash --private-key "$SIGNING_KEY" "$signing_message")
echo "Signing signature: $signing_signature"

echo "Updating signing key"
cast send "$POA_STAKER_REGISTRY_ADDRESS" "updateOperatorSigningKey(address,bytes)" "$signing_address" "$signing_signature" --private-key "$OPERATOR_KEY" --rpc-url "$RPC_URL"

echo "Signing key updated successfully"

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
check_param "FUNCTION_NAME" "${FUNCTION_NAME:-$1}"

echo "FUNCTION_NAME: $FUNCTION_NAME"

DEFAULT_POA_STAKER_REGISTRY=$(jq -r '.addresses.POAStakeRegistry' "$HOME/.nodes/poa_deploy.json" 2>/dev/null || true)
check_param "POA_STAKER_REGISTRY_ADDRESS" "${POA_STAKER_REGISTRY_ADDRESS:-$DEFAULT_POA_STAKER_REGISTRY}"

# Set up environment based on DEPLOY_ENV
setup_environment

# Read the deployer private key
deployer_private_key=$(load_deployment_data "$HOME/.nodes/deployer")
check_param "FUNDED_KEY" "${FUNDED_KEY:-$deployer_private_key}"
deployer_address=$(cast wallet address "$FUNDED_KEY")
echo "Deployer address: $deployer_address"

ensure_balance "$deployer_address"

if [ "$FUNCTION_NAME" == "registerOperator" ]; then
    check_param "OPERATOR_ADDRESS" "${OPERATOR_ADDRESS:-$2}"
    check_param "WEIGHT" "${WEIGHT:-$3}"
    echo "Registering operator"
    cast send "$POA_STAKER_REGISTRY_ADDRESS" "registerOperator(address,uint256)" "$OPERATOR_ADDRESS" "$WEIGHT" --private-key "$FUNDED_KEY" --rpc-url "$RPC_URL"

    echo "Operator registered successfully"
fi

if [ "$FUNCTION_NAME" == "deregisterOperator" ]; then
    check_param "OPERATOR_ADDRESS" "${OPERATOR_ADDRESS:-$2}"
    echo "Deregistering operator"
    cast send "$POA_STAKER_REGISTRY_ADDRESS" "deregisterOperator(address)" "$OPERATOR_ADDRESS" --private-key "$FUNDED_KEY" --rpc-url "$RPC_URL"

    echo "Operator deregistered successfully"
fi

if [ "$FUNCTION_NAME" == "updateOperatorWeight" ]; then
    check_param "OPERATOR_ADDRESS" "${OPERATOR_ADDRESS:-$2}"
    check_param "WEIGHT" "${WEIGHT:-$3}"
    echo "Updating operator weight"
    cast send "$POA_STAKER_REGISTRY_ADDRESS" "updateOperatorWeight(address,uint256)" "$OPERATOR_ADDRESS" "$WEIGHT" --private-key "$FUNDED_KEY" --rpc-url "$RPC_URL"

    echo "Operator weight updated successfully"
fi

if [ "$FUNCTION_NAME" == "updateStakeThreshold" ]; then
    check_param "THRESHOLD_WEIGHT" "${THRESHOLD_WEIGHT:-$2}"
    echo "Updating stake threshold"
    cast send "$POA_STAKER_REGISTRY_ADDRESS" "updateStakeThreshold(uint256)" "$THRESHOLD_WEIGHT" --private-key "$FUNDED_KEY" --rpc-url "$RPC_URL"

    echo "Stake threshold updated successfully"
fi

if [ "$FUNCTION_NAME" == "updateQuorum" ]; then
    check_param "QUORUM_NUMERATOR" "${QUORUM_NUMERATOR:-$2}"
    check_param "QUORUM_DENOMINATOR" "${QUORUM_DENOMINATOR:-$3}"
    echo "Updating quorum"
    cast send "$POA_STAKER_REGISTRY_ADDRESS" "updateQuorum(uint256,uint256)" "$QUORUM_NUMERATOR" "$QUORUM_DENOMINATOR" --private-key "$FUNDED_KEY" --rpc-url "$RPC_URL"

    echo "Quorum updated successfully"
fi

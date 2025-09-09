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

# Check required environment variables (secrets) - no defaults for security
check_env_var "FUNDED_KEY" "${FUNDED_KEY:-}"

# Set up environment based on DEPLOY_ENV
setup_environment

#############################################
###### Start of script execution ############
#############################################

# Create necessary directories
ensure_dir "$HOME/.nodes"

# Get deployer address and save private key
deployer_address=$(cast wallet address "$FUNDED_KEY")
save_deployment_data "$HOME/.nodes/deployer" "$FUNDED_KEY"

# Ensure deployer has sufficient balance
ensure_balance "$deployer_address"

echo "Deployer address: $deployer_address configured for $DEPLOY_ENV environment"

cd contracts || handle_error "Failed to change to contracts directory"
forge script script/ecdsa/POAMiddlewareDeployer.s.sol --rpc-url "$RPC_URL" --private-key "$FUNDED_KEY" -vvv --broadcast --skip-simulation || handle_error "Failed to deploy POAMiddlewareDeployer"

echo "Middleware contracts deployed with addresses:"
cat deployments/poa-ecdsa/poa_deploy.json | jq .addresses

# Save deployment data
cp deployments/poa-ecdsa/poa_deploy.json "$HOME/.nodes/poa_deploy.json"

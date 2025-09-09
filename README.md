# POA Middleware

POA Middleware contracts for stake registry management with ECDSA signature support.

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- [Node.js](https://nodejs.org/) and npm
- Git

## Setup

1. **Install dependencies:**
```bash
npm install
```

## Running Local Development

### 1. Start Anvil Instance

```bash
anvil
```

This will start a local blockchain at `http://127.0.0.1:8545` with 10 test accounts pre-funded with ETH.

### 2. Build Contracts

Build the contracts using the ECDSA profile:

```bash
FOUNDRY_PROFILE=ecdsa forge build --root contracts
```

### 3. Deploy Stake Registry

Deploy the POA Stake Registry using the deployment script:

```bash
cd contracts
FOUNDRY_PROFILE=ecdsa forge script script/ecdsa/POAMiddlewareDeployer.s.sol:POAMiddlewareDeployer \
  --fork-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

**Note:** The private key above is Anvil's first default account. For production, use your own private key.

This will:
- Deploy a proxy admin contract
- Deploy the POAStakeRegistry implementation
- Set up an upgradeable proxy pointing to the implementation
- Initialize the stake registry with parameters: `(100, 1, 1)`
- Save deployment addresses to `deployments/poa-ecdsa/poa_deploy.json`

## Testing

Run tests:

```bash
FOUNDRY_PROFILE=ecdsa forge test --root contracts
```

# POA Middleware

[**v1.0.1 Audited by Hashlock** (September 20th, 2025)](./audits/POA-Middleware-v1_0_0.pdf)

A Proof of Authority (POA) middleware system for managing operator registration, stake tracking, and signature validation using ECDSA signatures. This middleware provides a lightweight alternative to traditional EigenLayer-based AVS systems by implementing a simplified stake registry with quorum-based validation.

## Prerequisites

- Docker and Docker Compose
- Foundry (Forge and Cast) for local development and testing
- Node.js and npm for dependency management

## Testing

To run the test suite, make sure you have [Foundry](https://book.getfoundry.sh/) installed. Then run:

```bash
# Run all tests
make test

# Run ECDSA tests only
make test-ecdsa

# Generate coverage report
make coverage-html-ecdsa
```

## Docker Quick Start

### Build

First, ensure you have all dependencies:

```bash
npm install
```

Then, build the image:

```bash
docker build -t poa-middleware .
```

### Setup

Prepare the env file:

```bash
CHAIN=holesky
cp docker/env.example.$CHAIN docker/.env
# edit the RPC_URL, DEPLOY_ENV for a paid testnet rpc endpoint.
# edit the FORK_RPC_URL for local deployment.
```

## Testnet Fork

Start anvil in one terminal:

```bash
source docker/.env
anvil --fork-url $FORK_RPC_URL --host 0.0.0.0 --port 8545
```

## Commands

**Run all the following scripts in the `docker/` directory.**

```bash
cd docker/
```

### Deploy Contracts

Deploys the POA middleware contracts.

```bash
docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware deploy
```

| Environment Variable | Required              | Default                 | Source | Description                                   |
| -------------------- | --------------------- | ----------------------- | ------ | --------------------------------------------- |
| `DEPLOY_ENV`         | for non-default value | `LOCAL`                 | `.env` | Deployment environment (`LOCAL` or `TESTNET`) |
| `RPC_URL`            | for non-default value | `http://localhost:8545` | `.env` | RPC URL                                       |
| `FUNDED_KEY`         | Yes                   | -                       | `.env` | Private key with funds for deployment         |

### Register Operator

Registers an operator with the POA stake registry.

```bash
OPERATOR_KEY=$(cast wallet new --json | jq -r '.[0].private_key')
OPERATOR_ADDRESS=$(cast wallet addr --private-key "$OPERATOR_KEY")
echo "Operator address: $OPERATOR_ADDRESS"

SIGNING_KEY=$(cast wallet new --json | jq -r '.[0].private_key')
SIGNING_ADDRESS=$(cast wallet addr --private-key "$SIGNING_KEY")
echo "Signing address: $SIGNING_ADDRESS"

docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation registerOperator $OPERATOR_ADDRESS 10000
```

### Update Operator Weight

Updates the weight of a registered operator.

```bash
docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation updateOperatorWeight $OPERATOR_ADDRESS 1000
```

### Update Signing Key

Updates the signing key for an operator.

```bash
docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware update_signing_key $OPERATOR_KEY $SIGNING_ADDRESS
```

### Deregister Operator

Deregisters an operator from the POA stake registry.

```bash
docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation deregisterOperator $OPERATOR_ADDRESS
```

### Update Stake Threshold

Updates the minimum stake threshold required for validation.

```bash
docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation updateStakeThreshold 100
```

### Update Quorum

Updates the quorum configuration for signature validation.

```bash
docker run --rm --network host -v ./.nodes:/root/.nodes \
   --env-file .env \
   poa-middleware owner_operation updateQuorum 3 5
```

| Environment Variable | Required              | Default                 | Source       | Description                                   |
| -------------------- | --------------------- | ----------------------- | ------------ | --------------------------------------------- |
| `DEPLOY_ENV`         | for non-default value | `LOCAL`                 | `.env`       | Deployment environment (`LOCAL` or `TESTNET`) |
| `RPC_URL`            | for non-default value | `http://localhost:8545` | `.env`       | RPC URL                                       |
| `OPERATOR_KEY`       | Yes                   | -                       | Command line | Private key for the operator                  |
| `SIGNING_ADDRESS`    | Yes                   | -                       | Command line | Address of the signing key                    |

## Architecture

### Core Components

1. **POAStakeRegistry**: Main contract managing operator registration and stake tracking
2. **POAStakeRegistryStorage**: Storage layer for historical data using OpenZeppelin Checkpoints
3. **IPOAStakeRegistry**: Interface defining all contract functions and events

### Key Features

- **Operator Management**: Register, deregister, and update operator weights
- **Signing Key Management**: Operators can update their signing keys
- **Stake Tracking**: Historical tracking of operator weights and total stake
- **Quorum Validation**: Configurable quorum requirements for signature validation
- **ECDSA Signature Verification**: Validates signatures against registered signing keys
- **Threshold Management**: Configurable minimum stake thresholds

### Signature Validation

The system validates ECDSA signatures by:

1. Verifying signatures against registered signing keys
2. Checking that signers are sorted in ascending order
3. Ensuring sufficient stake weight has signed
4. Validating against quorum requirements
5. Checking threshold requirements

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

POA (Proof of Authority) middleware for WAVS/EigenLayer AVS systems. Implements a lightweight stake registry with quorum-based ECDSA signature validation using ERC1271. Audited by Hashlock (v1.0.1). Solidity 0.8.27, built with Foundry.

## Build & Test Commands

All Foundry commands run from the `contracts/` directory using Makefile targets:

```bash
# Install dependencies (from repo root)
npm install

# Build
cd contracts && make build-ecdsa        # Build ECDSA contracts
cd contracts && make build              # Build all profiles (bls + ecdsa)

# Test
cd contracts && make test-ecdsa         # Run ECDSA tests (forge test -vv)
cd contracts && make test               # Run all profile tests

# Run a single test
cd contracts && FOUNDRY_PROFILE=ecdsa forge test --match-test testFunctionName -vv

# Gas reports
cd contracts && make gas-ecdsa

# Coverage
cd contracts && make coverage-html-ecdsa   # Generates HTML at coverage-report-ecdsa/

# Formatting
cd contracts && make format             # Auto-format with forge fmt
cd contracts && make format-check       # Check formatting

# Linting (from repo root)
npm run lint                            # solhint on all .sol files
npm run lint:fix                        # Auto-fix lint issues

# Storage layout inspection
cd contracts && make inspect-ecdsa contract=POAStakeRegistry
```

## Architecture

### Multi-Profile Build System

Foundry is configured with separate profiles in `contracts/foundry.toml`:
- **ecdsa** — Current production profile. Source in `src/ecdsa/`, tests in `test/ecdsa/`, output in `out/ecdsa/`.
- **bls** — Planned future profile for BLS signature verification. Same directory convention under `src/bls/`, `test/bls/`, etc.

All `make` targets are suffixed by profile (e.g., `test-ecdsa`, `build-bls`). The unsuffixed targets run both profiles.

### Contract Structure

**POAStakeRegistry** (`contracts/src/ecdsa/POAStakeRegistry.sol`) — Main contract. Upgradeable (OwnableUpgradeable + initializer pattern). Implements ERC1271 `isValidSignature`. Core responsibilities:
- Operator registration/deregistration
- Signing key management (operators update their own keys)
- Weight tracking per operator
- Quorum and threshold configuration (owner-only)
- Signature validation: recovers signers from ECDSA signatures, checks registration, aggregates weights, validates against quorum and threshold at a given reference block

**POAStakeRegistryStorage** (`contracts/src/ecdsa/POAStakeRegistryStorage.sol`) — Separated storage contract for upgrade safety. All historical state uses `Checkpoints.Trace160` for point-in-time lookups by block number. Includes a 40-slot storage gap for future fields.

**Interfaces** (`contracts/src/ecdsa/interfaces/`):
- `IPOAStakeRegistry` — Public interface, custom errors, and events
- `IWavsServiceManager` / `IWavsServiceHandler` — WAVS integration types (Envelope, SignatureData structs)

### Key Design Patterns

- **Checkpoint history**: All state (weights, signing keys, quorum, threshold) is tracked per-block via `Checkpoints.Trace160`, enabling signature validation at past block numbers.
- **Sorted signers**: `_checkSignatures` requires signers in ascending address order to prevent duplicates.
- **Proxy/upgradeable**: Deployed via `UpgradeableProxyLib`. Constructor calls `_disableInitializers()`. State setup happens in `initialize()`.

### Deployment & Docker

The Docker image provides a CLI (`scripts/cli.sh`) for deployment and operations. Scripts in `scripts/ecdsa/` handle `deploy`, `owner_operation`, and `update_signing_key`. Key env vars: `RPC_URL`, `DEPLOY_ENV` (LOCAL/TESTNET), `FUNDED_KEY`, `OPERATOR_KEY`.

### Dependency Remappings

Defined in `contracts/remappings.txt`. Libraries live in `node_modules/` (not Foundry's `lib/`):
- `@openzeppelin/` → `../node_modules/@openzeppelin/`
- `forge-std/` → `../node_modules/forge-std/src/`
- `@wavs/` → `../node_modules/@wavs/solidity/contracts/`

### Formatting Conventions

Forge fmt config: 100 char line length, `params_first` multiline function headers, thousands underscores for number literals.

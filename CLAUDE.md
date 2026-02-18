# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

POA (Proof of Authority) middleware for WAVS/EigenLayer AVS systems. Implements a lightweight stake registry with quorum-based ECDSA signature validation using ERC1271. Audited by Hashlock (v1.0.1). Solidity 0.8.27, built with Foundry.

## Build & Test Commands

All commands run from the repo root. Task runner is `just` (justfile at root). Foundry config is at root `foundry.toml`.

```bash
# Install dependencies
npm install

# Build
just build                              # Build ECDSA contracts (default profile)
just build-all                          # Build all profiles (bls + ecdsa)

# Test
just test                               # Run ECDSA tests (forge test -vv)
just test-all                           # Run all profile tests

# Run a single test
just test-match testFunctionName

# Gas reports
just gas

# Coverage
just coverage-html                      # Generates HTML at coverage-report-ecdsa/

# Formatting
just format                             # Auto-format with forge fmt
just format-check                       # Check formatting

# Linting
just lint                               # solhint on all .sol files
just lint-fix                           # Auto-fix lint issues

# Contract sizes
just size

# Storage layout inspection
just inspect POAStakeRegistry

# Direct forge commands also work from repo root
FOUNDRY_PROFILE=ecdsa forge test --match-test testFunctionName -vv
```

## Architecture

### Multi-Profile Build System

Foundry is configured with separate profiles in root `foundry.toml`:
- **ecdsa** — Current production profile. Source in `contracts/src/ecdsa/`, tests in `contracts/test/ecdsa/`, output in `contracts/out/ecdsa/`.
- **bls** — Planned future profile for BLS signature verification. Same directory convention under `contracts/src/bls/`, `contracts/test/bls/`, etc.

The default `just` profile is `ecdsa`. Override with `just profile=bls build`.

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

Defined inline in root `foundry.toml`. Libraries live in `node_modules/` (not Foundry's `lib/`):
- `@openzeppelin/` → `node_modules/@openzeppelin/`
- `forge-std/` → `node_modules/forge-std/src/`
- `@wavs/` → `node_modules/@wavs/solidity/contracts/`
- `src/` → `contracts/src/` (so Solidity imports like `"src/ecdsa/..."` resolve correctly)
- `script/` → `contracts/script/`

### Formatting Conventions

Forge fmt config: 100 char line length, `params_first` multiline function headers, thousands underscores for number literals.

# Improvements

## Create BLS version of PoA contracts

Currently we're using ECDSA for PoA contracts. We plan to implement a BLS version of PoA contracts to improve security and efficiency.

It should leverage BLS precompiles for signature verification. Design and interfaces should match the existing PoA contracts.

## Move some wavs-middleware contracts and components to this repo

For syncing operators cross-chain, etc. Example: https://github.com/Lay3rLabs/wavs-middleware/blob/dev/contracts/src/eigenlayer/ecdsa/MirrorStakeRegistry.sol

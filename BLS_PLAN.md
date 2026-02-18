BLS12-381 POA Stake Registry Implementation Plan

 Context

 The project has an ECDSA-based POA Stake Registry at contracts/src/ecdsa/. We need a BLS12-381 version at contracts/src/bls/ that uses EIP-2537 precompiles for aggregate signature verification. The BLS profile is already configured in foundry.toml but the directories are empty.
 The goal is to mirror the ECDSA contract design while replacing ECDSA signature verification with BLS aggregate signature verification.

 Design decisions:
 - BLS12-381 curve with EIP-2537 precompiles
 - Public keys in G1 (128 bytes uncompressed), signatures in G2 (256 bytes uncompressed)
 - Single aggregate signature for all signers (the main efficiency benefit of BLS)
 - Target: any EVM chain with EIP-2537 support

 File Structure

 contracts/src/bls/
   POAStakeRegistry.sol                    # Main contract (mirrors ECDSA version)
   POAStakeRegistryStorage.sol             # Storage layout with BLS key support
   interfaces/
     IPOAStakeRegistry.sol                 # Interface, errors, events
     IWavsServiceHandler.sol               # BLS-specific SignatureData struct
     IWavsServiceManager.sol               # Service manager interface
   libs/
     BLS12381.sol                          # Precompile wrappers + aggregate verification
     HashToCurve.sol                       # expand_message_xmd + hash-to-G2 (RFC 9380)

 contracts/test/bls/
   POAStakeRegistry.t.sol                  # Integration tests (mirrors ECDSA test structure)
   BLS12381.t.sol                          # BLS library unit tests
   HashToCurve.t.sol                       # Hash-to-curve unit tests

 contracts/script/bls/
   POAMiddlewareDeployer.s.sol             # Deployment script
   utils/
     UpgradeableProxyLib.sol               # Copy from ecdsa
     EmptyContract.sol                     # Copy from ecdsa

 scripts/bls/
   foundry_profile.sh                      # export FOUNDRY_PROFILE=bls
   deploy.sh
   owner_operation.sh
   update_signing_key.sh

 1. foundry.toml Update

 Add evm_version = "prague" and remappings to the existing [profile.bls] section (EIP-2537 precompiles are a Prague EVM feature).

 File: /Users/jacobhartnell/Dev/Layer/poa-middleware/foundry.toml

 2. BLS12381 Library

 File: contracts/src/bls/libs/BLS12381.sol

 EIP-2537 Precompile Addresses (Pectra-final)

 G1ADD:          0x0b
 G1MSM:          0x0c   (handles single MUL when k=1)
 G2ADD:          0x0d
 G2MSM:          0x0e   (handles single MUL when k=1)
 PAIRING_CHECK:  0x0f
 MAP_FP_TO_G1:   0x10
 MAP_FP2_TO_G2:  0x11

 Key Functions

 - g1Add(bytes p1, bytes p2) -> bytes — Add two G1 points (128 + 128 -> 128 bytes)
 - g1Msm(bytes points_and_scalars) -> bytes — Multi-scalar multiplication in G1
 - g2Add(bytes p1, bytes p2) -> bytes — Add two G2 points (256 + 256 -> 256 bytes)
 - g2Msm(bytes points_and_scalars) -> bytes — Multi-scalar multiplication in G2
 - pairingCheck(bytes input) -> bool — Check e(P1,Q1) * e(P2,Q2) * ... == 1
 - mapFp2ToG2(bytes fp2) -> bytes — Map Fp2 element to G2 point

 Aggregate Signature Verification

 verifyAggregateSignature(aggregatedPubkey, messagePointG2, aggregateSignature):
   // Pairing equation: e(apk, H(m)) * e(-G1_gen, sig_agg) == 1
   input = [aggregatedPubkey || messagePointG2 || negG1Generator || aggregateSignature]
   return pairingCheck(input)   // 2-pair check, ~103k gas

 Constants: G1 generator point, negated G1 generator (precomputed p - y).

 3. HashToCurve Library

 File: contracts/src/bls/libs/HashToCurve.sol

 Implements BLS12381G2_XMD:SHA-256_SSWU_RO_ from RFC 9380 section 8.8.2.

 Algorithm

 hashToCurveG2(message):
   1. pseudoRandomBytes = expandMsgXmd(message, DST, 256)   // SHA-256 precompile (0x02)
   2. u0, u1 = hashToFieldFp2(pseudoRandomBytes)             // split + reduce mod p via MODEXP
   3. Q0 = MAP_FP2_TO_G2(u0)                                 // precompile 0x11
   4. Q1 = MAP_FP2_TO_G2(u1)                                 // precompile 0x11
   5. return G2ADD(Q0, Q1)                                    // precompile 0x0d

 Cofactor clearing: The MAP_FP2_TO_G2 precompile implements SWU map + isogeny + cofactor clearing per the EIP-2537 field-to-curve spec. If testing reveals the output is NOT in the subgroup, we'll add explicit cofactor clearing via scalar decomposition (splitting the ~76-byte G2
 effective cofactor into <=32-byte chunks and chaining G2MSM calls).

 Field reduction: hashToFieldFp2 produces 512-bit intermediates that must be reduced mod p (the 384-bit BLS12-381 base field prime). Uses the MODEXP precompile (0x05) with exponent=1 for efficient modular reduction.

 Gas Estimate (~55k)

 ┌─────────────────────────────┬────────┐
 │          Operation          │  Gas   │
 ├─────────────────────────────┼────────┤
 │ expandMsgXmd (9x SHA-256)   │ ~4,000 │
 ├─────────────────────────────┼────────┤
 │ 4x MODEXP (field reduction) │ ~800   │
 ├─────────────────────────────┼────────┤
 │ 2x MAP_FP2_TO_G2            │ 47,600 │
 ├─────────────────────────────┼────────┤
 │ 1x G2ADD                    │ 600    │
 ├─────────────────────────────┼────────┤
 │ Memory overhead             │ ~2,000 │
 └─────────────────────────────┴────────┘

 4. Storage Design

 File: contracts/src/bls/POAStakeRegistryStorage.sol

 BLS G1 public keys are 128 bytes and don't fit in Checkpoints.Trace160 (20 bytes). Solution: hash-indexed key storage with a custom checkpoint array for the forward mapping.

 // Full BLS key storage (keyhash -> 128-byte G1 key, permanent)
 mapping(bytes32 => bytes) internal _blsKeyStore;

 // Forward: operator -> BLS key history (custom checkpoint array)
 struct BLSKeyCheckpoint {
     uint96 blockNumber;
     bytes32 keyHash;        // keccak256(blsPublicKey)
 }
 mapping(address => BLSKeyCheckpoint[]) internal _operatorBLSKeyHistory;

 // Reverse: key hash -> operator history (Trace160 works since operator is uint160)
 mapping(bytes32 => Checkpoints.Trace160) internal _signingKeyOperatorHistory;

 // Everything else identical to ECDSA:
 Checkpoints.Trace160 internal _totalWeightHistory;
 Checkpoints.Trace160 internal _thresholdWeightHistory;
 Checkpoints.Trace160 internal _quorumNumeratorHistory;
 Checkpoints.Trace160 internal _quorumDenominatorHistory;
 mapping(address => Checkpoints.Trace160) internal _operatorWeightHistory;
 mapping(address => bool) internal _operatorRegistered;
 uint256 internal _totalOperators;
 string internal _serviceuri;
 uint256[40] private __gap;

 Binary search function _getOperatorKeyHashAtBlock(operator, blockNumber) implements upperLookup semantics on the BLSKeyCheckpoint[] array.

 5. Interface Changes from ECDSA

 Files: contracts/src/bls/interfaces/

 SignatureData (IWavsServiceHandler.sol)

 struct SignatureData {
     bytes[] signerPubkeys;     // Array of 128-byte G1 public keys
     bytes aggregateSignature;  // Single 256-byte G2 aggregate signature
     uint32 referenceBlock;
 }
 Changed from ECDSA: address[] signers + bytes[] signatures -> bytes[] signerPubkeys + bytes aggregateSignature

 IPOAStakeRegistry.sol — Changed Functions

 ┌─────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────┐
 │                        ECDSA                        │                            BLS                            │
 ├─────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
 │ updateOperatorSigningKey(address, bytes)            │ updateOperatorSigningKey(bytes blsKey, bytes blsSigProof) │
 ├─────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
 │ getLatestOperatorSigningKey(addr) -> address        │ getLatestOperatorSigningKey(addr) -> bytes                │
 ├─────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
 │ getOperatorSigningKeyAtBlock(addr, uint) -> address │ getOperatorSigningKeyAtBlock(addr, uint) -> bytes         │
 └─────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────┘

 IWavsServiceManager.sol — Changed Functions

 ┌────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────┐
 │                       ECDSA                        │                            BLS                             │
 ├────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────┤
 │ getLatestOperatorForSigningKey(address) -> address │ getLatestOperatorForSigningKey(bytes32 keyHash) -> address │
 └────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────┘

 New BLS-Specific Errors

 InvalidBLSKeyLength, InvalidBLSSignatureLength, InvalidBLSSignature, InvalidBLSKeyOwnershipProof, PrecompileCallFailed

 SigningKeyUpdate Event

 event SigningKeyUpdate(address indexed operator, uint256 indexed updateBlock,
                        bytes32 indexed newKeyHash, bytes32 oldKeyHash);
 Changed from ECDSA: address newSigningKey -> bytes32 newKeyHash

 Unchanged Functions

 registerOperator, deregisterOperator, updateOperatorWeight, updateStakeThreshold, updateQuorum, all weight/quorum/threshold view functions, operatorRegistered, setServiceURI, getServiceURI, EigenLayer stubs.

 6. Main Contract Signature Verification

 File: contracts/src/bls/POAStakeRegistry.sol

 _checkSignatures (replaces ECDSA version)

 _checkSignatures(digest, signerPubkeys[], aggregateSignature, referenceBlock):
   1. Validate inputs (lengths, sizes)
   2. For each signer pubkey:
      a. keyHash = keccak256(pubkey)
      b. Enforce sorted order by keyHash (ascending, prevents duplicates)
      c. Look up operator from _signingKeyOperatorHistory[keyHash] at referenceBlock
      d. Accumulate operator weight
      e. Aggregate pubkeys via G1ADD precompile
   3. Hash digest to G2 curve point via HashToCurve.hashToCurveG2
   4. Verify pairing: e(aggPubkey, H(m)) * e(-G1gen, aggSig) == 1
   5. Validate threshold + quorum (same as ECDSA)

 updateOperatorSigningKey

 Key ownership proof: operator signs keccak256(abi.encode(operator)) with their BLS private key. Contract verifies via verifyAggregateSignature(blsKey, H(msg), blsSigProof).

 isValidSignature (ERC1271)

 Same isValidSignature(bytes32, bytes) interface. Internal decoding changes to (bytes[], bytes, uint32) instead of (address[], bytes[], uint32).

 validate (WAVS)

 Same pattern but uses keccak256(abi.encode(envelope)) as digest (no toEthSignedMessageHash prefix since that's ECDSA-specific).

 Functions Identical to ECDSA (~80% of contract)

 initialize, registerOperator, deregisterOperator, updateOperatorWeight, updateStakeThreshold, updateQuorum, _updateTotalWeight, _getOperatorWeight, _getTotalWeight, _getThresholdStake, _getQuorum, _validateThresholdStake, setServiceURI, getServiceURI, EigenLayer stubs.

 7. Testing Strategy

 Files: contracts/test/bls/

 Generating BLS Signatures in Forge

 Forge lacks vm.sign for BLS. Use EIP-2537 precompiles directly:
 _generateBLSKeypair(uint256 sk) -> bytes pubkey:
   pubkey = G1MSM(G1_generator, sk)          // precompile 0x0c

 _blsSign(uint256 sk, bytes messageG2) -> bytes sig:
   sig = G2MSM(messageG2, sk)                // precompile 0x0e

 _aggregateSignatures(bytes sig1, bytes sig2) -> bytes:
   return G2ADD(sig1, sig2)                   // precompile 0x0d

 Test Coverage (mirrors ECDSA test suite)

 - Initialization, operator registration/deregistration, weight updates
 - BLS signing key updates with ownership proof
 - Threshold and quorum management
 - Valid aggregate BLS signatures (1 signer, 2+ signers)
 - Invalid signatures, unsorted signers, insufficient quorum/threshold
 - WAVS envelope validation
 - Historical data consistency (key/weight lookups at past blocks)
 - BLS library unit tests (g1Add, g2Add, pairingCheck, mapFp2ToG2)
 - Hash-to-curve unit tests (expandMsgXmd, hashToFieldFp2, hashToCurveG2)

 8. Implementation Sequence

 Phase 1: Foundation + Config

 1. Update foundry.toml — add evm_version = "prague" and remappings to BLS profile
 2. libs/BLS12381.sol — precompile wrappers and constants
 3. libs/HashToCurve.sol — hash-to-G2 implementation
 4. test/bls/BLS12381.t.sol + test/bls/HashToCurve.t.sol — verify precompiles work

 Phase 2: Interfaces + Storage

 5. interfaces/IWavsServiceHandler.sol — BLS SignatureData
 6. interfaces/IWavsServiceManager.sol
 7. interfaces/IPOAStakeRegistry.sol
 8. POAStakeRegistryStorage.sol — BLS key storage

 Phase 3: Main Contract + Tests

 9. POAStakeRegistry.sol — main contract
 10. test/bls/POAStakeRegistry.t.sol — integration tests

 Phase 4: Deployment

 11. script/bls/utils/ — copy UpgradeableProxyLib + EmptyContract from ecdsa
 12. script/bls/POAMiddlewareDeployer.s.sol
 13. scripts/bls/ — shell scripts

 9. Verification

 # Build BLS contracts
 just profile=bls build

 # Run BLS tests
 just profile=bls test

 # Run specific test
 FOUNDRY_PROFILE=bls forge test --match-test testFunctionName -vv

 # Run all profiles
 just build-all && just test-all

 10. Key Risks

 1. Precompile addresses: EIP-2537 addresses must match the target chain. Tests catch mismatches immediately.
 2. Cofactor clearing: If MAP_FP2_TO_G2 doesn't include cofactor clearing, we'll need to add explicit clearing via scalar decomposition (chain G2MSM calls with <=32-byte chunks of h_eff).
 3. Hash-to-curve correctness: Must match RFC 9380 test vectors exactly for interop with standard BLS libraries.
 4. EVM version: Solidity 0.8.27 predates Prague, but precompile calls use raw staticcall assembly, so Foundry's evm_version setting is what matters.

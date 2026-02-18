// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IWavsServiceHandler} from "./interfaces/IWavsServiceHandler.sol";
import {IWavsServiceManager} from "./interfaces/IWavsServiceManager.sol";
import {BLS12381} from "./libs/BLS12381.sol";
import {HashToCurve} from "./libs/HashToCurve.sol";

import {IPOAStakeRegistry, POAStakeRegistryStorage} from "./POAStakeRegistryStorage.sol";

/// @title POA Stake Registry (BLS)
/// @author Lay3r Labs
/// @notice Manages operator registration and quorum updates for an AVS using BLS12-381
///         aggregate signatures verified via EIP-2537 precompiles.
contract POAStakeRegistry is IERC1271, OwnableUpgradeable, POAStakeRegistryStorage {
    using Checkpoints for Checkpoints.Trace160;

    /// @notice Constructor to disable initializers
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with the given parameters.
     * @param initialOwner The initial owner of the contract.
     * @param thresholdWeight The threshold weight in basis points.
     * @param quorumNumerator The new quorum numerator.
     * @param quorumDenominator The new quorum denominator.
     */
    function initialize(
        address initialOwner,
        uint256 thresholdWeight,
        uint256 quorumNumerator,
        uint256 quorumDenominator
    ) external initializer {
        if (initialOwner == address(0)) {
            revert InvalidAddressZero();
        }
        _updateStakeThreshold(thresholdWeight);
        _updateQuorum(quorumNumerator, quorumDenominator);
        __Ownable_init(initialOwner);
    }

    /// @inheritdoc IPOAStakeRegistry
    function registerOperator(
        address operator,
        uint256 weight
    ) external onlyOwner {
        _registerOperator(operator, weight);
    }

    /// @inheritdoc IPOAStakeRegistry
    function deregisterOperator(
        address operator
    ) external onlyOwner {
        _deregisterOperator(operator);
    }

    /// @inheritdoc IPOAStakeRegistry
    function updateOperatorSigningKey(
        bytes calldata blsKey,
        bytes calldata blsSigProof
    ) external {
        if (!_operatorRegistered[msg.sender]) {
            revert OperatorNotRegistered();
        }
        _updateOperatorSigningKey(msg.sender, blsKey, blsSigProof);
    }

    /// @inheritdoc IPOAStakeRegistry
    function updateOperatorWeight(
        address operator,
        uint256 weight
    ) external onlyOwner {
        int256 delta = _updateOperatorWeight(operator, weight);
        _updateTotalWeight(delta);
    }

    /// @inheritdoc IPOAStakeRegistry
    function updateStakeThreshold(
        uint256 thresholdWeight
    ) external onlyOwner {
        _updateStakeThreshold(thresholdWeight);
    }

    /// @inheritdoc IPOAStakeRegistry
    function updateQuorum(
        uint256 quorumNumerator,
        uint256 quorumDenominator
    ) external onlyOwner {
        _updateQuorum(quorumNumerator, quorumDenominator);
    }

    /**
     * @notice Validates a BLS aggregate signature against the digest.
     * @param digest The hash of the data that is signed.
     * @param _signatureData ABI-encoded (bytes[] signerPubkeys, bytes aggSig, uint32 refBlock).
     * @return The selector for the `isValidSignature` function.
     */
    function isValidSignature( // solhint-disable-line gas-calldata-parameters
        bytes32 digest,
        bytes memory _signatureData
    ) external view returns (bytes4) {
        (bytes[] memory signerPubkeys, bytes memory aggregateSignature, uint32 referenceBlock) =
            abi.decode(_signatureData, (bytes[], bytes, uint32));
        _checkSignatures(digest, signerPubkeys, aggregateSignature, referenceBlock);
        return IERC1271.isValidSignature.selector;
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLatestOperatorSigningKey(
        address operator
    ) external view returns (bytes memory) {
        BLSKeyCheckpoint[] storage history = _operatorBLSKeyHistory[operator];
        if (history.length == 0) {
            return "";
        }
        bytes32 keyHash = history[history.length - 1].keyHash;
        return _blsKeyStore[keyHash];
    }

    /// @inheritdoc IPOAStakeRegistry
    function getOperatorSigningKeyAtBlock(
        address operator,
        uint256 blockNumber
    ) external view returns (bytes memory) {
        bytes32 keyHash = _getOperatorKeyHashAtBlock(operator, uint96(blockNumber));
        if (keyHash == bytes32(0)) {
            return "";
        }
        return _blsKeyStore[keyHash];
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLastCheckpointTotalWeight() external view returns (uint256) {
        return _totalWeightHistory.latest();
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLastCheckpointThresholdWeight() external view returns (uint256) {
        return _thresholdWeightHistory.latest();
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLastCheckpointQuorum() external view returns (uint256, uint256) {
        return (_quorumNumeratorHistory.latest(), _quorumDenominatorHistory.latest());
    }

    /// @inheritdoc IPOAStakeRegistry
    function getOperatorWeightAtBlock(
        address operator,
        uint32 blockNumber
    ) external view returns (uint256) {
        return _operatorWeightHistory[operator].upperLookup(uint96(blockNumber));
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLastCheckpointTotalWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256) {
        return _totalWeightHistory.upperLookup(uint96(blockNumber));
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLastCheckpointThresholdWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256) {
        return _thresholdWeightHistory.upperLookup(uint96(blockNumber));
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLastCheckpointQuorumAtBlock(
        uint32 blockNumber
    ) external view returns (uint256, uint256) {
        return (
            _quorumNumeratorHistory.upperLookup(uint96(blockNumber)),
            _quorumDenominatorHistory.upperLookup(uint96(blockNumber))
        );
    }

    /// @inheritdoc IPOAStakeRegistry
    function operatorRegistered(
        address operator
    ) external view returns (bool) {
        return _operatorRegistered[operator];
    }

    /// @inheritdoc IWavsServiceManager
    function getOperatorWeight(
        address operator
    ) external view returns (uint256) {
        return _operatorWeightHistory[operator].latest();
    }

    /// @inheritdoc IWavsServiceManager
    function setServiceURI(
        string calldata __serviceuri
    ) external onlyOwner {
        _serviceuri = __serviceuri;
        emit ServiceURIUpdated(_serviceuri);
    }

    /// @inheritdoc IWavsServiceManager
    function getServiceURI() external view returns (string memory) {
        return _serviceuri;
    }

    /// @inheritdoc IWavsServiceManager
    function getAllocationManager() external pure returns (address) {
        return address(0);
    }

    /// @inheritdoc IWavsServiceManager
    function getDelegationManager() external pure returns (address) {
        return address(0);
    }

    /// @inheritdoc IWavsServiceManager
    function getStakeRegistry() external pure returns (address) {
        return address(0);
    }

    /// @inheritdoc IWavsServiceManager
    function getLatestOperatorForSigningKey(
        bytes32 keyHash
    ) external view returns (address) {
        return address(_signingKeyOperatorHistory[keyHash].latest());
    }

    /// @inheritdoc IWavsServiceManager
    function validate(
        IWavsServiceHandler.Envelope calldata envelope,
        IWavsServiceHandler.SignatureData calldata signatureData
    ) external view {
        bytes32 digest = keccak256(abi.encode(envelope));
        _checkSignatures(
            digest,
            signatureData.signerPubkeys,
            signatureData.aggregateSignature,
            signatureData.referenceBlock
        );
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal: Threshold / Quorum / Weight management (identical to ECDSA)
    // ──────────────────────────────────────────────────────────────────────────

    function _updateStakeThreshold(
        uint256 thresholdWeight
    ) internal {
        if (thresholdWeight > type(uint160).max || thresholdWeight == 0) {
            revert InvalidThresholdWeight();
        }
        _thresholdWeightHistory.push(uint96(block.number), uint160(thresholdWeight));
        emit ThresholdWeightUpdated(thresholdWeight);
    }

    function _updateQuorum(
        uint256 quorumNumerator,
        uint256 quorumDenominator
    ) internal {
        if (
            quorumNumerator > type(uint160).max || quorumDenominator > type(uint160).max
                || quorumDenominator == 0 || quorumNumerator > quorumDenominator
        ) {
            revert InvalidQuorum();
        }
        _quorumNumeratorHistory.push(uint96(block.number), uint160(quorumNumerator));
        _quorumDenominatorHistory.push(uint96(block.number), uint160(quorumDenominator));
        emit QuorumThresholdUpdated(quorumNumerator, quorumDenominator);
    }

    function _deregisterOperator(
        address operator
    ) internal {
        if (operator == address(0)) {
            revert InvalidAddressZero();
        }
        if (!_operatorRegistered[operator]) {
            revert OperatorNotRegistered();
        }
        --_totalOperators;
        delete _operatorRegistered[operator];
        int256 delta = _updateOperatorWeight(operator, 0);
        _updateTotalWeight(delta);
        emit OperatorDeregistered(operator);
    }

    function _registerOperator(
        address operator,
        uint256 weight
    ) internal {
        if (weight == 0 || weight > type(uint160).max) {
            revert InvalidWeight();
        }
        if (operator == address(0)) {
            revert InvalidAddressZero();
        }
        if (_operatorRegistered[operator]) {
            revert OperatorAlreadyRegistered();
        }
        ++_totalOperators;
        _operatorRegistered[operator] = true;
        int256 delta = _updateOperatorWeight(operator, weight);
        _updateTotalWeight(delta);
        emit OperatorRegistered(operator);
    }

    function _updateOperatorWeight(
        address operator,
        uint256 weight
    ) internal returns (int256) {
        if (weight > type(uint160).max) {
            revert InvalidWeight();
        }
        if (operator == address(0)) {
            revert InvalidAddressZero();
        }
        int256 delta = 0;
        uint256 newWeight = 0;
        uint256 oldWeight = _operatorWeightHistory[operator].latest();
        if (!_operatorRegistered[operator]) {
            delta -= int256(oldWeight);
            if (delta == 0) {
                return delta;
            }
            _operatorWeightHistory[operator].push(uint96(block.number), 0);
        } else {
            newWeight = weight;
            delta = int256(newWeight) - int256(oldWeight);
            if (delta == 0) {
                return delta;
            }
            _operatorWeightHistory[operator].push(uint96(block.number), uint160(newWeight));
        }
        emit OperatorWeightUpdated(operator, oldWeight, newWeight);
        return delta;
    }

    function _updateTotalWeight(
        int256 delta
    ) internal returns (uint256 oldTotalWeight, uint256 newTotalWeight) {
        oldTotalWeight = _totalWeightHistory.latest();
        int256 newWeight = int256(oldTotalWeight) + delta;
        newTotalWeight = uint256(newWeight);
        if (newTotalWeight == oldTotalWeight) {
            return (oldTotalWeight, newTotalWeight);
        }
        _totalWeightHistory.push(uint96(block.number), uint160(newTotalWeight));
        emit TotalWeightUpdated(oldTotalWeight, newTotalWeight);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal: BLS signing key management
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Update an operator's BLS signing key with ownership proof.
     * @param operator The operator address.
     * @param blsKey The new BLS G1 public key (128 bytes).
     * @param blsSigProof BLS signature of keccak256(abi.encode(operator)) proving key ownership.
     */
    function _updateOperatorSigningKey(
        address operator,
        bytes calldata blsKey,
        bytes calldata blsSigProof
    ) internal {
        if (blsKey.length != BLS12381.G1_POINT_SIZE) {
            revert InvalidBLSKeyLength();
        }
        if (blsSigProof.length != BLS12381.G2_POINT_SIZE) {
            revert InvalidBLSSignatureLength();
        }

        // Verify key ownership: operator signs keccak256(abi.encode(operator)) with BLS key
        bytes32 messageHash = keccak256(abi.encode(operator));
        bytes memory messageG2 = HashToCurve.hashToCurveG2(abi.encodePacked(messageHash));
        bool ownershipValid = BLS12381.verifyAggregateSignature(blsKey, messageG2, blsSigProof);
        if (!ownershipValid) {
            revert InvalidBLSKeyOwnershipProof();
        }

        bytes32 newKeyHash = keccak256(blsKey);

        // Check if key is already assigned to a different operator
        address currentOwner = address(_signingKeyOperatorHistory[newKeyHash].latest());
        if (currentOwner != address(0) && currentOwner != operator) {
            revert SigningKeyAlreadyAssigned();
        }

        // Get old key hash
        bytes32 oldKeyHash = bytes32(0);
        BLSKeyCheckpoint[] storage history = _operatorBLSKeyHistory[operator];
        if (history.length > 0) {
            oldKeyHash = history[history.length - 1].keyHash;
        }

        // No-op if same key
        if (newKeyHash == oldKeyHash) {
            return;
        }

        // Store the full BLS key
        _blsKeyStore[newKeyHash] = blsKey;

        // Update forward mapping (operator -> key history)
        history.push(BLSKeyCheckpoint({blockNumber: uint96(block.number), keyHash: newKeyHash}));

        // Update reverse mapping (key -> operator)
        _signingKeyOperatorHistory[newKeyHash].push(uint96(block.number), uint160(operator));

        // Clear old reverse mapping
        if (oldKeyHash != bytes32(0)) {
            _signingKeyOperatorHistory[oldKeyHash].push(uint96(block.number), uint160(0));
        }

        emit SigningKeyUpdate(operator, block.number, newKeyHash, oldKeyHash);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal: BLS signature verification
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Verify a BLS aggregate signature from multiple signers.
     * @param digest The hash of the data the signers endorsed.
     * @param signerPubkeys Array of 128-byte G1 public keys.
     * @param aggregateSignature The aggregate G2 signature (256 bytes).
     * @param referenceBlock The block number for evaluating stake weight.
     */
    function _checkSignatures(
        bytes32 digest,
        bytes[] memory signerPubkeys,
        bytes memory aggregateSignature,
        uint32 referenceBlock
    ) internal view {
        uint256 signersLength = signerPubkeys.length;
        if (signersLength == 0) {
            revert InvalidLength();
        }
        if (aggregateSignature.length != BLS12381.G2_POINT_SIZE) {
            revert InvalidBLSSignatureLength();
        }

        bytes32 lastKeyHash = bytes32(0);
        uint256 signedWeight = 0;

        // Aggregate pubkeys and accumulate weights
        bytes memory aggregatedPubkey;
        for (uint256 i; i < signersLength; ++i) {
            bytes memory pubkey = signerPubkeys[i];
            if (pubkey.length != BLS12381.G1_POINT_SIZE) {
                revert InvalidBLSKeyLength();
            }

            bytes32 keyHash = keccak256(pubkey);

            // Enforce sorted ascending order by keyHash to prevent duplicates
            if (!(lastKeyHash < keyHash)) {
                revert NotSorted();
            }
            lastKeyHash = keyHash;

            // Look up operator for this signing key at the reference block
            address operator = _getOperatorForSigningKey(keyHash, referenceBlock);
            signedWeight += _getOperatorWeight(operator, referenceBlock);

            // Aggregate pubkeys via G1ADD
            if (i == 0) {
                aggregatedPubkey = pubkey;
            } else {
                aggregatedPubkey = BLS12381.g1Add(aggregatedPubkey, pubkey);
            }
        }

        // Hash the digest to a G2 curve point
        bytes memory messageG2 = HashToCurve.hashToCurveG2(abi.encodePacked(digest));

        // Verify the aggregate signature
        bool valid =
            BLS12381.verifyAggregateSignature(aggregatedPubkey, messageG2, aggregateSignature);
        if (!valid) {
            revert InvalidBLSSignature();
        }

        // Validate threshold + quorum
        _validateThresholdStake(signedWeight, referenceBlock);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal: Lookups (shared with ECDSA pattern)
    // ──────────────────────────────────────────────────────────────────────────

    function _getOperatorForSigningKey(
        bytes32 keyHash,
        uint32 referenceBlock
    ) internal view returns (address) {
        if (referenceBlock == type(uint32).max) {
            return address(_signingKeyOperatorHistory[keyHash].latest());
        }
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        address operator =
            address(_signingKeyOperatorHistory[keyHash].upperLookup(uint96(referenceBlock)));
        if (operator == address(0)) {
            revert SignerNotRegistered();
        }
        return operator;
    }

    function _getOperatorWeight(
        address operator,
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (referenceBlock == type(uint32).max) {
            return _operatorWeightHistory[operator].latest();
        }
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return _operatorWeightHistory[operator].upperLookup(uint96(referenceBlock));
    }

    function _getTotalWeight(
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (referenceBlock == type(uint32).max) {
            return _totalWeightHistory.latest();
        }
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return _totalWeightHistory.upperLookup(uint96(referenceBlock));
    }

    function _getThresholdStake(
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (referenceBlock == type(uint32).max) {
            return _thresholdWeightHistory.latest();
        }
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return _thresholdWeightHistory.upperLookup(uint96(referenceBlock));
    }

    function _getQuorum(
        uint32 referenceBlock
    ) internal view returns (uint256, uint256) {
        if (referenceBlock == type(uint32).max) {
            return (_quorumNumeratorHistory.latest(), _quorumDenominatorHistory.latest());
        }
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return (
            _quorumNumeratorHistory.upperLookup(uint96(referenceBlock)),
            _quorumDenominatorHistory.upperLookup(uint96(referenceBlock))
        );
    }

    function _validateThresholdStake(
        uint256 signedWeight,
        uint32 referenceBlock
    ) internal view {
        uint256 totalWeight = _getTotalWeight(referenceBlock);
        if (signedWeight > totalWeight) {
            revert InvalidSignedWeight();
        }
        uint256 thresholdStake = _getThresholdStake(referenceBlock);
        if (thresholdStake > signedWeight) {
            revert InsufficientSignedStake();
        }
        (uint256 quorumNumerator, uint256 quorumDenominator) = _getQuorum(referenceBlock);
        if (signedWeight * quorumDenominator < quorumNumerator * totalWeight) {
            revert InsufficientQuorum(signedWeight, quorumNumerator, totalWeight);
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal: BLS key history binary search
    // ──────────────────────────────────────────────────────────────────────────

    /// @dev Binary search on BLSKeyCheckpoint[] for the keyHash at a given block.
    ///      Implements upperLookup semantics (finds latest checkpoint <= blockNumber).
    function _getOperatorKeyHashAtBlock(
        address operator,
        uint96 blockNumber
    ) internal view returns (bytes32) {
        BLSKeyCheckpoint[] storage history = _operatorBLSKeyHistory[operator];
        uint256 len = history.length;
        if (len == 0) {
            return bytes32(0);
        }

        // If the target block is before the first checkpoint, return zero
        if (blockNumber < history[0].blockNumber) {
            return bytes32(0);
        }

        // If the target block is at or after the latest checkpoint, return latest
        if (blockNumber >= history[len - 1].blockNumber) {
            return history[len - 1].keyHash;
        }

        // Binary search for the right checkpoint
        uint256 low = 0;
        uint256 high = len - 1;
        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (history[mid].blockNumber <= blockNumber) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return history[low].keyHash;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Checkpoints} from
    "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SignatureChecker} from
    "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC1271} from
    "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IWavsServiceHandler} from "@wavs/src/eigenlayer/ecdsa/interfaces/IWavsServiceHandler.sol";
import {IWavsServiceManager} from "@wavs/src/eigenlayer/ecdsa/interfaces/IWavsServiceManager.sol";
import {IPOAStakeRegistry, POAStakeRegistryStorage} from "./POAStakeRegistryStorage.sol";

/// @title POA Stake Registry
/// @dev THIS CONTRACT IS NOT AUDITED
/// @author Lay3r Labs
/// @notice Manages operator registration and quorum updates for an AVS using ECDSA signatures.
contract POAStakeRegistry is IERC1271, OwnableUpgradeable, POAStakeRegistryStorage {
    using SignatureChecker for address;
    using Checkpoints for Checkpoints.Trace160;

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
        _updateStakeThreshold(thresholdWeight);
        _updateQuorum(quorumNumerator, quorumDenominator);
        __Ownable_init(initialOwner);
    }

    /// @inheritdoc IPOAStakeRegistry
    function registerOperator(address operator, uint256 weight) external onlyOwner {
        if (weight == 0) {
            revert InvalidWeight();
        }
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
        address newSigningKey
    ) external {
        if (!_operatorRegistered[msg.sender]) {
            revert OperatorNotRegistered();
        }
        _updateOperatorSigningKey(msg.sender, newSigningKey);
    }

    /// @inheritdoc IPOAStakeRegistry
    function updateOperatorWeight(address operator, uint256 weight) external onlyOwner {
        if (weight == 0) {
            revert InvalidWeight();
        }
        _updateOperatorWeight(operator, weight);
    }

    /// @inheritdoc IPOAStakeRegistry
    function updateStakeThreshold(
        uint256 thresholdWeight
    ) external onlyOwner {
        _updateStakeThreshold(thresholdWeight);
    }

    /// @inheritdoc IPOAStakeRegistry
    function updateQuorum(uint256 quorumNumerator, uint256 quorumDenominator) external onlyOwner {
        _updateQuorum(quorumNumerator, quorumDenominator);
    }

    /**
     * @notice Validates a signature against the signer's address and data hash.
     * @param digest The hash of the data that is signed.
     * @param _signatureData The signature to validate.
     * @return The selector for the `isValidSignature` function.
     */
    function isValidSignature( // solhint-disable-line gas-calldata-parameters
        bytes32 digest,
        bytes memory _signatureData
    ) external view returns (bytes4) {
        (address[] memory signers, bytes[] memory signatures, uint32 referenceBlock) =
            abi.decode(_signatureData, (address[], bytes[], uint32));
        _checkSignatures(digest, signers, signatures, referenceBlock);
        return IERC1271.isValidSignature.selector;
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLatestOperatorSigningKey(
        address operator
    ) external view returns (address) {
        return address(uint160(_operatorSigningKeyHistory[operator].latest()));
    }

    /// @inheritdoc IPOAStakeRegistry
    function getOperatorSigningKeyAtBlock(
        address operator,
        uint256 blockNumber
    ) external view returns (address) {
        return address(uint160(_operatorSigningKeyHistory[operator].upperLookup(uint96(blockNumber))));
    }

    /// @inheritdoc IPOAStakeRegistry
    function getLastCheckpointOperatorWeight(
        address operator
    ) external view returns (uint256) {
        return _operatorWeightHistory[operator].latest();
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

    /**
     * @notice Updates the stake threshold weight and records the history.
     * @param thresholdWeight The new threshold weight to set and record in the history.
     */
    function _updateStakeThreshold(
        uint256 thresholdWeight
    ) internal {
        _thresholdWeightHistory.push(uint96(block.number), uint160(thresholdWeight));
        emit ThresholdWeightUpdated(thresholdWeight);
    }

    /**
     * @notice Updates the quorum numerator and records the history.
     * @param quorumNumerator The new quorum numerator to set and record in the history.
     * @param quorumDenominator The new quorum denominator to set and record in the history.
     */
    function _updateQuorum(uint256 quorumNumerator, uint256 quorumDenominator) internal {
        if (quorumDenominator == 0) {
            revert InvalidQuorum();
        }
        if (quorumNumerator > quorumDenominator) {
            revert InvalidQuorum();
        }
        _quorumNumeratorHistory.push(uint96(block.number), uint160(quorumNumerator));
        _quorumDenominatorHistory.push(uint96(block.number), uint160(quorumDenominator));
        emit QuorumThresholdUpdated(quorumNumerator, quorumDenominator);
    }

    /**
     * @notice Internal function to deregister an operator
     * @param operator The operator's address to deregister
     */
    function _deregisterOperator(
        address operator
    ) internal {
        if (!_operatorRegistered[operator]) {
            revert OperatorNotRegistered();
        }
        --_totalOperators;
        delete _operatorRegistered[operator];
        int256 delta = _updateOperatorWeight(operator, 0);
        _updateTotalWeight(delta);
        emit OperatorDeregistered(operator);
    }

    /**
     * @notice Registers an operator through a provided weight
     * @param operator The address of the operator to register
     * @param weight The weight of the operator
     */
    function _registerOperator(address operator, uint256 weight) internal {
        if (_operatorRegistered[operator]) {
            revert OperatorAlreadyRegistered();
        }
        ++_totalOperators;
        _operatorRegistered[operator] = true;
        int256 delta = _updateOperatorWeight(operator, weight);
        _updateTotalWeight(delta);
        emit OperatorRegistered(operator);
    }

    /**
     * @notice Internal function to update an operator's signing key
     * @param operator The address of the operator to update the signing key for
     * @param newSigningKey The new signing key to set for the operator
     */
    function _updateOperatorSigningKey(address operator, address newSigningKey) internal {
        address oldSigningKey = address(uint160(_operatorSigningKeyHistory[operator].latest()));
        if (newSigningKey == oldSigningKey) {
            return;
        }
        _operatorSigningKeyHistory[operator].push(uint96(block.number), uint160(newSigningKey));
        _signingKeyOperatorHistory[newSigningKey].push(uint96(block.number), uint160(operator));
        if (oldSigningKey != address(0)) {
            _signingKeyOperatorHistory[oldSigningKey].push(uint96(block.number), uint160(0));
        }
        emit SigningKeyUpdate(operator, block.number, newSigningKey, oldSigningKey);
    }

    /**
     * @notice Updates the weight of an operator and returns the previous and current weights.
     * @param operator The address of the operator to update the weight of.
     * @param weight The weight to set for the operator.
     * @return delta The change in weight for the operator.
     */
    function _updateOperatorWeight(address operator, uint256 weight) internal returns (int256) {
        int256 delta;
        uint256 newWeight;
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

    /**
     * @notice Internal function to update the total weight of the stake
     * @param delta The change in stake applied last total weight
     * @return oldTotalWeight The weight before the update
     * @return newTotalWeight The updated weight after applying the delta
     */
    function _updateTotalWeight(
        int256 delta
    ) internal returns (uint256 oldTotalWeight, uint256 newTotalWeight) {
        oldTotalWeight = _totalWeightHistory.latest();
        int256 newWeight = int256(oldTotalWeight) + delta;
        newTotalWeight = uint256(newWeight);
        _totalWeightHistory.push(uint96(block.number), uint160(newTotalWeight));
        emit TotalWeightUpdated(oldTotalWeight, newTotalWeight);
    }

    /**
     * @notice Common logic to verify a batch of ECDSA signatures against a hash, using either last stake weight or at a specific block.
     * @param digest The hash of the data the signers endorsed.
     * @param signers A collection of signing key addresses that endorsed the data hash.
     * @param signatures A collection of signatures matching the signers.
     * @param referenceBlock The block number for evaluating stake weight; use max uint32 for latest weight.
     */
    function _checkSignatures(
        bytes32 digest,
        address[] memory signers,
        bytes[] memory signatures,
        uint32 referenceBlock
    ) internal view {
        uint256 signersLength = signers.length;
        address currentSigner;
        address lastSigner;
        address operator;
        uint256 signedWeight;

        _validateSignaturesLength(signersLength, signatures.length);
        for (uint256 i; i < signersLength; ++i) {
            currentSigner = signers[i];
            operator = _getOperatorForSigningKey(currentSigner, referenceBlock);

            _validateSortedSigners(lastSigner, currentSigner);
            _validateSignature(currentSigner, digest, signatures[i]);

            lastSigner = currentSigner;
            uint256 operatorWeight = _getOperatorWeight(operator, referenceBlock);
            signedWeight += operatorWeight;
        }

        _validateThresholdStake(signedWeight, referenceBlock);
    }

    /**
     * @notice Validates that the number of signers equals the number of signatures, and neither is zero.
     * @param signersLength The number of signers.
     * @param signaturesLength The number of signatures.
     */
    function _validateSignaturesLength(
        uint256 signersLength,
        uint256 signaturesLength
    ) internal pure {
        if (signersLength != signaturesLength) {
            revert LengthMismatch();
        }
        if (signersLength == 0) {
            revert InvalidLength();
        }
    }

    /**
     * @notice Ensures that signers are sorted in ascending order by address.
     * @param lastSigner The address of the last signer.
     * @param currentSigner The address of the current signer.
     */
    function _validateSortedSigners(address lastSigner, address currentSigner) internal pure {
        if (!(lastSigner < currentSigner)) {
            revert NotSorted();
        }
    }

    /**
     * @notice Validates a given signature against the signer's address and data hash.
     * @param signer The address of the signer to validate.
     * @param digest The hash of the data that is signed.
     * @param signature The signature to validate.
     */
    function _validateSignature(
        address signer,
        bytes32 digest,
        bytes memory signature
    ) internal view {
        if (!signer.isValidSignatureNow(digest, signature)) {
            revert InvalidSignature();
        }
    }

    /**
     * @notice Retrieves the operator weight for a signer, either at the last checkpoint or a specified block.
     * @param operator The operator to query their signing key history for
     * @param referenceBlock The block number to query the operator's weight at, or the maximum uint32 value for the last checkpoint.
     * @return The weight of the operator.
     */
    function _getOperatorSigningKey(
        address operator,
        uint32 referenceBlock
    ) internal view returns (address) {
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return address(uint160(_operatorSigningKeyHistory[operator].upperLookup(uint96(referenceBlock))));
    }

    /**
     * @notice Retrieves the operator address for a given signing key at a specific block.
     * @param signingKey The signing key to look up the operator for.
     * @param referenceBlock The block number to query the operator at.
     * @return The operator address associated with the signing key.
     */
    function _getOperatorForSigningKey(
        address signingKey,
        uint32 referenceBlock
    ) internal view returns (address) {
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        address operator = address(uint160(_signingKeyOperatorHistory[signingKey].upperLookup(uint96(referenceBlock))));
        if (operator == address(0)) {
            revert SignerNotRegistered();
        }
        return operator;
    }

    /**
     * @notice Retrieves the operator weight for a signer, either at the last checkpoint or a specified block.
     * @param signer The address of the signer whose weight is returned.
     * @param referenceBlock The block number to query the operator's weight at, or the maximum uint32 value for the last checkpoint.
     * @return The weight of the operator.
     */
    function _getOperatorWeight(
        address signer,
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return _operatorWeightHistory[signer].upperLookup(uint96(referenceBlock));
    }

    /**
     * @notice Retrieve the total stake weight at a specific block or the latest if not specified.
     * @dev If the `referenceBlock` is the maximum value for uint32, the latest total weight is returned.
     * @param referenceBlock The block number to retrieve the total stake weight from.
     * @return The total stake weight at the given block or the latest if the given block is the max uint32 value.
     */
    function _getTotalWeight(
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return _totalWeightHistory.upperLookup(uint96(referenceBlock));
    }

    /**
     * @notice Retrieves the threshold stake for a given reference block.
     * @param referenceBlock The block number to query the threshold stake for.
     * If set to the maximum uint32 value, it retrieves the latest threshold stake.
     * @return The threshold stake in basis points for the reference block.
     */
    function _getThresholdStake(
        uint32 referenceBlock
    ) internal view returns (uint256) {
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return _thresholdWeightHistory.upperLookup(uint96(referenceBlock));
    }

    /**
     * @notice Retrieves the quorum for a given reference block.
     * @param referenceBlock The block number to query the quorum for.
     * If set to the maximum uint32 value, it retrieves the latest quorum.
     * @return The quorum numerator at the given block.
     * @return The quorum denominator at the given block.
     */
    function _getQuorum(
        uint32 referenceBlock
    ) internal view returns (uint256, uint256) {
        if (!(referenceBlock < block.number)) {
            revert InvalidReferenceBlock();
        }
        return (
            _quorumNumeratorHistory.upperLookup(uint96(referenceBlock)),
            _quorumDenominatorHistory.upperLookup(uint96(referenceBlock))
        );
    }

    /**
     * @notice Validates that the cumulative stake of signed messages meets or exceeds the required threshold.
     * @param signedWeight The cumulative weight of the signers that have signed the message.
     * @param referenceBlock The block number to verify the stake threshold for
     */
    function _validateThresholdStake(uint256 signedWeight, uint32 referenceBlock) internal view {
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

    /// @inheritdoc IWavsServiceManager
    function setServiceURI(
        string calldata __serviceURI
    ) external onlyOwner {
        _serviceURI = __serviceURI;
        emit ServiceURIUpdated(_serviceURI);
    }

    /// @inheritdoc IWavsServiceManager
    function getServiceURI() external view returns (string memory) {
        return _serviceURI;
    }

    // this is not used, but required for the IWAVSServiceManager to be Eigenlayer backwards compatible
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
        address signingKeyAddress
    ) external view returns (address) {
        return address(uint160(_signingKeyOperatorHistory[signingKeyAddress].latest()));
    }

    /// @inheritdoc IWavsServiceManager
    function validate(
        IWavsServiceHandler.Envelope calldata envelope,
        IWavsServiceHandler.SignatureData calldata signatureData
    ) external view {
        bytes32 messageHash = keccak256(abi.encode(envelope));
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(messageHash);
        _checkSignatures(digest, signatureData.signers, signatureData.signatures, signatureData.referenceBlock);
    }
}

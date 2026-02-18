// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title IPOAStakeRegistryErrors
 * @author Lay3r Labs
 * @notice Interface containing all error definitions for the BLS POAStakeRegistry contract.
 */
interface IPOAStakeRegistryErrors {
    /// @notice Thrown when the signers pubkeys array is empty.
    error InvalidLength();
    /// @notice Thrown when reference blocks must be for blocks that have already been confirmed.
    error InvalidReferenceBlock();
    /// @notice Thrown when operator weights were out of sync and the signed weight exceed the total.
    error InvalidSignedWeight();
    /// @notice Thrown when the total signed stake fails to meet the required threshold.
    error InsufficientSignedStake();
    /// @notice Thrown when the system finds a list of items unsorted.
    error NotSorted();
    /// @notice Thrown when registering an already registered operator.
    error OperatorAlreadyRegistered();
    /// @notice Thrown when de-registering or updating the stake for an unregistered operator.
    error OperatorNotRegistered();
    /// @notice Thrown when the quorum is invalid.
    error InvalidQuorum();
    /// @notice Thrown when the weight is invalid.
    error InvalidWeight();
    /// @notice Thrown when the signer is not registered.
    error SignerNotRegistered();
    /// @notice Thrown when the address is zero.
    error InvalidAddressZero();
    /// @notice Thrown when the signing key is already assigned to another operator.
    error SigningKeyAlreadyAssigned();
    /// @notice Thrown when the threshold weight is invalid.
    error InvalidThresholdWeight();
    /// @notice Thrown when the BLS public key has an invalid length (expected 128 bytes).
    error InvalidBLSKeyLength();
    /// @notice Thrown when the BLS signature has an invalid length (expected 256 bytes).
    error InvalidBLSSignatureLength();
    /// @notice Thrown when the BLS signature verification fails.
    error InvalidBLSSignature();
    /// @notice Thrown when the BLS key ownership proof is invalid.
    error InvalidBLSKeyOwnershipProof();
}

/**
 * @title IPOAStakeRegistryTypes
 * @author Lay3r Labs
 * @notice Interface containing all type definitions for the BLS POAStakeRegistry contract.
 */
interface IPOAStakeRegistryTypes {}

/**
 * @title IPOAStakeRegistryEvents
 * @author Lay3r Labs
 * @notice Interface containing all event definitions for the BLS POAStakeRegistry contract.
 */
interface IPOAStakeRegistryEvents is IPOAStakeRegistryTypes {
    /**
     * @notice Emitted when the system registers an operator.
     * @param operator The address of the registered operator.
     */
    event OperatorRegistered(address indexed operator);

    /**
     * @notice Emitted when the system deregisters an operator.
     * @param operator The address of the deregistered operator.
     */
    event OperatorDeregistered(address indexed operator);

    /**
     * @notice Emitted when the system updates an operator's weight.
     * @param operator The address of the operator updated.
     * @param oldWeight The operator's weight before the update.
     * @param newWeight The operator's weight after the update.
     */
    event OperatorWeightUpdated(
        address indexed operator,
        uint256 oldWeight,
        uint256 newWeight
    );

    /**
     * @notice Emitted when the system updates the total weight.
     * @param oldTotalWeight The total weight before the update.
     * @param newTotalWeight The total weight after the update.
     */
    event TotalWeightUpdated(uint256 oldTotalWeight, uint256 newTotalWeight);

    /**
     * @notice Emits when setting a new threshold weight.
     * @param thresholdWeight The new threshold weight.
     */
    event ThresholdWeightUpdated(uint256 thresholdWeight);

    /**
     * @notice Emitted when an operator's BLS signing key is updated.
     * @param operator The address of the operator whose signing key was updated.
     * @param updateBlock The block number at which the signing key was updated.
     * @param newKeyHash The keccak256 hash of the new BLS public key.
     * @param oldKeyHash The keccak256 hash of the old BLS public key.
     */
    event SigningKeyUpdate(
        address indexed operator,
        uint256 indexed updateBlock,
        bytes32 indexed newKeyHash,
        bytes32 oldKeyHash
    );
}

/**
 * @title IPOAStakeRegistry
 * @author Lay3r Labs
 * @notice Interface containing all functions for the BLS POAStakeRegistry contract.
 */
interface IPOAStakeRegistry is
    IPOAStakeRegistryErrors,
    IPOAStakeRegistryEvents,
    IERC1271
{
    /* ACTIONS */

    /**
     * @notice Registers a new operator using a provided operator address and weight.
     * @param operator The address of the operator to register.
     * @param weight The weight of the operator.
     */
    function registerOperator(address operator, uint256 weight) external;

    /**
     * @notice Deregisters an existing operator.
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperator(address operator) external;

    /**
     * @notice Updates the BLS signing key for an operator.
     * @param blsKey The new BLS G1 public key (128 bytes).
     * @param blsSigProof BLS signature proving key ownership (256 bytes).
     *        The operator signs keccak256(abi.encode(operator)) with their BLS private key.
     * @dev Only callable by the operator themselves.
     */
    function updateOperatorSigningKey(
        bytes calldata blsKey,
        bytes calldata blsSigProof
    ) external;

    /**
     * @notice Updates the weight for an operator.
     * @param operator The address of the operator to update the weight for.
     * @param weight The new weight to set for the operator.
     * @dev Only callable by owner.
     */
    function updateOperatorWeight(address operator, uint256 weight) external;

    /**
     * @notice Sets a new cumulative threshold weight for message validation.
     * @param thresholdWeight The updated threshold weight required to validate a message.
     */
    function updateStakeThreshold(uint256 thresholdWeight) external;

    /**
     * @notice Updates the quorum configuration.
     * @param quorumNumerator The new quorum numerator.
     * @param quorumDenominator The new quorum denominator.
     */
    function updateQuorum(
        uint256 quorumNumerator,
        uint256 quorumDenominator
    ) external;

    /* VIEW */

    /**
     * @notice Retrieves the latest BLS signing key for a given operator.
     * @param operator The address of the operator.
     * @return The latest BLS public key of the operator (128 bytes).
     */
    function getLatestOperatorSigningKey(
        address operator
    ) external view returns (bytes memory);

    /**
     * @notice Retrieves the BLS signing key for an operator at a specific block.
     * @param operator The address of the operator.
     * @param blockNumber The block number to query at.
     * @return The BLS public key of the operator at the given block (128 bytes).
     */
    function getOperatorSigningKeyAtBlock(
        address operator,
        uint256 blockNumber
    ) external view returns (bytes memory);

    /**
     * @notice Retrieves the last recorded total weight across all operators.
     * @return The latest total weight.
     */
    function getLastCheckpointTotalWeight() external view returns (uint256);

    /**
     * @notice Retrieves the last recorded threshold weight.
     * @return The latest threshold weight.
     */
    function getLastCheckpointThresholdWeight()
        external
        view
        returns (uint256);

    /**
     * @notice Retrieves the last recorded quorum.
     * @return The latest quorum numerator.
     * @return The latest quorum denominator.
     */
    function getLastCheckpointQuorum()
        external
        view
        returns (uint256, uint256);

    /**
     * @notice Returns whether an operator is currently registered.
     * @param operator The operator address to check.
     * @return Whether the operator is registered.
     */
    function operatorRegistered(
        address operator
    ) external view returns (bool);

    /**
     * @notice Retrieves the operator's weight at a specific block number.
     * @param operator The address of the operator.
     * @param blockNumber The block number to query at.
     * @return The weight of the operator at the given block.
     */
    function getOperatorWeightAtBlock(
        address operator,
        uint32 blockNumber
    ) external view returns (uint256);

    /**
     * @notice Retrieves the total weight at a specific block number.
     * @param blockNumber The block number to query at.
     * @return The total weight at the given block.
     */
    function getLastCheckpointTotalWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256);

    /**
     * @notice Retrieves the threshold weight at a specific block number.
     * @param blockNumber The block number to query at.
     * @return The threshold weight at the given block.
     */
    function getLastCheckpointThresholdWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256);

    /**
     * @notice Retrieves the quorum at a specific block number.
     * @param blockNumber The block number to query at.
     * @return The quorum numerator at the given block.
     * @return The quorum denominator at the given block.
     */
    function getLastCheckpointQuorumAtBlock(
        uint32 blockNumber
    ) external view returns (uint256, uint256);
}

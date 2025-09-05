// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC1271Upgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1271Upgradeable.sol";

// TODO: many of these errors do not have test coverage.

interface IPOAStakeRegistryErrors {
    /// @notice Thrown when the lengths of the signers array and signatures array do not match.
    error LengthMismatch();
    /// @notice Thrown when encountering an invalid length for the signers or signatures array.
    error InvalidLength();
    /// @notice Thrown when encountering an invalid signature.
    error InvalidSignature();
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
    /// @notice Thrown when de-registering or updating the stake for an unregisted operator.
    error OperatorNotRegistered();
}

interface IPOAStakeRegistryTypes {}

interface IPOAStakeRegistryEvents is IPOAStakeRegistryTypes {
    /*
     * @notice Emitted when the system registers an operator.
     * @param operator The address of the registered operator.
     */
    event OperatorRegistered(address indexed operator);

    /*
     * @notice Emitted when the system deregisters an operator.
     * @param operator The address of the deregistered operator.
     */
    event OperatorDeregistered(address indexed operator);

    /*
     * @notice Emitted when the weight to join the operator set updates.
     * @param previous The previous minimum weight.
     * @param current The new minimumWeight.
     */
    event MinimumWeightUpdated(uint256 previous, uint256 current);

    /*
     * @notice Emitted when the system updates an operator's weight.
     * @param operator The address of the operator updated.
     * @param oldWeight The operator's weight before the update.
     * @param newWeight The operator's weight after the update.
     */
    event OperatorWeightUpdated(address indexed operator, uint256 oldWeight, uint256 newWeight);

    /*
     * @notice Emitted when the system updates the total weight.
     * @param oldTotalWeight The total weight before the update.
     * @param newTotalWeight The total weight after the update.
     */
    event TotalWeightUpdated(uint256 oldTotalWeight, uint256 newTotalWeight);

    /*
     * @notice Emits when setting a new threshold weight.
     */
    event ThresholdWeightUpdated(uint256 thresholdWeight);

    /*
     * @notice Emitted when an operator's signing key is updated.
     * @param operator The address of the operator whose signing key was updated.
     * @param updateBlock The block number at which the signing key was updated.
     * @param newSigningKey The operator's signing key after the update.
     * @param oldSigningKey The operator's signing key before the update.
     */
    event SigningKeyUpdate(
        address indexed operator,
        uint256 indexed updateBlock,
        address indexed newSigningKey,
        address oldSigningKey
    );
}

interface IPOAStakeRegistry is
    IPOAStakeRegistryErrors,
    IPOAStakeRegistryEvents,
    IERC1271Upgradeable
{
    /* ACTIONS */

    /*
     * @notice Registers a new operator using a provided operator address and weight.
     * @param operator The address of the operator to register.
     * @param weight The weight of the operator.
     */
    function registerOperator(address operator, uint256 weight) external;

    /*
     * @notice Deregisters an existing operator.
     * @param operator The address of the operator to deregister.
     */
    function deregisterOperator(
        address operator
    ) external;

    /*
     * @notice Updates the signing key for an operator.
     * @param newSigningKey The new signing key to set for the operator.
     * @dev Only callable by the operator themselves.
     */
    function updateOperatorSigningKey(
        address newSigningKey
    ) external;

    /*
     * @notice Updates the weight for an operator.
     * @param operator The address of the operator to update the weight for.
     * @param weight The new weight to set for the operator.
     * @dev Only callable by owner.
     */
    function updateOperatorWeight(
        address operator,
        uint256 weight
    ) external;

    /*
     * @notice Updates the weight an operator must have to join the operator set.
     * @param newMinimumWeight The new weight an operator must have to join the operator set.
     */
    function updateMinimumWeight(
        uint256 newMinimumWeight
    ) external;

    /*
     * @notice Sets a new cumulative threshold weight for message validation.
     * @param thresholdWeight The updated threshold weight required to validate a message.
     */
    function updateStakeThreshold(
        uint256 thresholdWeight
    ) external;

    /* VIEW */

    /*
     * @notice Retrieves the latest signing key for a given operator.
     * @param operator The address of the operator.
     * @return The latest signing key of the operator.
     */
    function getLatestOperatorSigningKey(
        address operator
    ) external view returns (address);

    /*
     * @notice Retrieves the signing key for an operator at a specific block.
     * @param operator The address of the operator.
     * @param blockNumber The block number to query at.
     * @return The signing key of the operator at the given block.
     */
    function getOperatorSigningKeyAtBlock(
        address operator,
        uint256 blockNumber
    ) external view returns (address);

    /*
     * @notice Retrieves the last recorded weight for a given operator.
     * @param operator The address of the operator.
     * @return The latest weight of the operator.
     */
    function getLastCheckpointOperatorWeight(
        address operator
    ) external view returns (uint256);

    /*
     * @notice Retrieves the last recorded total weight across all operators.
     * @return The latest total weight.
     */
    function getLastCheckpointTotalWeight() external view returns (uint256);

    /*
     * @notice Retrieves the last recorded threshold weight.
     * @return The latest threshold weight.
     */
    function getLastCheckpointThresholdWeight() external view returns (uint256);

    /*
     * @notice Returns whether an operator is currently registered.
     * @param operator The operator address to check.
     * @return Whether the operator is registered.
     */
    function operatorRegistered(
        address operator
    ) external view returns (bool);

    /*
     * @notice Returns the minimum weight required for operator participation.
     * @return The minimum weight threshold.
     */
    function minimumWeight() external view returns (uint256);

    /*
     * @notice Retrieves the operator's weight at a specific block number.
     * @param operator The address of the operator.
     * @param blockNumber The block number to query at.
     * @return The weight of the operator at the given block.
     */
    function getOperatorWeightAtBlock(
        address operator,
        uint32 blockNumber
    ) external view returns (uint256);

    /*
     * @notice Retrieves the operator's weight.
     * @param operator The address of the operator.
     * @return The current weight of the operator.
     */
    function getOperatorWeight(
        address operator
    ) external view returns (uint256);

    /*
     * @notice Retrieves the total weight at a specific block number.
     * @param blockNumber The block number to query at.
     * @return The total weight at the given block.
     */
    function getLastCheckpointTotalWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256);

    /*
     * @notice Retrieves the threshold weight at a specific block number.
     * @param blockNumber The block number to query at.
     * @return The threshold weight at the given block.
     */
    function getLastCheckpointThresholdWeightAtBlock(
        uint32 blockNumber
    ) external view returns (uint256);
}

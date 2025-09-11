// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Checkpoints} from
    "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IPOAStakeRegistry} from "./interfaces/IPOAStakeRegistry.sol";

/**
 * @title Storage variables for the `POAStakeRegistry` contract.
 * @author Layr Labs, Inc.
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract POAStakeRegistryStorage is IPOAStakeRegistry {
    /// @notice The size of the current operator set
    uint256 internal _totalOperators;

    /// @notice Maps an operator to their signing key history using checkpoints
    mapping(address => Checkpoints.Trace160) internal _operatorSigningKeyHistory;

    /// @notice Tracks the total stake history over time using checkpoints
    Checkpoints.Trace160 internal _totalWeightHistory;

    /// @notice Tracks the threshold bps history using checkpoints
    Checkpoints.Trace160 internal _thresholdWeightHistory;

    /// @notice Tracks the quorum numerator history over time using checkpoints
    Checkpoints.Trace160 internal _quorumNumeratorHistory;

    /// @notice Tracks the quorum denominator history over time using checkpoints
    Checkpoints.Trace160 internal _quorumDenominatorHistory;

    /// @notice Maps operator addresses to their respective stake histories using checkpoints
    mapping(address => Checkpoints.Trace160) internal _operatorWeightHistory;

    /// @notice Maps an operator to their registration status
    mapping(address => bool) internal _operatorRegistered;

    // slither-disable-next-line shadowing-state
    /// @dev Reserves storage slots for future upgrades
    // solhint-disable-next-line
    uint256[40] private __gap;
}

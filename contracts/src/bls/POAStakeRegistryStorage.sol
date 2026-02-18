// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IPOAStakeRegistry} from "./interfaces/IPOAStakeRegistry.sol";
import {IWavsServiceManager} from "./interfaces/IWavsServiceManager.sol";

/**
 * @title Storage variables for the BLS `POAStakeRegistry` contract.
 * @author Lay3r Labs
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract POAStakeRegistryStorage is IPOAStakeRegistry, IWavsServiceManager {
    /// @notice Checkpoint for tracking BLS key history per operator.
    struct BLSKeyCheckpoint {
        uint96 blockNumber;
        bytes32 keyHash;
    }

    /// @notice The size of the current operator set
    uint256 internal _totalOperators;

    /// @notice The service URI
    string internal _serviceuri;

    /// @notice Full BLS key storage: keyHash -> 128-byte G1 public key (permanent, append-only)
    mapping(bytes32 => bytes) internal _blsKeyStore;

    /// @notice Forward mapping: operator -> BLS key history (custom checkpoint array)
    mapping(address => BLSKeyCheckpoint[]) internal _operatorBLSKeyHistory;

    /// @notice Reverse mapping: keyHash -> operator history (Trace160 since operator is uint160)
    mapping(bytes32 => Checkpoints.Trace160) internal _signingKeyOperatorHistory;

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

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/**
 * @title EmptyContract
 * @author Lay3rLabs
 * @notice This contract is used to deploy an empty contract.
 * @dev This contract is used to deploy an empty contract.
 */
contract EmptyContract {
    /**
     * @notice The foo function.
     * @return The result of the foo function.
     */
    function foo() public pure returns (uint256) {
        return 0;
    }
}

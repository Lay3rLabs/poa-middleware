// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {POAStakeRegistry} from "src/ecdsa/POAStakeRegistry.sol";

/**
 * @title POAMiddlewareDeployer
 * @author Lay3rLabs
 * @notice This script deploys the POAMiddleware contracts.
 * @dev This script is used to deploy the POAMiddleware contracts.
 */
contract POAMiddlewareDeployer is Script {
    using Strings for *;
    using UpgradeableProxyLib for address;

    /// @notice The proxy admin address.
    address public proxyAdmin;
    /// @notice The deployment data.
    address public poaStakeRegistry;

    /// @notice The run function.
    function run() public virtual {
        vm.startBroadcast();
        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        // deploy middleware contracts
        poaStakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(proxyAdmin);
        address poaStakeRegistryImpl = address(new POAStakeRegistry());
        bytes memory poaStakeRegistryUpgradeCall =
            abi.encodeCall(POAStakeRegistry.initialize, (100, 1, 1));
        UpgradeableProxyLib.upgradeAndCall(
            poaStakeRegistry, poaStakeRegistryImpl, poaStakeRegistryUpgradeCall
        );

        vm.stopBroadcast();

        writeDeploymentJson();
    }

    /// @notice The write deployment JSON function.
    function writeDeploymentJson() internal {
        proxyAdmin = address(UpgradeableProxyLib.getProxyAdmin(poaStakeRegistry));

        string memory deploymentData = _generateDeploymentJson();

        if (!vm.exists("deployments/poa-ecdsa")) {
            vm.createDir("deployments/poa-ecdsa", true);
        }

        // solhint-disable-next-line gas-small-strings
        vm.writeFile("deployments/poa-ecdsa/poa_deploy.json", deploymentData);
    }

    /**
     * @notice The generate deployment JSON function.
     * @return deploymentData The deployment JSON.
     */
    function _generateDeploymentJson() internal view returns (string memory) {
        return string.concat(
            "{",
            "\"lastUpdate\":{",
            "\"timestamp\":\"",
            vm.toString(block.timestamp),
            "\",",
            "\"block_number\":\"",
            vm.toString(block.number),
            "\"",
            "},",
            "\"addresses\":",
            _generateContractsJson(),
            "}"
        );
    }

    /**
     * @notice The generate contracts JSON function.
     * @return contractsJson The contracts JSON.
     */
    function _generateContractsJson() internal view returns (string memory) {
        return string.concat(
            "{\"proxyAdmin\":\"",
            proxyAdmin.toHexString(),
            "\",\"POAStakeRegistry\":\"",
            poaStakeRegistry.toHexString(),
            "\"}"
        );
    }
}

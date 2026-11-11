// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CascadeVault} from "../src/CascadeVault.sol";
import {IdleStrategy} from "../src/strategies/IdleStrategy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployVault
 * @notice Anvil-first deploy of CascadeVault + IdleStrategy.
 */
contract DeployVault is Script {
    function run() external returns (CascadeVault vault, IdleStrategy strategy, HelperConfig config) {
        config = new HelperConfig();
        (address assetAddr, address feeRecipient, uint256 withdrawalFeeBps, address deployer) =
            config.activeNetworkConfig();

        vm.startBroadcast();
        vault = new CascadeVault(
            IERC20(assetAddr), "Cascade Vault DAI", "cvDAI", deployer, feeRecipient, withdrawalFeeBps
        );
        strategy = new IdleStrategy(IERC20(assetAddr), address(vault));
        vault.setStrategy(strategy);
        vm.stopBroadcast();

        console2.log("CascadeVault", address(vault));
        console2.log("IdleStrategy", address(strategy));
        console2.log("Asset", assetAddr);
    }
}

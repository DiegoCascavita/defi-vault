// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CascadeVault} from "../src/CascadeVault.sol";
import {IdleStrategy} from "../src/strategies/IdleStrategy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @title DeployVault
 * @notice Deploys CascadeVault + IdleStrategy (Anvil mocks or Sepolia WETH).
 *
 * Anvil:
 *   anvil
 *   forge script script/DeployVault.s.sol:DeployVault \
 *     --rpc-url http://127.0.0.1:8545 --broadcast -vvvv
 *
 * Sepolia (requires secrets in env — do NOT invent keys):
 *   source .env   # SEPOLIA_RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY
 *   forge script script/DeployVault.s.sol:DeployVault \
 *     --rpc-url "$SEPOLIA_RPC_URL" --broadcast --verify -vvvv
 */
contract DeployVault is Script {
    function run() external returns (CascadeVault vault, IdleStrategy strategy, HelperConfig config) {
        config = new HelperConfig();
        (address assetAddr, address feeRecipient, uint256 withdrawalFeeBps, address deployer, uint256 deployerKey) =
            config.activeNetworkConfig();

        bool isSepolia = block.chainid == config.SEPOLIA_CHAIN_ID();
        if (isSepolia && deployerKey == 0) {
            revert("DeployVault: PRIVATE_KEY not set - refuse to broadcast without a key");
        }

        string memory vaultName = isSepolia ? "Cascade Vault WETH" : "Cascade Vault DAI";
        string memory vaultSymbol = isSepolia ? "cvWETH" : "cvDAI";

        vm.startBroadcast(deployerKey);
        vault = new CascadeVault(
            IERC20(assetAddr), vaultName, vaultSymbol, deployer, feeRecipient, withdrawalFeeBps
        );
        strategy = new IdleStrategy(IERC20(assetAddr), address(vault));
        vault.setStrategy(strategy);
        vm.stopBroadcast();

        console2.log("CascadeVault", address(vault));
        console2.log("IdleStrategy", address(strategy));
        console2.log("Asset", assetAddr);
        console2.log("Deployer", deployer);
    }
}

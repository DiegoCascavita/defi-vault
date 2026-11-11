// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

/**
 * @title HelperConfig
 * @notice Network config for Cascade Vault — Anvil mocks + Sepolia lending/dapp WETH.
 * @dev Sepolia underlying follows lending/dapp WETH
 *      `0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9` (not DSC's Uniswap WETH9).
 *      `deployerKey` reads `PRIVATE_KEY` on Sepolia; Anvil uses the Foundry default key.
 */
contract HelperConfig is Script {
    struct NetworkConfig {
        address asset;
        address feeRecipient;
        uint256 withdrawalFeeBps;
        address deployer;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @dev Canonical Sepolia WETH used by defi-lending / defi-dapp.
    address public constant SEPOLIA_WETH_LENDING = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    /// @dev Uniswap Sepolia WETH9 used by defi-stablecoin collateral — not the vault default.
    address public constant SEPOLIA_WETH_DSC = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    /**
     * @notice Sepolia config: lending/dapp WETH, zero withdrawal fee, deployer from `PRIVATE_KEY`.
     * @dev `deployerKey == 0` means the key is missing — DeployVault must refuse to broadcast.
     */
    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = deployerKey == 0 ? address(0) : vm.addr(deployerKey);
        return NetworkConfig({
            asset: SEPOLIA_WETH_LENDING,
            feeRecipient: deployer,
            withdrawalFeeBps: 0,
            deployer: deployer,
            deployerKey: deployerKey
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.asset != address(0)) {
            return activeNetworkConfig;
        }

        address deployer = vm.addr(DEFAULT_ANVIL_KEY);

        vm.startBroadcast(DEFAULT_ANVIL_KEY);
        ERC20Mock mockDai = new ERC20Mock("Mock DAI", "mDAI", 18);
        vm.stopBroadcast();

        return NetworkConfig({
            asset: address(mockDai),
            feeRecipient: deployer,
            withdrawalFeeBps: 0,
            deployer: deployer,
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}

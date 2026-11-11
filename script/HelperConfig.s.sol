// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

/**
 * @title HelperConfig
 * @notice Network config for Cascade Vault — Anvil mocks first; Sepolia placeholders only.
 * @dev v0 does not broadcast to Sepolia. When it does, prefer lending/dapp WETH
 *      `0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9` (not DSC's Uniswap WETH9).
 */
contract HelperConfig is Script {
    struct NetworkConfig {
        address asset;
        address feeRecipient;
        uint256 withdrawalFeeBps;
        address deployer;
    }

    NetworkConfig public activeNetworkConfig;

    // Sepolia placeholders (documented; unused until Phase 4).
    address public constant SEPOLIA_WETH_LENDING = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address public constant SEPOLIA_WETH_DSC = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        // Placeholder only — do not broadcast in v0.
        return NetworkConfig({
            asset: SEPOLIA_WETH_LENDING,
            feeRecipient: msg.sender,
            withdrawalFeeBps: 0,
            deployer: msg.sender
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.asset != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock mockDai = new ERC20Mock("Mock DAI", "mDAI", 18);
        vm.stopBroadcast();

        return NetworkConfig({
            asset: address(mockDai),
            feeRecipient: msg.sender,
            withdrawalFeeBps: 0,
            deployer: msg.sender
        });
    }
}

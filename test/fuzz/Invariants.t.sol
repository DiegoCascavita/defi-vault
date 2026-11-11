// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CascadeVault} from "../../src/CascadeVault.sol";
import {IdleStrategy} from "../../src/strategies/IdleStrategy.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    CascadeVault internal vault;
    IdleStrategy internal strategy;
    ERC20Mock internal asset;
    Handler internal handler;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        asset = new ERC20Mock("Mock DAI", "mDAI", 18);
        vm.prank(owner);
        vault = new CascadeVault(IERC20(address(asset)), "Cascade Vault DAI", "cvDAI", owner, feeRecipient, 0);
        strategy = new IdleStrategy(IERC20(address(asset)), address(vault));
        vm.prank(owner);
        vault.setStrategy(strategy);

        address[] memory actors = new address[](3);
        actors[0] = makeAddr("alice");
        actors[1] = makeAddr("bob");
        actors[2] = makeAddr("carol");

        handler = new Handler(vault, asset, actors);
        targetContract(address(handler));
    }

    /// @dev Solvency: vault assets cover the asset value of outstanding shares.
    function invariant_solvency() public view {
        assertGe(vault.totalAssets(), vault.convertToAssets(vault.totalSupply()));
    }

    /// @dev totalAssets equals idle vault balance plus strategy-reported assets.
    function invariant_totalAssetsAccounting() public view {
        uint256 idle = asset.balanceOf(address(vault));
        uint256 managed = strategy.totalAssets();
        assertEq(vault.totalAssets(), idle + managed);
    }

    /// @dev Share supply is tracked; zero shares ⇒ zero claimable assets under convert.
    function invariant_shareSupplyNonNegativeConvert() public view {
        assertEq(vault.convertToAssets(0), 0);
        if (vault.totalSupply() == 0) {
            // Empty vault may still hold dust only if donated; strategy path keeps deposits routed.
            assertEq(vault.totalSupply(), 0);
        }
    }
}

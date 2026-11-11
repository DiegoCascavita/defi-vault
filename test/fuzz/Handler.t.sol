// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CascadeVault} from "../../src/CascadeVault.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/// @notice Ghost-accounting handler for CascadeVault invariant suite.
contract Handler is Test {
    CascadeVault public vault;
    ERC20Mock public asset;

    address[] public actors;
    uint256 public ghostSumDeposited;
    uint256 public ghostSumWithdrawn;

    constructor(CascadeVault vault_, ERC20Mock asset_, address[] memory actors_) {
        vault = vault_;
        asset = asset_;
        actors = actors_;
    }

    function deposit(uint256 actorSeed, uint256 amount) public {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e6, 10_000e18);

        asset.mint(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), amount);
        vault.deposit(amount, actor);
        vm.stopPrank();

        ghostSumDeposited += amount;
    }

    function withdraw(uint256 actorSeed, uint256 amount) public {
        address actor = actors[actorSeed % actors.length];
        uint256 maxW = vault.maxWithdraw(actor);
        if (maxW == 0) return;
        amount = bound(amount, 1, maxW);

        vm.prank(actor);
        vault.withdraw(amount, actor, actor);

        ghostSumWithdrawn += amount;
    }

    function redeem(uint256 actorSeed, uint256 shares) public {
        address actor = actors[actorSeed % actors.length];
        uint256 bal = vault.balanceOf(actor);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);

        uint256 beforeBal = asset.balanceOf(actor);
        vm.prank(actor);
        vault.redeem(shares, actor, actor);
        ghostSumWithdrawn += asset.balanceOf(actor) - beforeBal;
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }
}

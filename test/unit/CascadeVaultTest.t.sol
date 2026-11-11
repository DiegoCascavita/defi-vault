// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CascadeVault} from "../../src/CascadeVault.sol";
import {IdleStrategy} from "../../src/strategies/IdleStrategy.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract CascadeVaultTest is Test {
    CascadeVault internal vault;
    IdleStrategy internal strategy;
    ERC20Mock internal asset;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant INITIAL = 1_000_000e18;

    function setUp() public {
        asset = new ERC20Mock("Mock DAI", "mDAI", 18);

        vm.prank(owner);
        vault = new CascadeVault(IERC20(address(asset)), "Cascade Vault DAI", "cvDAI", owner, feeRecipient, 0);

        strategy = new IdleStrategy(IERC20(address(asset)), address(vault));

        vm.prank(owner);
        vault.setStrategy(strategy);

        asset.mint(alice, INITIAL);
        asset.mint(bob, INITIAL);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_DepositMintsShares() public {
        uint256 assets = 100e18;
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), assets);
        assertEq(strategy.totalAssets(), assets);
    }

    function test_MintBurnsExactShares() public {
        uint256 shares = 50e18;
        vm.prank(alice);
        uint256 assets = vault.mint(shares, alice);

        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.convertToShares(assets), shares);
    }

    function test_WithdrawReturnsAssets() public {
        uint256 assets = 200e18;
        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 beforeBal = asset.balanceOf(alice);
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(assets, alice, alice);

        assertGt(sharesBurned, 0);
        assertEq(asset.balanceOf(alice), beforeBal + assets);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_RedeemReturnsAssets() public {
        uint256 assets = 150e18;
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);

        assertEq(received, assets);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_WithdrawalFeeSkim() public {
        vm.prank(owner);
        vault.setWithdrawalFeeBps(50); // 0.50%

        uint256 assets = 10_000e18;
        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 withdrawAmount = 1_000e18;
        uint256 feeBefore = asset.balanceOf(feeRecipient);
        uint256 aliceBefore = asset.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        assertEq(asset.balanceOf(alice), aliceBefore + withdrawAmount);
        assertGt(asset.balanceOf(feeRecipient), feeBefore);
    }

    function test_PreviewHelpersMatchRoundTrip() public {
        vm.prank(alice);
        vault.deposit(1_000e18, alice);

        uint256 assets = 100e18;
        uint256 shares = vault.previewDeposit(assets);
        assertEq(vault.previewMint(shares), assets);

        uint256 wShares = vault.previewWithdraw(assets);
        assertGe(vault.previewRedeem(wShares), assets - 1); // allow 1 wei rounding
    }

    function test_ZeroDepositNoShares() public {
        // OZ ERC-4626 allows a zero-asset deposit as a no-op (0 shares minted).
        vm.prank(alice);
        uint256 shares = vault.deposit(0, alice);
        assertEq(shares, 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_ConvertRoundTripNoFreeValue() public {
        vm.prank(alice);
        vault.deposit(500e18, alice);

        uint256 a = 123e18;
        assertLe(vault.convertToAssets(vault.convertToShares(a)), a);

        uint256 s = vault.balanceOf(alice) / 2;
        assertLe(vault.convertToShares(vault.convertToAssets(s)), s);
    }

    function test_OnlyOwnerSetsFee() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setWithdrawalFeeBps(10);
    }

    function test_FeeTooHighReverts() public {
        vm.prank(owner);
        vm.expectRevert(CascadeVault.CascadeVault__FeeTooHigh.selector);
        vault.setWithdrawalFeeBps(51);
    }
}

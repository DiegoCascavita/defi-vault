// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CascadeVault} from "../../src/CascadeVault.sol";
import {IdleStrategy} from "../../src/strategies/IdleStrategy.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract CascadeVaultFuzz is Test {
    CascadeVault internal vault;
    IdleStrategy internal strategy;
    ERC20Mock internal asset;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        asset = new ERC20Mock("Mock DAI", "mDAI", 18);
        vm.prank(owner);
        vault = new CascadeVault(IERC20(address(asset)), "Cascade Vault DAI", "cvDAI", owner, feeRecipient, 0);
        strategy = new IdleStrategy(IERC20(address(asset)), address(vault));
        vm.prank(owner);
        vault.setStrategy(strategy);
    }

    function testFuzz_DepositRedeemRoundTrip(address actor, uint256 amount) public {
        vm.assume(actor != address(0) && actor != address(vault) && actor != address(strategy));
        amount = bound(amount, 1e6, 1_000_000e18);

        asset.mint(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, actor);
        uint256 received = vault.redeem(shares, actor, actor);
        vm.stopPrank();

        // No free assets; allow tiny rounding loss.
        assertLe(received, amount);
        assertGe(received + 1, amount); // at most 1 wei loss with virtual offset 0 on first depositor
    }

    function testFuzz_ConvertBounds(uint256 seedAssets, uint256 sample) public {
        seedAssets = bound(seedAssets, 1e18, 1_000_000e18);
        sample = bound(sample, 1, seedAssets);

        address depositor = makeAddr("depositor");
        asset.mint(depositor, seedAssets);
        vm.startPrank(depositor);
        asset.approve(address(vault), seedAssets);
        vault.deposit(seedAssets, depositor);
        vm.stopPrank();

        assertLe(vault.convertToAssets(vault.convertToShares(sample)), sample);
        uint256 shares = vault.convertToShares(sample);
        if (shares > 0) {
            assertLe(vault.convertToShares(vault.convertToAssets(shares)), shares);
        }
    }

    function testFuzz_WithdrawWithFee(uint256 amount, uint256 feeBps) public {
        amount = bound(amount, 1e18, 100_000e18);
        feeBps = bound(feeBps, 0, 50);

        vm.prank(owner);
        vault.setWithdrawalFeeBps(feeBps);

        address actor = makeAddr("actor");
        asset.mint(actor, amount * 2);
        vm.startPrank(actor);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amount * 2, actor);

        uint256 beforeBal = asset.balanceOf(actor);
        uint256 withdrawAmt = amount;
        vault.withdraw(withdrawAmt, actor, actor);
        vm.stopPrank();

        assertEq(asset.balanceOf(actor), beforeBal + withdrawAmt);
        // Vault remaining + fees skimmed == deposited - net withdrawn (feeRecipient started at 0).
        assertEq(vault.totalAssets() + asset.balanceOf(feeRecipient), amount * 2 - withdrawAmt);
        // Solvency: remaining assets cover remaining shares.
        assertGe(vault.totalAssets(), vault.convertToAssets(vault.totalSupply()));
    }
}

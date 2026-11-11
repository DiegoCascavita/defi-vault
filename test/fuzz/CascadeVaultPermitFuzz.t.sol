// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {CascadeVault} from "../../src/CascadeVault.sol";
import {IdleStrategy} from "../../src/strategies/IdleStrategy.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract CascadeVaultPermitFuzzTest is Test {
    CascadeVault internal vault;
    IdleStrategy internal strategy;
    ERC20Mock internal asset;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 internal alicePk = 0xA11CE;
    address internal alice;

    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        alice = vm.addr(alicePk);

        asset = new ERC20Mock("Mock DAI", "mDAI", 18);

        vm.prank(owner);
        vault = new CascadeVault(IERC20(address(asset)), "Cascade Vault DAI", "cvDAI", owner, feeRecipient, 0);

        strategy = new IdleStrategy(IERC20(address(asset)), address(vault));

        vm.prank(owner);
        vault.setStrategy(strategy);

        asset.mint(alice, type(uint128).max);
    }

    function testFuzz_SharePermitThenRedeemBySpender(uint256 assets, address spender, uint256 deadlineSkew) public {
        vm.assume(spender != address(0) && spender != alice && spender != address(vault));
        assets = bound(assets, 1e18, 1_000_000e18);
        uint256 deadline = block.timestamp + bound(deadlineSkew, 1, 30 days);

        vm.prank(alice);
        asset.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 nonce = vault.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(alicePk, address(vault), alice, spender, shares, nonce, deadline);

        vault.permit(alice, spender, shares, deadline, v, r, s);
        assertEq(vault.allowance(alice, spender), shares);
        assertEq(vault.nonces(alice), nonce + 1);

        // Replay must fail (nonce advanced).
        vm.expectRevert();
        vault.permit(alice, spender, shares, deadline, v, r, s);

        vm.prank(spender);
        uint256 received = vault.redeem(shares, alice, alice);
        assertEq(received, assets);
        assertEq(vault.balanceOf(alice), 0);
    }

    function testFuzz_DepositWithPermitAmounts(uint256 assets, uint256 deadlineSkew) public {
        assets = bound(assets, 1e18, 500_000e18);
        uint256 deadline = block.timestamp + bound(deadlineSkew, 1, 30 days);

        uint256 nonce = asset.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(alicePk, address(asset), alice, address(vault), assets, nonce, deadline);

        vm.prank(alice);
        uint256 shares = vault.depositWithPermit(assets, alice, deadline, v, r, s);

        assertEq(vault.balanceOf(alice), shares);
        assertEq(asset.nonces(alice), nonce + 1);

        // Bad signature (wrong value) must not increase allowance when called via permit directly.
        (uint8 v2, bytes32 r2, bytes32 s2) =
            _signPermit(alicePk, address(asset), alice, address(vault), assets, asset.nonces(alice), deadline);
        vm.expectRevert();
        asset.permit(alice, address(vault), assets + 1, deadline, v2, r2, s2);
    }

    function testFuzz_ExpiredSharePermitAlwaysReverts(uint256 assets, uint256 pastSkew) public {
        assets = bound(assets, 1e18, 100_000e18);
        pastSkew = bound(pastSkew, 1, 365 days);

        vm.prank(alice);
        asset.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 deadline = vm.getBlockTimestamp();
        vm.warp(deadline + pastSkew);

        address spender = makeAddr("spender");
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(alicePk, address(vault), alice, spender, shares, vault.nonces(alice), deadline);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        vault.permit(alice, spender, shares, deadline, v, r, s);
    }

    function _signPermit(
        uint256 pk,
        address token,
        address owner_,
        address spender_,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = ERC20Permit(token).DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner_, spender_, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(pk, digest);
    }
}

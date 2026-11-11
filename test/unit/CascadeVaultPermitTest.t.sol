// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {CascadeVault} from "../../src/CascadeVault.sol";
import {IdleStrategy} from "../../src/strategies/IdleStrategy.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract CascadeVaultPermitTest is Test {
    CascadeVault internal vault;
    IdleStrategy internal strategy;
    ERC20Mock internal asset;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal spender = makeAddr("spender");

    uint256 internal alicePk = 0xA11CE;
    address internal alice;

    uint256 internal constant INITIAL = 1_000_000e18;

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

        asset.mint(alice, INITIAL);
    }

    /*//////////////////////////////////////////////////////////////
                         SHARE PERMIT (EIP-2612)
    //////////////////////////////////////////////////////////////*/

    function test_SharePermitSetsAllowance() public {
        uint256 assets = 100e18;
        vm.prank(alice);
        asset.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, address(vault), alice, spender, shares, 0, deadline);

        vault.permit(alice, spender, shares, deadline, v, r, s);

        assertEq(vault.allowance(alice, spender), shares);
        assertEq(vault.nonces(alice), 1);
    }

    function test_SharePermitExpiredReverts() public {
        uint256 assets = 50e18;
        vm.prank(alice);
        asset.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 deadline = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, address(vault), alice, spender, shares, 0, deadline);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        vault.permit(alice, spender, shares, deadline, v, r, s);
    }

    function test_SharePermitBadSignatureReverts() public {
        uint256 assets = 50e18;
        vm.prank(alice);
        asset.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 deadline = block.timestamp + 1 days;
        // Sign for a different spender than the one submitted on-chain.
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, address(vault), alice, spender, shares, 0, deadline);

        address other = makeAddr("other");
        vm.expectRevert();
        vault.permit(alice, other, shares, deadline, v, r, s);
    }

    function test_SharePermitReplayReverts() public {
        uint256 assets = 50e18;
        vm.prank(alice);
        asset.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, address(vault), alice, spender, shares, 0, deadline);

        vault.permit(alice, spender, shares, deadline, v, r, s);

        vm.expectRevert();
        vault.permit(alice, spender, shares, deadline, v, r, s);
    }

    function test_SharePermitWrongNonceReverts() public {
        uint256 assets = 50e18;
        vm.prank(alice);
        asset.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        uint256 deadline = block.timestamp + 1 days;
        // Nonce 1 while on-chain nonce is still 0.
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, address(vault), alice, spender, shares, 1, deadline);

        vm.expectRevert();
        vault.permit(alice, spender, shares, deadline, v, r, s);
        assertEq(vault.nonces(alice), 0);
    }

    function test_DomainSeparatorIsStable() public view {
        bytes32 separator = vault.DOMAIN_SEPARATOR();
        assertEq(separator, vault.DOMAIN_SEPARATOR());
        assertTrue(separator != bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                      depositWithPermit (underlying)
    //////////////////////////////////////////////////////////////*/

    function test_DepositWithPermit() public {
        uint256 assets = 200e18;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(alicePk, address(asset), alice, address(vault), assets, 0, deadline);

        vm.prank(alice);
        uint256 shares = vault.depositWithPermit(assets, alice, deadline, v, r, s);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(asset.nonces(alice), 1);
        assertEq(asset.allowance(alice, address(vault)), 0);
    }

    function test_DepositWithPermitReplayDoesNotDoubleSpend() public {
        uint256 assets = 100e18;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(alicePk, address(asset), alice, address(vault), assets, 0, deadline);

        vm.prank(alice);
        vault.depositWithPermit(assets, alice, deadline, v, r, s);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetBefore = asset.balanceOf(alice);

        // Frontrun / replay: try/catch swallows the failed permit; transferFrom then fails (no allowance).
        vm.prank(alice);
        vm.expectRevert();
        vault.depositWithPermit(assets, alice, deadline, v, r, s);

        assertEq(vault.balanceOf(alice), sharesBefore);
        assertEq(asset.balanceOf(alice), assetBefore);
        assertEq(asset.nonces(alice), 1);
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

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

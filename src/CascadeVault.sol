// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICascadeStrategy} from "./interfaces/ICascadeStrategy.sol";

/**
 * @title CascadeVault
 * @notice ERC-4626 share vault with optional withdrawal fee and pluggable strategy.
 * @dev Fourth leg of the Cascade DeFi suite (after stablecoin, lending, dapp).
 *      Fees skim to `feeRecipient` on withdraw/redeem. Strategy defaults to IdleStrategy.
 */
contract CascadeVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_WITHDRAWAL_FEE_BPS = 50; // 0.50%

    ICascadeStrategy public strategy;
    address public feeRecipient;
    uint256 public depositFeeBps; // reserved; default 0
    uint256 public withdrawalFeeBps; // owner-configurable, capped at MAX_WITHDRAWAL_FEE_BPS

    event StrategyUpdated(address indexed previousStrategy, address indexed newStrategy);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event DepositFeeUpdated(uint256 previousBps, uint256 newBps);
    event WithdrawalFeeUpdated(uint256 previousBps, uint256 newBps);
    event WithdrawalFeeSkimmed(address indexed recipient, uint256 assets);
    /// @dev Stub for a future streaming management fee (not accrued in v0).
    event ManagementFeeAccrued(uint256 virtualAssets, uint256 timestamp);

    error CascadeVault__ZeroAddress();
    error CascadeVault__FeeTooHigh();
    error CascadeVault__StrategyAssetMismatch();

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address feeRecipient_,
        uint256 withdrawalFeeBps_
    ) ERC20(name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        if (feeRecipient_ == address(0)) revert CascadeVault__ZeroAddress();
        if (withdrawalFeeBps_ > MAX_WITHDRAWAL_FEE_BPS) revert CascadeVault__FeeTooHigh();
        feeRecipient = feeRecipient_;
        withdrawalFeeBps = withdrawalFeeBps_;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER CONTROLS
    //////////////////////////////////////////////////////////////*/

    function setStrategy(ICascadeStrategy newStrategy) external onlyOwner {
        if (address(newStrategy) == address(0)) revert CascadeVault__ZeroAddress();
        if (newStrategy.asset() != asset()) revert CascadeVault__StrategyAssetMismatch();

        address previous = address(strategy);
        // Pull any idle assets from the previous strategy into the vault before switching.
        if (previous != address(0)) {
            uint256 managed = ICascadeStrategy(previous).totalAssets();
            if (managed > 0) {
                ICascadeStrategy(previous).withdraw(managed, address(this));
            }
        }

        strategy = newStrategy;
        emit StrategyUpdated(previous, address(newStrategy));

        // Push vault idle balance into the new strategy (keeps totalAssets continuous).
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle > 0) {
            IERC20(asset()).forceApprove(address(newStrategy), idle);
            newStrategy.deposit(idle);
        }
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert CascadeVault__ZeroAddress();
        address previous = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(previous, newRecipient);
    }

    function setDepositFeeBps(uint256 newBps) external onlyOwner {
        if (newBps > MAX_WITHDRAWAL_FEE_BPS) revert CascadeVault__FeeTooHigh();
        uint256 previous = depositFeeBps;
        depositFeeBps = newBps;
        emit DepositFeeUpdated(previous, newBps);
    }

    function setWithdrawalFeeBps(uint256 newBps) external onlyOwner {
        if (newBps > MAX_WITHDRAWAL_FEE_BPS) revert CascadeVault__FeeTooHigh();
        uint256 previous = withdrawalFeeBps;
        withdrawalFeeBps = newBps;
        emit WithdrawalFeeUpdated(previous, newBps);
    }

    /// @notice Owner hook to realize strategy yield (IdleStrategy returns 0).
    function harvest() external onlyOwner returns (uint256 harvested) {
        if (address(strategy) == address(0)) return 0;
        harvested = strategy.harvest();
        // Management fee remains a stub — emit a virtual accrual marker for interview surface.
        emit ManagementFeeAccrued(0, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-4626
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 managed = address(strategy) == address(0) ? 0 : strategy.totalAssets();
        return idle + managed;
    }

    /**
     * @dev Shares burned for a given asset withdrawal include the fee so the owner
     *      receives exactly `assets` after the skim. Fee assets stay in the vault
     *      (or move to feeRecipient) and reduce claimable value for remaining shares.
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 grossAssets = _grossUpForWithdrawalFee(assets);
        return super.previewWithdraw(grossAssets);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 grossAssets = super.previewRedeem(shares);
        return _netAfterWithdrawalFee(grossAssets);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return _netAfterWithdrawalFee(super.maxWithdraw(owner));
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HOOKS / MATH
    //////////////////////////////////////////////////////////////*/

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        // `assets` is the net amount the receiver gets (both withdraw and redeem paths,
        // thanks to the preview* overrides). Gross value of `shares` funds net + fee.
        uint256 grossFromShares = convertToAssets(shares);
        uint256 fee = grossFromShares > assets ? grossFromShares - assets : _feeOnRaw(assets);

        _ensureLiquidity(assets + fee);

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);

        IERC20 underlying = IERC20(asset());
        if (fee > 0) {
            underlying.safeTransfer(feeRecipient, fee);
            emit WithdrawalFeeSkimmed(feeRecipient, fee);
        }
        underlying.safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        // Route newly deposited assets into the strategy when one is configured.
        if (address(strategy) != address(0) && assets > 0) {
            IERC20 underlying = IERC20(asset());
            underlying.forceApprove(address(strategy), assets);
            strategy.deposit(assets);
        }
    }

    function _ensureLiquidity(uint256 needed) internal {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle >= needed) return;
        if (address(strategy) == address(0)) return;
        uint256 shortfall = needed - idle;
        strategy.withdraw(shortfall, address(this));
    }

    function _feeOnRaw(uint256 assets) internal view returns (uint256) {
        return assets.mulDiv(withdrawalFeeBps, MAX_BPS, Math.Rounding.Ceil);
    }

    function _netAfterWithdrawalFee(uint256 grossAssets) internal view returns (uint256) {
        uint256 fee = grossAssets.mulDiv(withdrawalFeeBps, MAX_BPS, Math.Rounding.Ceil);
        return grossAssets - fee;
    }

    function _grossUpForWithdrawalFee(uint256 netAssets) internal view returns (uint256) {
        if (withdrawalFeeBps == 0) return netAssets;
        // net = gross - ceil(gross * feeBps / MAX_BPS)
        // Solve for gross ≈ net * MAX_BPS / (MAX_BPS - feeBps), rounding up.
        return netAssets.mulDiv(MAX_BPS, MAX_BPS - withdrawalFeeBps, Math.Rounding.Ceil);
    }

    /// @dev Slight virtual-share offset mitigates empty-vault inflation attacks (OZ guidance).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 0;
    }
}

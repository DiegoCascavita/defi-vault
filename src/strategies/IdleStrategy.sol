// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICascadeStrategy} from "../interfaces/ICascadeStrategy.sol";

/**
 * @title IdleStrategy
 * @notice v0 default strategy — holds the underlying ERC-20 without deploying it.
 * @dev Proves vault ↔ strategy wiring. Later: LendingPoolStrategy supplies into Cascade Lend.
 */
contract IdleStrategy is ICascadeStrategy {
    using SafeERC20 for IERC20;

    IERC20 private immutable i_asset;
    address public immutable vault;

    error IdleStrategy__OnlyVault();
    error IdleStrategy__ZeroAddress();

    modifier onlyVault() {
        if (msg.sender != vault) revert IdleStrategy__OnlyVault();
        _;
    }

    constructor(IERC20 asset_, address vault_) {
        if (address(asset_) == address(0) || vault_ == address(0)) {
            revert IdleStrategy__ZeroAddress();
        }
        i_asset = asset_;
        vault = vault_;
    }

    /// @inheritdoc ICascadeStrategy
    function asset() external view returns (address) {
        return address(i_asset);
    }

    /// @inheritdoc ICascadeStrategy
    function totalAssets() external view returns (uint256) {
        return i_asset.balanceOf(address(this));
    }

    /// @inheritdoc ICascadeStrategy
    function deposit(uint256 amount) external onlyVault {
        if (amount == 0) return;
        i_asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc ICascadeStrategy
    function withdraw(uint256 amount, address receiver) external onlyVault {
        if (amount == 0) return;
        i_asset.safeTransfer(receiver, amount);
    }

    /// @inheritdoc ICascadeStrategy
    function harvest() external onlyVault returns (uint256 harvested) {
        // Idle hold — nothing to realize. Touch vault so the function stays non-view.
        if (vault == address(0)) return 0;
        return 0;
    }
}

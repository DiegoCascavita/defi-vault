// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICascadeStrategy
 * @notice Minimal strategy surface for Cascade Vault v0.
 * @dev IdleStrategy holds assets; a future LendingPoolStrategy can supply into Cascade Lend.
 */
interface ICascadeStrategy {
    /// @notice Underlying ERC-20 this strategy manages.
    function asset() external view returns (address);

    /// @notice Assets currently controlled by the strategy (idle or deployed).
    function totalAssets() external view returns (uint256);

    /// @notice Pull `amount` of underlying from the caller into the strategy.
    function deposit(uint256 amount) external;

    /// @notice Return `amount` of underlying to `receiver`.
    function withdraw(uint256 amount, address receiver) external;

    /// @notice Optional yield realization hook (no-op for IdleStrategy).
    function harvest() external returns (uint256 harvested);
}

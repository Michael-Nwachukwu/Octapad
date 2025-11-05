// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

/**
 * @title IStrategyInterface
 * @notice Extended interface for YieldDonating Strategy with custom functions
 */
interface IStrategyInterface is IStrategy {
    // ============================================
    // CUSTOM VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Returns the Kalani vault (yield source) address
     * @return Address of the ERC4626 vault
     */
    function yieldSource() external view returns (address);

    /**
     * @notice Returns minimum idle threshold in basis points
     * @return Threshold BPS (e.g., 100 = 1%)
     */
    function minIdleThresholdBps() external view returns (uint256);

    /**
     * @notice Returns vault health status
     * @return isPaused Whether vault operations are paused
     * @return consecutiveFailures Number of consecutive failures
     * @return lastFailureTime Timestamp of last failure
     */
    function vaultHealth() external view returns (bool isPaused, uint256 consecutiveFailures, uint256 lastFailureTime);

    /**
     * @notice Returns detailed breakdown of assets
     * @return vault Assets deployed in vault
     * @return idle Idle assets in strategy
     * @return total Total assets under management
     */
    function getAssetBreakdown() external view returns (uint256 vault, uint256 idle, uint256 total);

    /**
     * @notice Returns vault health information (same as vaultHealth but named getter)
     * @return isPaused Whether vault is paused
     * @return failures Consecutive failures count
     * @return lastFailure Last failure timestamp
     */
    function getVaultHealth() external view returns (bool isPaused, uint256 failures, uint256 lastFailure);

    // ============================================
    // MANAGEMENT FUNCTIONS
    // ============================================

    /**
     * @notice Manually resumes a paused vault
     * @dev Only callable by management
     */
    function resumeVault() external;

    /**
     * @notice Sets minimum idle threshold for tend trigger
     * @param _thresholdBps Threshold in basis points (max 1000 = 10%)
     * @dev Only callable by management
     */
    function setMinIdleThreshold(uint256 _thresholdBps) external;

    // ============================================
    // CONSTANTS
    // ============================================

    /**
     * @notice Maximum consecutive failures before circuit breaker triggers
     * @return Maximum failures threshold
     */
    function MAX_CONSECUTIVE_FAILURES() external view returns (uint256);

    /**
     * @notice Cooldown period after failure
     * @return Cooldown duration in seconds
     */
    function FAILURE_COOLDOWN() external view returns (uint256);

    /**
     * @notice Maximum basis points (100%)
     * @return 10000 (100%)
     */
    function MAX_BPS() external view returns (uint256);

    // ============================================
    // EVENTS
    // ============================================

    event FundsDeployed(uint256 amount, address yieldSource);
    event FundsWithdrawn(uint256 amount);
    event VaultPaused(address indexed vault, uint256 failures);
    event VaultResumed(address indexed vault);
    event EmergencyWithdrawal(uint256 amount);

    // ============================================
    // ERRORS
    // ============================================

    error VaultPausedError();
    error InvalidVaultAddress();
    error InsufficientLiquidity();
}

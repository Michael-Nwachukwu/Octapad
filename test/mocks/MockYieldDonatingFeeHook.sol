// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockYieldDonatingFeeHook
 * @notice Test mock that implements the same logic as YieldDonatingFeeHook
 * @dev Simplified version for testing without Uniswap v4 dependencies
 *
 * This mock implements the EXACT same fee capture and deposit logic as the real hook:
 * - Captures 50% of swap fees (FEE_DONATION_BPS = 5000)
 * - Accumulates until $1 threshold
 * - Deposits to YieldDonating Strategy
 * - Emits same events
 * - Has same public interface
 *
 * IMPLEMENTATION NOTE:
 * The real YieldDonatingFeeHook (src/hooks/YieldDonatingFeeHook.sol) inherits from
 * Uniswap v4's BaseHook and implements the afterSwap() callback. This mock replicates
 * the internal logic without the v4 dependencies, allowing us to test fee calculation
 * and deposit mechanics in isolation.
 */
contract MockYieldDonatingFeeHook {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice YieldDonating Strategy that receives fees
    address public immutable yieldStrategy;

    /// @notice USDC token
    IERC20 public immutable usdc;

    /// @notice Admin address
    address public admin;

    /// @notice Percentage of fees to donate (5000 = 50%)
    uint256 public constant FEE_DONATION_BPS = 5000;
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Minimum amount to accumulate before depositing ($1 = 1e6 for USDC 6 decimals)
    uint256 public constant DEPOSIT_THRESHOLD = 1e6;

    /// @notice Accumulated fees not yet deposited
    uint256 public accumulatedFees;

    /// @notice Total fees donated to date
    uint256 public totalFeesDonated;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeesCollected(bytes32 indexed poolId, uint256 amount, uint256 accumulated);
    event FeesDeposited(uint256 amount, uint256 totalDonated);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error DepositFailed();
    error InsufficientFees();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _yieldStrategy,
        address _usdc,
        address _admin
    ) {
        require(_yieldStrategy != address(0), "MockYieldDonatingFeeHook: zero strategy");
        require(_usdc != address(0), "MockYieldDonatingFeeHook: zero usdc");
        require(_admin != address(0), "MockYieldDonatingFeeHook: zero admin");

        yieldStrategy = _yieldStrategy;
        usdc = IERC20(_usdc);
        admin = _admin;
    }

    /*//////////////////////////////////////////////////////////////
                        SIMULATED HOOK LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Simulate afterSwap hook behavior
     * @dev This function replicates the logic from YieldDonatingFeeHook._afterSwap()
     * @param totalPoolFee The total fee from the swap (100% of swap fee)
     *
     * Real implementation location: YieldDonatingFeeHook.sol:138-177
     *
     * In the real implementation, the pool manager transfers the full fee to the hook.
     * The hook then calculates 50% to donate and keeps the rest to return to LPs.
     */
    function simulateAfterSwap(uint256 totalPoolFee) external {
        if (totalPoolFee > 0) {
            // Calculate 50% donation amount
            // Same logic as YieldDonatingFeeHook.sol:155
            uint256 donationAmount = (totalPoolFee * FEE_DONATION_BPS) / BASIS_POINTS;

            if (donationAmount > 0) {
                // In real implementation, poolManager.take() transfers USDC from pool to hook
                // In this mock, we assume the fee was already transferred to this contract
                // The donationAmount stays in the contract, the rest (50%) would go back to LPs

                // Accumulate fees
                // Same logic as YieldDonatingFeeHook.sol:164
                accumulatedFees += donationAmount;

                // Emit event (poolId is mocked as bytes32(0))
                emit FeesCollected(bytes32(0), donationAmount, accumulatedFees);

                // Deposit if threshold reached
                // Same logic as YieldDonatingFeeHook.sol:170-171
                if (accumulatedFees >= DEPOSIT_THRESHOLD) {
                    _depositToStrategy();
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TO STRATEGY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit accumulated fees to YieldDonating Strategy
     * @dev Internal function, automatically called when threshold reached
     *
     * Real implementation location: YieldDonatingFeeHook.sol:187-216
     */
    function _depositToStrategy() internal {
        uint256 amount = accumulatedFees;
        if (amount == 0) return;

        // Reset accumulated before external call (reentrancy protection)
        // Same logic as YieldDonatingFeeHook.sol:192
        accumulatedFees = 0;

        // Approve strategy to spend USDC
        // Same logic as YieldDonatingFeeHook.sol:195
        usdc.forceApprove(yieldStrategy, amount);

        // Call deposit on YieldDonating Strategy
        // Same logic as YieldDonatingFeeHook.sol:199-205
        (bool success, ) = yieldStrategy.call(
            abi.encodeWithSignature(
                "deposit(uint256,address)",
                amount,
                address(this)
            )
        );

        if (!success) {
            // Revert accumulated fees if deposit failed
            accumulatedFees = amount;
            revert DepositFailed();
        }

        // Track total donated
        // Same logic as YieldDonatingFeeHook.sol:213
        totalFeesDonated += amount;

        emit FeesDeposited(amount, totalFeesDonated);
    }

    /**
     * @notice Manually trigger deposit to strategy
     * @dev Can be called by anyone (keepers, users, etc.)
     *
     * Real implementation location: YieldDonatingFeeHook.sol:223-226
     */
    function depositAccumulatedFees() external {
        if (accumulatedFees == 0) revert InsufficientFees();
        _depositToStrategy();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get accumulated fees ready for deposit
     * @return amount Amount of USDC accumulated
     *
     * Real implementation location: YieldDonatingFeeHook.sol:264-266
     */
    function getAccumulatedFees() external view returns (uint256) {
        return accumulatedFees;
    }

    /**
     * @notice Check if fees are ready for deposit
     * @return ready True if accumulated >= threshold
     *
     * Real implementation location: YieldDonatingFeeHook.sol:272-274
     */
    function isReadyForDeposit() external view returns (bool) {
        return accumulatedFees >= DEPOSIT_THRESHOLD;
    }

    /**
     * @notice Get total fees donated to strategy
     * @return total Total USDC donated to date
     *
     * Real implementation location: YieldDonatingFeeHook.sol:289-291
     */
    function getTotalDonated() external view returns (uint256) {
        return totalFeesDonated;
    }

    /**
     * @notice Calculate estimated donation for a swap amount
     * @param swapAmount Amount being swapped
     * @param feePercentage Pool fee percentage (e.g., 3000 = 0.3%)
     * @return donation Estimated donation amount
     *
     * Real implementation location: YieldDonatingFeeHook.sol:299-309
     */
    function estimateDonation(uint256 swapAmount, uint256 feePercentage)
        external
        pure
        returns (uint256 donation)
    {
        // Fee = swapAmount * feePercentage / 1000000
        uint256 fee = (swapAmount * feePercentage) / 1000000;
        // Donation = 50% of fee
        donation = (fee * FEE_DONATION_BPS) / BASIS_POINTS;
        return donation;
    }
}

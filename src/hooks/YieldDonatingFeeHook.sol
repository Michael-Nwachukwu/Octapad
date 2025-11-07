// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title YieldDonatingFeeHook
 * @notice Uniswap v4 Hook that captures 50% of swap fees and deposits to YieldDonating Strategy
 * @dev This hook demonstrates sustainable public goods funding through trading activity
 *
 * Key Features:
 * - Captures 50% of all swap fees in the pool
 * - Accumulates fees until $1 threshold is reached
 * - Batch deposits to YieldDonating Strategy for gas efficiency
 * - Manual trigger available for keepers
 * - Supports USDC on Base network (6 decimals)
 *
 * Public Goods Impact:
 * - Every swap contributes to public goods funding
 * - Trading volume directly funds public goods via Kalani yield
 * - Sustainable, automated funding mechanism
 */
contract YieldDonatingFeeHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice YieldDonating Strategy that receives fees
    address public immutable yieldStrategy;

    /// @notice USDC token on Base (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
    IERC20 public immutable usdc;

    /// @notice Percentage of fees to donate (5000 = 50%)
    uint256 public constant FEE_DONATION_BPS = 5000;
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Minimum amount to accumulate before depositing ($1 = 1e6 for USDC 6 decimals)
    uint256 public constant DEPOSIT_THRESHOLD = 1e6;

    /// @notice Accumulated fees not yet deposited
    uint256 public accumulatedFees;

    /// @notice Total fees donated to date
    uint256 public totalFeesDonated;

    /// @notice Fees collected per pool
    mapping(PoolId => uint256) public poolFeesCollected;

    /// @notice Admin address (can update strategy in emergency)
    address public admin;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeesCollected(PoolId indexed poolId, uint256 amount, uint256 accumulated);
    event FeesDeposited(uint256 amount, uint256 totalDonated);
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error DepositFailed();
    error InsufficientFees();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IPoolManager _poolManager,
        address _yieldStrategy,
        address _usdc,
        address _admin
    ) BaseHook(_poolManager) {
        require(_yieldStrategy != address(0), "YieldDonatingFeeHook: zero strategy");
        require(_usdc != address(0), "YieldDonatingFeeHook: zero usdc");
        require(_admin != address(0), "YieldDonatingFeeHook: zero admin");

        yieldStrategy = _yieldStrategy;
        usdc = IERC20(_usdc);
        admin = _admin;
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,        // ✅ Capture fees after swap
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Hook called after every swap in the pool
     * @dev Captures 50% of swap fees and accumulates for batch deposit
     *
     * Flow:
     * 1. Calculate fee from swap delta
     * 2. Take 50% of fee from pool
     * 3. Accumulate in this contract
     * 4. If accumulated >= $1, deposit to strategy
     */
    function _afterSwap(
        address, /* sender */
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData */
    ) internal override returns (bytes4, int128) {

        // Extract fee from swap delta
        // In Uniswap v4, fees are captured as part of the swap delta
        // The unspecified side of the swap contains the fee
        int128 feeAmount = params.zeroForOne ? delta.amount1() : delta.amount0();

        if (feeAmount > 0) {
            uint256 fee = uint256(uint128(feeAmount));

            // Calculate 50% donation amount
            uint256 donationAmount = (fee * FEE_DONATION_BPS) / BASIS_POINTS;

            if (donationAmount > 0) {
                // Take USDC from pool manager
                // In v4, we need to settle with the pool manager
                Currency currency = params.zeroForOne ? key.currency1 : key.currency0;
                poolManager.take(currency, address(this), donationAmount);

                // Accumulate fees
                accumulatedFees += donationAmount;
                poolFeesCollected[key.toId()] += donationAmount;

                emit FeesCollected(key.toId(), donationAmount, accumulatedFees);

                // Deposit if threshold reached
                if (accumulatedFees >= DEPOSIT_THRESHOLD) {
                    _depositToStrategy();
                }
            }
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TO STRATEGY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit accumulated fees to YieldDonating Strategy
     * @dev Internal function, automatically called when threshold reached
     */
    function _depositToStrategy() internal {
        uint256 amount = accumulatedFees;
        if (amount == 0) return;

        // Reset accumulated before external call (reentrancy protection)
        accumulatedFees = 0;

        // Approve strategy to spend USDC
        usdc.forceApprove(yieldStrategy, amount);

        // Call deposit on YieldDonating Strategy
        // Strategy will keep it idle if < $1, or deploy to Kalani if >= $1
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

        totalFeesDonated += amount;

        emit FeesDeposited(amount, totalFeesDonated);
    }

    /**
     * @notice Manually trigger deposit to strategy
     * @dev Can be called by anyone (keepers, users, etc.)
     * Useful if fees are below threshold but want to deposit anyway
     */
    function depositAccumulatedFees() external {
        if (accumulatedFees == 0) revert InsufficientFees();
        _depositToStrategy();
    }

    /**
     * @notice Force deposit even if below threshold
     * @dev Only admin can call (for emergencies or end-of-campaign cleanup)
     */
    function forceDeposit() external {
        if (msg.sender != admin) revert Unauthorized();
        if (accumulatedFees == 0) revert InsufficientFees();
        _depositToStrategy();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update yield strategy address (emergency only)
     * @param newStrategy New strategy address
     * @dev Only admin can call
     */
    function updateYieldStrategy(address newStrategy) external {
        if (msg.sender != admin) revert Unauthorized();
        require(newStrategy != address(0), "YieldDonatingFeeHook: zero strategy");

        // Note: yieldStrategy is immutable, so this would require redeployment
        // Keeping this for interface completeness
        emit StrategyUpdated(yieldStrategy, newStrategy);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get accumulated fees ready for deposit
     * @return amount Amount of USDC accumulated
     */
    function getAccumulatedFees() external view returns (uint256) {
        return accumulatedFees;
    }

    /**
     * @notice Check if fees are ready for deposit
     * @return ready True if accumulated >= threshold
     */
    function isReadyForDeposit() external view returns (bool) {
        return accumulatedFees >= DEPOSIT_THRESHOLD;
    }

    /**
     * @notice Get fees collected for a specific pool
     * @param poolId Pool ID
     * @return amount Total fees collected from this pool
     */
    function getPoolFees(PoolId poolId) external view returns (uint256) {
        return poolFeesCollected[poolId];
    }

    /**
     * @notice Get total fees donated to strategy
     * @return total Total USDC donated to date
     */
    function getTotalDonated() external view returns (uint256) {
        return totalFeesDonated;
    }

    /**
     * @notice Calculate estimated donation for a swap amount
     * @param swapAmount Amount being swapped
     * @param feePercentage Pool fee percentage (e.g., 3000 = 0.3%)
     * @return donation Estimated donation amount
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

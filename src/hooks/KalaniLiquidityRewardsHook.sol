// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-core/src/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title KalaniLiquidityRewardsHook
 * @notice Uniswap v4 Hook that distributes Kalani vault yield to liquidity providers
 * @dev This hook demonstrates sustainable LP incentivization through public goods funding
 *
 * Key Features:
 * - Tracks LP positions via afterAddLiquidity/afterRemoveLiquidity
 * - Receives portion of Kalani yield for LP rewards
 * - Distributes rewards proportionally to LP shares
 * - LPs can claim accumulated rewards anytime
 * - Rewards compound over time if not claimed
 *
 * Public Goods Impact:
 * - Uses Kalani yield (generated from public goods donations) to incentivize liquidity
 * - Creates sustainable liquidity without requiring token emissions
 * - Aligns LP interests with public goods funding mechanism
 */
contract KalaniLiquidityRewardsHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice USDC token on Base (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
    IERC20 public immutable usdc;

    /// @notice Admin address (can deposit rewards)
    address public admin;

    /// @notice Rewards distributor (YieldDonating Strategy or management)
    address public rewardsDistributor;

    /// @notice Total liquidity shares tracked per pool
    mapping(PoolId => uint256) public totalShares;

    /// @notice LP shares per pool per user
    mapping(PoolId => mapping(address => uint256)) public lpShares;

    /// @notice Rewards per share (scaled by 1e18)
    mapping(PoolId => uint256) public rewardsPerShare;

    /// @notice User's reward debt (for calculating actual rewards)
    mapping(PoolId => mapping(address => uint256)) public rewardDebt;

    /// @notice Pending rewards per pool
    mapping(PoolId => uint256) public pendingRewards;

    /// @notice Total rewards distributed per pool
    mapping(PoolId => uint256) public totalRewardsDistributed;

    /// @notice Total rewards claimed by user per pool
    mapping(PoolId => mapping(address => uint256)) public userRewardsClaimed;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event LiquidityTracked(
        PoolId indexed poolId,
        address indexed provider,
        int256 liquidityDelta,
        uint256 shares
    );
    event RewardsDeposited(PoolId indexed poolId, uint256 amount);
    event RewardsClaimed(PoolId indexed poolId, address indexed user, uint256 amount);
    event RewardsDistributorUpdated(address indexed oldDistributor, address indexed newDistributor);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error NoRewardsToClaim();
    error TransferFailed();
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IPoolManager _poolManager,
        address _usdc,
        address _admin,
        address _rewardsDistributor
    ) BaseHook(_poolManager) {
        require(_usdc != address(0), "KalaniLiquidityRewardsHook: zero usdc");
        require(_admin != address(0), "KalaniLiquidityRewardsHook: zero admin");
        require(_rewardsDistributor != address(0), "KalaniLiquidityRewardsHook: zero distributor");

        usdc = IERC20(_usdc);
        admin = _admin;
        rewardsDistributor = _rewardsDistributor;
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,      // ✅ Track LP additions
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,   // ✅ Track LP removals
            beforeSwap: false,
            afterSwap: false,
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
     * @notice Hook called after liquidity is added to pool
     * @dev Tracks LP position and updates reward accounting
     *
     * Flow:
     * 1. Calculate liquidity delta from BalanceDelta
     * 2. Update user's shares
     * 3. Update total shares
     * 4. Update reward debt for accurate reward calculation
     */
    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, BalanceDelta) {
        require(msg.sender == address(poolManager), "KalaniLiquidityRewardsHook: only pool manager");

        PoolId poolId = key.toId();

        // Calculate liquidity amount from delta
        // In v4, delta represents token amounts added/removed
        // We'll use the absolute sum as a proxy for liquidity shares
        uint256 liquidityAmount = uint256(int256(delta.amount0() > 0 ? delta.amount0() : -delta.amount0())) +
                                 uint256(int256(delta.amount1() > 0 ? delta.amount1() : -delta.amount1()));

        if (liquidityAmount > 0) {
            // Update pending rewards before modifying shares
            _updateRewards(poolId, sender);

            // Update shares
            lpShares[poolId][sender] += liquidityAmount;
            totalShares[poolId] += liquidityAmount;

            // Update reward debt to prevent claiming rewards for liquidity added after distribution
            rewardDebt[poolId][sender] = (lpShares[poolId][sender] * rewardsPerShare[poolId]) / 1e18;

            emit LiquidityTracked(poolId, sender, int256(liquidityAmount), lpShares[poolId][sender]);
        }

        return (BaseHook.afterAddLiquidity.selector, delta);
    }

    /**
     * @notice Hook called after liquidity is removed from pool
     * @dev Updates LP position and pays out pending rewards
     *
     * Flow:
     * 1. Calculate liquidity delta
     * 2. Pay pending rewards to user
     * 3. Update user's shares
     * 4. Update total shares
     */
    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, BalanceDelta) {
        require(msg.sender == address(poolManager), "KalaniLiquidityRewardsHook: only pool manager");

        PoolId poolId = key.toId();

        // Calculate liquidity amount removed
        uint256 liquidityAmount = uint256(int256(delta.amount0() < 0 ? -delta.amount0() : delta.amount0())) +
                                 uint256(int256(delta.amount1() < 0 ? -delta.amount1() : delta.amount1()));

        if (liquidityAmount > 0) {
            // Update and claim pending rewards before removing shares
            _updateRewards(poolId, sender);
            uint256 pending = _pendingRewards(poolId, sender);
            if (pending > 0) {
                _claimRewards(poolId, sender, pending);
            }

            // Update shares
            if (liquidityAmount >= lpShares[poolId][sender]) {
                // Removing all liquidity
                totalShares[poolId] -= lpShares[poolId][sender];
                lpShares[poolId][sender] = 0;
            } else {
                lpShares[poolId][sender] -= liquidityAmount;
                totalShares[poolId] -= liquidityAmount;
            }

            // Update reward debt
            rewardDebt[poolId][sender] = (lpShares[poolId][sender] * rewardsPerShare[poolId]) / 1e18;

            emit LiquidityTracked(poolId, sender, -int256(liquidityAmount), lpShares[poolId][sender]);
        }

        return (BaseHook.afterRemoveLiquidity.selector, delta);
    }

    /*//////////////////////////////////////////////////////////////
                        REWARDS DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit rewards for a specific pool
     * @param poolId Pool to distribute rewards to
     * @param amount USDC amount to distribute
     * @dev Only rewards distributor can call
     */
    function depositRewards(PoolId poolId, uint256 amount) external {
        if (msg.sender != rewardsDistributor) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();

        // Transfer USDC from distributor
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Update rewards per share if there are LPs
        if (totalShares[poolId] > 0) {
            rewardsPerShare[poolId] += (amount * 1e18) / totalShares[poolId];
            pendingRewards[poolId] += amount;
            totalRewardsDistributed[poolId] += amount;

            emit RewardsDeposited(poolId, amount);
        } else {
            // No LPs yet, accumulate rewards
            pendingRewards[poolId] += amount;
        }
    }

    /**
     * @notice Claim accumulated rewards for a pool
     * @param poolId Pool to claim rewards from
     */
    function claimRewards(PoolId poolId) external {
        _updateRewards(poolId, msg.sender);
        uint256 pending = _pendingRewards(poolId, msg.sender);

        if (pending == 0) revert NoRewardsToClaim();

        _claimRewards(poolId, msg.sender, pending);
    }

    /**
     * @notice Claim rewards from multiple pools
     * @param poolIds Array of pool IDs to claim from
     */
    function claimMultiplePools(PoolId[] calldata poolIds) external {
        for (uint256 i = 0; i < poolIds.length; i++) {
            _updateRewards(poolIds[i], msg.sender);
            uint256 pending = _pendingRewards(poolIds[i], msg.sender);

            if (pending > 0) {
                _claimRewards(poolIds[i], msg.sender, pending);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update rewards for a user before share changes
     * @param poolId Pool ID
     * @param user User address
     */
    function _updateRewards(PoolId poolId, address user) internal {
        if (lpShares[poolId][user] > 0) {
            uint256 pending = _pendingRewards(poolId, user);
            if (pending > 0) {
                // Accumulate pending rewards in debt
                rewardDebt[poolId][user] += pending;
            }
        }
    }

    /**
     * @notice Calculate pending rewards for user
     * @param poolId Pool ID
     * @param user User address
     * @return pending Pending reward amount
     */
    function _pendingRewards(PoolId poolId, address user) internal view returns (uint256 pending) {
        uint256 userShares = lpShares[poolId][user];
        if (userShares == 0) return 0;

        uint256 accumulatedRewards = (userShares * rewardsPerShare[poolId]) / 1e18;
        pending = accumulatedRewards - rewardDebt[poolId][user];
    }

    /**
     * @notice Internal function to transfer rewards to user
     * @param poolId Pool ID
     * @param user User address
     * @param amount Reward amount
     */
    function _claimRewards(PoolId poolId, address user, uint256 amount) internal {
        // Update accounting
        rewardDebt[poolId][user] = (lpShares[poolId][user] * rewardsPerShare[poolId]) / 1e18;
        pendingRewards[poolId] -= amount;
        userRewardsClaimed[poolId][user] += amount;

        // Transfer USDC rewards
        usdc.safeTransfer(user, amount);

        emit RewardsClaimed(poolId, user, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update rewards distributor address
     * @param newDistributor New distributor address
     * @dev Only admin can call
     */
    function updateRewardsDistributor(address newDistributor) external {
        if (msg.sender != admin) revert Unauthorized();
        require(newDistributor != address(0), "KalaniLiquidityRewardsHook: zero distributor");

        emit RewardsDistributorUpdated(rewardsDistributor, newDistributor);
        rewardsDistributor = newDistributor;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get pending rewards for a user in a pool
     * @param poolId Pool ID
     * @param user User address
     * @return pending Pending reward amount
     */
    function getPendingRewards(PoolId poolId, address user) external view returns (uint256 pending) {
        return _pendingRewards(poolId, user);
    }

    /**
     * @notice Get LP shares for a user in a pool
     * @param poolId Pool ID
     * @param user User address
     * @return shares LP shares amount
     */
    function getLPShares(PoolId poolId, address user) external view returns (uint256 shares) {
        return lpShares[poolId][user];
    }

    /**
     * @notice Get total shares in a pool
     * @param poolId Pool ID
     * @return total Total shares
     */
    function getTotalShares(PoolId poolId) external view returns (uint256 total) {
        return totalShares[poolId];
    }

    /**
     * @notice Get pool statistics
     * @param poolId Pool ID
     * @return totalShares_ Total LP shares
     * @return pendingRewards_ Pending rewards to distribute
     * @return totalDistributed Total rewards distributed
     * @return rewardsPerShare_ Current rewards per share
     */
    function getPoolStats(PoolId poolId)
        external
        view
        returns (
            uint256 totalShares_,
            uint256 pendingRewards_,
            uint256 totalDistributed,
            uint256 rewardsPerShare_
        )
    {
        return (
            totalShares[poolId],
            pendingRewards[poolId],
            totalRewardsDistributed[poolId],
            rewardsPerShare[poolId]
        );
    }

    /**
     * @notice Get user statistics for a pool
     * @param poolId Pool ID
     * @param user User address
     * @return shares User's LP shares
     * @return pending Pending rewards
     * @return claimed Total rewards claimed
     */
    function getUserStats(PoolId poolId, address user)
        external
        view
        returns (
            uint256 shares,
            uint256 pending,
            uint256 claimed
        )
    {
        return (
            lpShares[poolId][user],
            _pendingRewards(poolId, user),
            userRewardsClaimed[poolId][user]
        );
    }

    /**
     * @notice Calculate user's share percentage in a pool
     * @param poolId Pool ID
     * @param user User address
     * @return percentage Share percentage (scaled by 1e18, e.g., 1e18 = 100%)
     */
    function getUserSharePercentage(PoolId poolId, address user) external view returns (uint256 percentage) {
        uint256 total = totalShares[poolId];
        if (total == 0) return 0;

        return (lpShares[poolId][user] * 1e18) / total;
    }
}

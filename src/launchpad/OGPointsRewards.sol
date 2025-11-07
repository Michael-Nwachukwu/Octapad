// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.3.0/contracts/utils/ReentrancyGuard.sol";
import {PaymentSplitter} from "@octant-core/core/PaymentSplitter.sol";

/**
 * @title OGPointsRewards
 * @notice Distributes 50% of Kalani yield to OG Points holders
 * @dev Implements reward distribution proportional to points balance using PaymentSplitter
 *
 * Key Features:
 * - Receives 50% of Kalani yield from YieldDonating Strategy via PaymentSplitter
 * - Distributes rewards proportionally to OG Points holders
 * - Snapshot-based reward calculation (rewards per point)
 * - Users can claim anytime
 * - Unclaimed rewards compound over time
 *
 * Reward Flow (PaymentSplitter Architecture):
 * 1. YieldDonating Strategy earns yield from Kalani
 * 2. On report(), 100% of profit shares minted to PaymentSplitter (donationAddress)
 * 3. PaymentSplitter holds shares: 50% for Dragon Router, 50% for OGPointsRewards
 * 4. This contract claims 50% shares from PaymentSplitter
 * 5. Redeems strategy shares for USDC
 * 6. Distributes USDC to OG Points holders
 * 7. Users claim proportional to their OG Points balance
 *
 * Fair Distribution:
 * - Rewards per point calculated at deposit time
 * - Users earn rewards from deposit onwards (no retroactive rewards)
 * - Prevents gaming through reward debt accounting
 * - Gas efficient batch claiming
 */
contract OGPointsRewards is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice OG Points token (non-transferable loyalty points)
    IERC20 public immutable ogPointsToken;

    /// @notice USDC token on Base (rewards currency)
    IERC20 public immutable usdc;

    /// @notice YieldDonating Strategy (ERC4626-like, issues strategy shares)
    address public immutable yieldStrategy;

    /// @notice PaymentSplitter that splits profits 50/50 (Dragon Router + OGPointsRewards)
    address payable public paymentSplitter;

    /// @notice Admin address (can deposit rewards)
    address public admin;

    /// @notice Rewards distributor (for manual deposits if needed)
    address public rewardsDistributor;

    /// @notice Accumulated rewards per point (scaled by 1e18)
    uint256 public rewardsPerPoint;

    /// @notice User's reward debt (for calculating actual rewards)
    mapping(address => uint256) public rewardDebt;

    /// @notice Total rewards deposited
    uint256 public totalRewardsDeposited;

    /// @notice Total rewards claimed
    uint256 public totalRewardsClaimed;

    /// @notice Rewards claimed per user
    mapping(address => uint256) public userRewardsClaimed;

    /// @notice Pending rewards not yet distributed (waiting for point holders)
    uint256 public pendingRewards;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RewardsDeposited(uint256 amount, uint256 rewardsPerPoint);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsDistributorUpdated(address indexed oldDistributor, address indexed newDistributor);
    event SharesClaimedFromSplitter(uint256 shares);
    event SharesRedeemed(uint256 shares, uint256 usdcReceived);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error NoRewardsToClaim();
    error InvalidAmount();
    error NoPointHolders();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _ogPointsToken,
        address _usdc,
        address _admin,
        address _rewardsDistributor,
        address _yieldStrategy,
        address _paymentSplitter
    ) {
        require(_ogPointsToken != address(0), "OGPointsRewards: zero points token");
        require(_usdc != address(0), "OGPointsRewards: zero usdc");
        require(_admin != address(0), "OGPointsRewards: zero admin");
        require(_yieldStrategy != address(0), "OGPointsRewards: zero strategy");
        require(_paymentSplitter != address(0), "OGPointsRewards: zero splitter");

        ogPointsToken = IERC20(_ogPointsToken);
        usdc = IERC20(_usdc);
        admin = _admin;
        rewardsDistributor = _rewardsDistributor; // Can be zero for PaymentSplitter-only mode
        yieldStrategy = _yieldStrategy;
        paymentSplitter = payable(_paymentSplitter);
    }

    /*//////////////////////////////////////////////////////////////
                        REWARDS DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit rewards for OG Points holders (manual/emergency use)
     * @param amount USDC amount to distribute
     * @dev Only rewards distributor can call
     *      For normal operation, use claimAndRedeemFromSplitter() instead
     *
     * Calculation:
     * - rewardsPerPoint += (amount * 1e18) / totalPoints
     * - This ensures fair distribution proportional to holdings
     */
    function depositRewards(uint256 amount) external nonReentrant {
        if (msg.sender != rewardsDistributor) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();

        // Transfer USDC from distributor
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Distribute to OG Points holders
        _distributeRewards(amount);
    }

    /**
     * @notice Claim accumulated rewards
     * @dev Updates reward debt and transfers USDC to caller
     */
    function claimRewards() external nonReentrant {
        _updateRewards(msg.sender);
        uint256 pending = _pendingRewards(msg.sender);

        if (pending == 0) revert NoRewardsToClaim();

        // Update accounting
        rewardDebt[msg.sender] = (ogPointsToken.balanceOf(msg.sender) * rewardsPerPoint) / 1e18;
        totalRewardsClaimed += pending;
        userRewardsClaimed[msg.sender] += pending;

        // Transfer USDC rewards
        usdc.safeTransfer(msg.sender, pending);

        emit RewardsClaimed(msg.sender, pending);
    }

    /**
     * @notice Distribute pending rewards that accumulated before point holders existed
     * @dev Can be called by anyone once there are point holders
     */
    function distributePendingRewards() external nonReentrant {
        if (pendingRewards == 0) return;

        uint256 totalPoints = ogPointsToken.totalSupply();
        if (totalPoints == 0) revert NoPointHolders();

        uint256 amount = pendingRewards;
        pendingRewards = 0;

        // Update rewards per point
        rewardsPerPoint += (amount * 1e18) / totalPoints;
        totalRewardsDeposited += amount;

        emit RewardsDeposited(amount, rewardsPerPoint);
    }

    /**
     * @notice Claim strategy shares from PaymentSplitter and redeem for USDC
     * @dev This is the main harvest function for the PaymentSplitter architecture
     *
     * Flow:
     * 1. Claim our 50% share of strategy tokens from PaymentSplitter
     * 2. Redeem strategy shares for USDC
     * 3. Distribute USDC to OG Points holders via existing reward system
     *
     * Can be called by anyone (keeper, admin, or community member)
     */
    function claimAndRedeemFromSplitter() external nonReentrant {
        // 1. Claim strategy shares from PaymentSplitter
        // Use typed call instead of low-level call for safety
        PaymentSplitter(paymentSplitter).release(
            IERC20(yieldStrategy),  // Strategy token (ERC20)
            address(this)           // This contract receives the shares
        );

        // 2. Get our share balance
        uint256 shares = IERC20(yieldStrategy).balanceOf(address(this));
        if (shares == 0) return; // Nothing to redeem

        emit SharesClaimedFromSplitter(shares);

        // 3. Redeem shares for USDC
        // Strategy.redeem(uint256 shares, address receiver, address owner) returns (uint256 assets)
        (bool successRedeem, bytes memory data) = yieldStrategy.call(
            abi.encodeWithSignature(
                "redeem(uint256,address,address)",
                shares,
                address(this),  // Receiver of USDC
                address(this)   // Owner of shares
            )
        );

        require(successRedeem, "OGPointsRewards: redeem failed");

        uint256 usdcReceived = abi.decode(data, (uint256));
        emit SharesRedeemed(shares, usdcReceived);

        // 4. Distribute USDC to OG Points holders
        if (usdcReceived > 0) {
            _distributeRewards(usdcReceived);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to distribute USDC rewards to OG Points holders
     * @param amount USDC amount to distribute
     * @dev Updates rewardsPerPoint and handles accounting
     */
    function _distributeRewards(uint256 amount) internal {
        uint256 totalPoints = ogPointsToken.totalSupply();

        if (totalPoints > 0) {
            // Update rewards per point
            rewardsPerPoint += (amount * 1e18) / totalPoints;
            totalRewardsDeposited += amount;

            emit RewardsDeposited(amount, rewardsPerPoint);
        } else {
            // No point holders yet, accumulate rewards
            pendingRewards += amount;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update rewards for a user before balance changes
     * @param user User address
     * @dev This should be called whenever user's points balance changes
     */
    function _updateRewards(address user) internal {
        uint256 userPoints = ogPointsToken.balanceOf(user);
        if (userPoints > 0) {
            uint256 pending = _pendingRewards(user);
            if (pending > 0) {
                // Accumulate pending rewards in debt
                rewardDebt[user] += pending;
            }
        }
    }

    /**
     * @notice Calculate pending rewards for user
     * @param user User address
     * @return pending Pending reward amount in USDC
     */
    function _pendingRewards(address user) internal view returns (uint256 pending) {
        uint256 userPoints = ogPointsToken.balanceOf(user);
        if (userPoints == 0) return 0;

        uint256 accumulatedRewards = (userPoints * rewardsPerPoint) / 1e18;
        pending = accumulatedRewards - rewardDebt[user];
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
        require(newDistributor != address(0), "OGPointsRewards: zero distributor");

        emit RewardsDistributorUpdated(rewardsDistributor, newDistributor);
        rewardsDistributor = newDistributor;
    }

    /**
     * @notice Update payment splitter address
     * @param newSplitter New payment splitter address
     * @dev Only admin can call
     */
    function updatePaymentSplitter(address payable newSplitter) external {
        if (msg.sender != admin) revert Unauthorized();
        require(newSplitter != address(0), "OGPointsRewards: zero splitter");

        paymentSplitter = newSplitter;
    }

    /**
     * @notice Transfer admin role
     * @param newAdmin New admin address
     * @dev Only admin can call
     */
    function transferAdmin(address newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        require(newAdmin != address(0), "OGPointsRewards: zero admin");

        admin = newAdmin;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get pending rewards for a user
     * @param user User address
     * @return pending Pending reward amount in USDC
     */
    function getPendingRewards(address user) external view returns (uint256 pending) {
        return _pendingRewards(user);
    }

    /**
     * @notice Get user statistics
     * @param user User address
     * @return points User's OG Points balance
     * @return pending Pending rewards
     * @return claimed Total rewards claimed
     */
    function getUserStats(address user)
        external
        view
        returns (
            uint256 points,
            uint256 pending,
            uint256 claimed
        )
    {
        return (
            ogPointsToken.balanceOf(user),
            _pendingRewards(user),
            userRewardsClaimed[user]
        );
    }

    /**
     * @notice Get global statistics
     * @return totalPoints Total OG Points supply
     * @return rewardsPerPoint_ Current rewards per point
     * @return totalDeposited Total rewards deposited
     * @return totalClaimed Total rewards claimed
     * @return pending Pending rewards awaiting distribution
     */
    function getGlobalStats()
        external
        view
        returns (
            uint256 totalPoints,
            uint256 rewardsPerPoint_,
            uint256 totalDeposited,
            uint256 totalClaimed,
            uint256 pending
        )
    {
        return (
            ogPointsToken.totalSupply(),
            rewardsPerPoint,
            totalRewardsDeposited,
            totalRewardsClaimed,
            pendingRewards
        );
    }

    /**
     * @notice Calculate user's share percentage of total rewards
     * @param user User address
     * @return percentage Share percentage (scaled by 1e18, e.g., 1e18 = 100%)
     */
    function getUserSharePercentage(address user) external view returns (uint256 percentage) {
        uint256 totalPoints = ogPointsToken.totalSupply();
        if (totalPoints == 0) return 0;

        return (ogPointsToken.balanceOf(user) * 1e18) / totalPoints;
    }

    /**
     * @notice Estimate rewards for a given points amount
     * @param pointsAmount Amount of OG Points
     * @return rewards Estimated USDC rewards
     */
    function estimateRewards(uint256 pointsAmount) external view returns (uint256 rewards) {
        if (rewardsPerPoint == 0) return 0;
        return (pointsAmount * rewardsPerPoint) / 1e18;
    }

    /**
     * @notice Get current APR for points holders (annualized estimate)
     * @param depositAmount Recent deposit amount
     * @param periodDays Period in days for the deposit
     * @return apr Estimated APR (scaled by 1e18, e.g., 0.05e18 = 5%)
     */
    function estimateAPR(uint256 depositAmount, uint256 periodDays)
        external
        view
        returns (uint256 apr)
    {
        uint256 totalPoints = ogPointsToken.totalSupply();
        if (totalPoints == 0 || periodDays == 0) return 0;

        // Assume 1 point = 1 USDC value for simplicity
        // APR = (rewards / principal) * (365 / days)
        uint256 yearlyRewards = (depositAmount * 365) / periodDays;
        apr = (yearlyRewards * 1e18) / totalPoints;
    }

    /**
     * @notice Get claimable strategy shares from PaymentSplitter
     * @return shares Amount of strategy shares claimable
     */
    function getClaimableShares() external view returns (uint256 shares) {
        // PaymentSplitter.releasable(IERC20 token, address account) returns (uint256)
        (bool success, bytes memory data) = paymentSplitter.staticcall(
            abi.encodeWithSignature(
                "releasable(address,address)",
                yieldStrategy,
                address(this)
            )
        );

        if (success) {
            shares = abi.decode(data, (uint256));
        }

        return shares;
    }

    /**
     * @notice Get held strategy shares (already claimed but not redeemed)
     * @return shares Amount of strategy shares held by this contract
     */
    function getHeldShares() external view returns (uint256 shares) {
        return IERC20(yieldStrategy).balanceOf(address(this));
    }
}

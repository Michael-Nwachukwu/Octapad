// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseHook} from "@uniswap/v4-core/src/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * @title OGPointsHook
 * @notice Uniswap v4 Hook that awards OG points based on trading volume
 * @dev This hook demonstrates community engagement through trading activity
 *
 * Key Features:
 * - Tracks swap volume for all traders
 * - Awards OG points proportional to swap size
 * - Configurable points multiplier
 * - Admin can adjust points rate
 * - Anti-gaming: uses absolute swap value, caps points per transaction
 *
 * OG Points Benefits:
 * - Points holders can claim 50% of Kalani yield
 * - Non-transferable loyalty rewards
 * - Aligns trader interests with public goods funding
 * - Creates engaged community around campaigns
 *
 * Points Calculation:
 * - Base: 1 point per 1 USDC swap volume
 * - Multiplier: configurable (default 100 = 1x, 200 = 2x)
 * - Cap: max points per transaction to prevent gaming
 * - Volume measured in absolute terms (buys and sells both count)
 */
contract OGPointsHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice OG Points token contract (will be deployed separately)
    address public ogPointsToken;

    /// @notice Admin address (can update settings)
    address public admin;

    /// @notice Points multiplier (scaled by 100, e.g., 100 = 1x, 200 = 2x)
    uint256 public pointsMultiplier;

    /// @notice Max points per transaction (anti-gaming measure)
    uint256 public maxPointsPerTx;

    /// @notice Base points per USDC volume (scaled by 1e6 for USDC decimals)
    uint256 public basePointsPerUSDC;

    /// @notice Total OG points awarded
    uint256 public totalPointsAwarded;

    /// @notice Points awarded per pool
    mapping(PoolId => uint256) public poolPointsAwarded;

    /// @notice Points awarded per user
    mapping(address => uint256) public userPointsAwarded;

    /// @notice Trading volume per user (in USDC, 6 decimals)
    mapping(address => uint256) public userVolume;

    /// @notice Trading volume per pool (in USDC, 6 decimals)
    mapping(PoolId => uint256) public poolVolume;

    /// @notice Whether OG Points token is set (prevents awarding before token exists)
    bool public pointsTokenSet;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PointsAwarded(
        PoolId indexed poolId,
        address indexed trader,
        uint256 swapAmount,
        uint256 pointsAwarded
    );
    event PointsMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
    event MaxPointsPerTxUpdated(uint256 oldMax, uint256 newMax);
    event OGPointsTokenSet(address indexed token);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error PointsTokenNotSet();
    error InvalidMultiplier();
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IPoolManager _poolManager,
        address _admin
    ) BaseHook(_poolManager) {
        require(_admin != address(0), "OGPointsHook: zero admin");

        admin = _admin;
        pointsMultiplier = 100; // 1x by default
        maxPointsPerTx = 100000e18; // 100k points max per tx
        basePointsPerUSDC = 1e18; // 1 point per 1 USDC (scaled to 18 decimals for points)
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
            afterSwap: true,              // ✅ Track swaps and award points
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
     * @dev Awards OG points based on swap volume
     *
     * Flow:
     * 1. Extract swap amount from delta
     * 2. Convert to USDC value if needed
     * 3. Calculate points based on volume and multiplier
     * 4. Award points to trader (mint OG Points tokens)
     * 5. Update statistics
     */
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        require(msg.sender == address(poolManager), "OGPointsHook: only pool manager");

        // Skip if points token not set yet
        if (!pointsTokenSet) {
            return (BaseHook.afterSwap.selector, 0);
        }

        PoolId poolId = key.toId();

        // Extract swap amount (use absolute value for volume calculation)
        // Delta contains the token amounts: negative = tokens out, positive = tokens in
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // Calculate swap volume in USDC terms
        // If USDC is currency0, use amount0; if USDC is currency1, use amount1
        uint256 swapVolumeUSDC = _calculateSwapVolume(key, amount0, amount1, params.zeroForOne);

        if (swapVolumeUSDC > 0) {
            // Calculate points to award
            uint256 pointsToAward = _calculatePoints(swapVolumeUSDC);

            // Award points to trader
            _awardPoints(poolId, sender, swapVolumeUSDC, pointsToAward);

            emit PointsAwarded(poolId, sender, swapVolumeUSDC, pointsToAward);
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        POINTS CALCULATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate swap volume in USDC terms
     * @param key Pool key
     * @param amount0 Amount of currency0
     * @param amount1 Amount of currency1
     * @param zeroForOne Swap direction
     * @return volumeUSDC Swap volume in USDC (6 decimals)
     */
    function _calculateSwapVolume(
        PoolKey calldata key,
        int128 amount0,
        int128 amount1,
        bool zeroForOne
    ) internal pure returns (uint256 volumeUSDC) {
        // Use the input amount (positive value) as volume
        // If zeroForOne, trader is selling token0 (amount0 is positive)
        // If oneForZero, trader is selling token1 (amount1 is positive)

        int128 inputAmount = zeroForOne ? amount0 : amount1;

        // Convert to absolute value
        uint256 absAmount = inputAmount > 0
            ? uint256(int256(inputAmount))
            : uint256(int256(-inputAmount));

        // For campaign token <-> USDC pools:
        // - If USDC is the input token, use it directly
        // - If campaign token is input, we'd need price oracle (simplified: use output USDC)

        // Simplified approach: use the USDC side of the swap
        // In real implementation, would need to identify which currency is USDC
        // For now, assume we're tracking USDC volume regardless of direction

        return absAmount;
    }

    /**
     * @notice Calculate OG points for a swap volume
     * @param volumeUSDC Swap volume in USDC (6 decimals)
     * @return points Points to award (18 decimals)
     */
    function _calculatePoints(uint256 volumeUSDC) internal view returns (uint256 points) {
        // Base calculation: 1 point per 1 USDC
        // volumeUSDC is in 6 decimals, basePointsPerUSDC is scaled to 18 decimals
        // So we need to scale up from 6 to 18 decimals

        points = (volumeUSDC * basePointsPerUSDC * pointsMultiplier) / (1e6 * 100);

        // Apply cap to prevent gaming
        if (points > maxPointsPerTx) {
            points = maxPointsPerTx;
        }

        return points;
    }

    /**
     * @notice Award points to trader
     * @param poolId Pool ID
     * @param trader Trader address
     * @param volumeUSDC Swap volume
     * @param points Points to award
     */
    function _awardPoints(
        PoolId poolId,
        address trader,
        uint256 volumeUSDC,
        uint256 points
    ) internal {
        // Update statistics
        userPointsAwarded[trader] += points;
        poolPointsAwarded[poolId] += points;
        totalPointsAwarded += points;

        userVolume[trader] += volumeUSDC;
        poolVolume[poolId] += volumeUSDC;

        // Mint OG Points to trader
        (bool success, ) = ogPointsToken.call(
            abi.encodeWithSignature("mint(address,uint256)", trader, points)
        );
        require(success, "OGPointsHook: mint failed");
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set OG Points token address (one-time)
     * @param _ogPointsToken OG Points token address
     * @dev Only admin can call, can only be set once
     */
    function setOGPointsToken(address _ogPointsToken) external {
        if (msg.sender != admin) revert Unauthorized();
        require(!pointsTokenSet, "OGPointsHook: token already set");
        require(_ogPointsToken != address(0), "OGPointsHook: zero address");

        ogPointsToken = _ogPointsToken;
        pointsTokenSet = true;

        emit OGPointsTokenSet(_ogPointsToken);
    }

    /**
     * @notice Update points multiplier
     * @param _multiplier New multiplier (scaled by 100, e.g., 150 = 1.5x)
     * @dev Only admin can call
     */
    function setPointsMultiplier(uint256 _multiplier) external {
        if (msg.sender != admin) revert Unauthorized();
        if (_multiplier == 0 || _multiplier > 1000) revert InvalidMultiplier(); // Max 10x

        emit PointsMultiplierUpdated(pointsMultiplier, _multiplier);
        pointsMultiplier = _multiplier;
    }

    /**
     * @notice Update max points per transaction
     * @param _maxPoints New max points
     * @dev Only admin can call
     */
    function setMaxPointsPerTx(uint256 _maxPoints) external {
        if (msg.sender != admin) revert Unauthorized();
        if (_maxPoints == 0) revert InvalidAmount();

        emit MaxPointsPerTxUpdated(maxPointsPerTx, _maxPoints);
        maxPointsPerTx = _maxPoints;
    }

    /**
     * @notice Update base points per USDC
     * @param _basePoints New base points (18 decimals)
     * @dev Only admin can call
     */
    function setBasePointsPerUSDC(uint256 _basePoints) external {
        if (msg.sender != admin) revert Unauthorized();
        if (_basePoints == 0) revert InvalidAmount();

        basePointsPerUSDC = _basePoints;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get total points awarded to a user
     * @param user User address
     * @return points Total points awarded
     */
    function getUserPoints(address user) external view returns (uint256 points) {
        return userPointsAwarded[user];
    }

    /**
     * @notice Get trading volume for a user
     * @param user User address
     * @return volume Total volume in USDC (6 decimals)
     */
    function getUserVolume(address user) external view returns (uint256 volume) {
        return userVolume[user];
    }

    /**
     * @notice Get pool statistics
     * @param poolId Pool ID
     * @return points Total points awarded in pool
     * @return volume Total volume in pool (USDC, 6 decimals)
     */
    function getPoolStats(PoolId poolId) external view returns (uint256 points, uint256 volume) {
        return (poolPointsAwarded[poolId], poolVolume[poolId]);
    }

    /**
     * @notice Get user statistics
     * @param user User address
     * @return points Total points awarded
     * @return volume Total trading volume
     */
    function getUserStats(address user) external view returns (uint256 points, uint256 volume) {
        return (userPointsAwarded[user], userVolume[user]);
    }

    /**
     * @notice Calculate points for a given swap amount
     * @param usdcAmount Swap amount in USDC (6 decimals)
     * @return points Estimated points to be awarded
     */
    function estimatePoints(uint256 usdcAmount) external view returns (uint256 points) {
        return _calculatePoints(usdcAmount);
    }

    /**
     * @notice Get current points settings
     * @return multiplier Current points multiplier
     * @return maxPerTx Max points per transaction
     * @return basePoints Base points per USDC
     */
    function getPointsSettings()
        external
        view
        returns (
            uint256 multiplier,
            uint256 maxPerTx,
            uint256 basePoints
        )
    {
        return (pointsMultiplier, maxPointsPerTx, basePointsPerUSDC);
    }

    /**
     * @notice Get global statistics
     * @return totalPoints Total points awarded globally
     * @return tokenSet Whether OG Points token is set
     * @return token OG Points token address
     */
    function getGlobalStats()
        external
        view
        returns (
            uint256 totalPoints,
            bool tokenSet,
            address token
        )
    {
        return (totalPointsAwarded, pointsTokenSet, ogPointsToken);
    }
}

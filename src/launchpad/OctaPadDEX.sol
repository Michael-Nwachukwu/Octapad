// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.3.0/contracts/utils/ReentrancyGuard.sol";

/**
 * @title OctaPadDEX
 * @notice Simple DEX interface for swapping between Campaign Tokens and USDC via Uniswap v4
 * @dev Routes all swaps through Uniswap v4 pools with YieldDonating hooks
 *
 * Key Features:
 * - Simple swap interface (buy/sell campaign tokens with USDC)
 * - Routes through Uniswap v4 with hooks enabled
 * - Supports slippage protection
 * - Gas efficient
 * - No custody (direct swaps through pool manager)
 *
 * Integration with Hooks:
 * - YieldDonatingFeeHook: Captures 50% of swap fees → YieldDonating Strategy
 * - OGPointsHook: Awards OG points based on swap volume
 * - KalaniLiquidityRewardsHook: N/A for swaps (LP rewards only)
 *
 * User Journey:
 * 1. User approves USDC/token to OctaPadDEX
 * 2. Calls buyTokens() or sellTokens()
 * 3. DEX routes swap through Uniswap v4 pool
 * 4. Hooks execute (fee capture, points award)
 * 5. User receives tokens/USDC
 */
contract OctaPadDEX is ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Uniswap v4 Pool Manager
    IPoolManager public immutable poolManager;

    /// @notice USDC token on Base
    IERC20 public immutable usdc;

    /// @notice Admin address
    address public admin;

    /// @notice Campaign token → Pool Key mapping
    mapping(address => PoolKey) public campaignPools;

    /// @notice Whether a campaign pool is registered
    mapping(address => bool) public isPoolRegistered;

    /// @notice Default slippage tolerance (basis points, e.g., 100 = 1%)
    uint16 public defaultSlippageBps;

    /// @notice Maximum slippage tolerance allowed (basis points)
    uint16 public constant MAX_SLIPPAGE_BPS = 1000; // 10%

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PoolRegistered(address indexed campaignToken, PoolId indexed poolId);
    event TokensPurchased(
        address indexed buyer,
        address indexed campaignToken,
        uint256 usdcIn,
        uint256 tokensOut
    );
    event TokensSold(
        address indexed seller,
        address indexed campaignToken,
        uint256 tokensIn,
        uint256 usdcOut
    );
    event DefaultSlippageUpdated(uint16 oldSlippage, uint16 newSlippage);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error PoolNotRegistered();
    error PoolAlreadyRegistered();
    error SlippageTooHigh();
    error InsufficientOutput();
    error InvalidAmount();
    error SwapFailed();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _poolManager,
        address _usdc,
        address _admin
    ) {
        require(_poolManager != address(0), "OctaPadDEX: zero pool manager");
        require(_usdc != address(0), "OctaPadDEX: zero usdc");
        require(_admin != address(0), "OctaPadDEX: zero admin");

        poolManager = IPoolManager(_poolManager);
        usdc = IERC20(_usdc);
        admin = _admin;
        defaultSlippageBps = 100; // 1% default slippage
    }

    /*//////////////////////////////////////////////////////////////
                            POOL REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a campaign token's Uniswap v4 pool
     * @param campaignToken Campaign token address
     * @param poolKey Pool key for the campaign token <-> USDC pool
     * @dev Only admin can call (typically OctaPad during funding completion)
     */
    function registerPool(address campaignToken, PoolKey memory poolKey) external {
        if (msg.sender != admin) revert Unauthorized();
        if (isPoolRegistered[campaignToken]) revert PoolAlreadyRegistered();

        campaignPools[campaignToken] = poolKey;
        isPoolRegistered[campaignToken] = true;

        emit PoolRegistered(campaignToken, poolKey.toId());
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Buy campaign tokens with USDC
     * @param campaignToken Campaign token to buy
     * @param usdcAmount USDC amount to spend
     * @param minTokensOut Minimum tokens to receive (slippage protection)
     * @return tokensOut Amount of tokens received
     *
     * Flow:
     * 1. Transfer USDC from user
     * 2. Approve pool manager
     * 3. Execute swap via Uniswap v4
     * 4. Hooks execute (fee capture, points award)
     * 5. Transfer tokens to user
     */
    function buyTokens(
        address campaignToken,
        uint256 usdcAmount,
        uint256 minTokensOut
    ) external nonReentrant returns (uint256 tokensOut) {
        if (!isPoolRegistered[campaignToken]) revert PoolNotRegistered();
        if (usdcAmount == 0) revert InvalidAmount();

        // Transfer USDC from user
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Get pool key
        PoolKey memory poolKey = campaignPools[campaignToken];

        // Determine swap direction (USDC for token)
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(usdc);

        // Execute swap through pool manager
        // Note: This is a simplified interface. Real implementation would use
        // Uniswap v4's swap router or implement proper pool manager interactions
        tokensOut = _executeSwap(poolKey, zeroForOne, usdcAmount, minTokensOut);

        // Transfer tokens to user
        IERC20(campaignToken).safeTransfer(msg.sender, tokensOut);

        emit TokensPurchased(msg.sender, campaignToken, usdcAmount, tokensOut);
    }

    /**
     * @notice Sell campaign tokens for USDC
     * @param campaignToken Campaign token to sell
     * @param tokenAmount Token amount to sell
     * @param minUsdcOut Minimum USDC to receive (slippage protection)
     * @return usdcOut Amount of USDC received
     *
     * Flow:
     * 1. Transfer tokens from user
     * 2. Execute swap via Uniswap v4
     * 3. Hooks execute (fee capture, points award)
     * 4. Transfer USDC to user
     */
    function sellTokens(
        address campaignToken,
        uint256 tokenAmount,
        uint256 minUsdcOut
    ) external nonReentrant returns (uint256 usdcOut) {
        if (!isPoolRegistered[campaignToken]) revert PoolNotRegistered();
        if (tokenAmount == 0) revert InvalidAmount();

        // Transfer tokens from user
        IERC20(campaignToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Get pool key
        PoolKey memory poolKey = campaignPools[campaignToken];

        // Determine swap direction (token for USDC)
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(campaignToken);

        // Execute swap through pool manager
        usdcOut = _executeSwap(poolKey, zeroForOne, tokenAmount, minUsdcOut);

        // Transfer USDC to user
        usdc.safeTransfer(msg.sender, usdcOut);

        emit TokensSold(msg.sender, campaignToken, tokenAmount, usdcOut);
    }

    /**
     * @notice Get quote for buying tokens with USDC
     * @param campaignToken Campaign token to buy
     * @param usdcAmount USDC amount to spend
     * @return tokensOut Estimated tokens to receive
     * @return minTokensOut Minimum tokens with default slippage
     */
    function getQuoteBuy(address campaignToken, uint256 usdcAmount)
        external
        view
        returns (uint256 tokensOut, uint256 minTokensOut)
    {
        if (!isPoolRegistered[campaignToken]) revert PoolNotRegistered();

        // Get quote from pool (simplified - real implementation would query pool state)
        tokensOut = _getQuote(campaignToken, usdcAmount, true);
        minTokensOut = (tokensOut * (10000 - defaultSlippageBps)) / 10000;
    }

    /**
     * @notice Get quote for selling tokens for USDC
     * @param campaignToken Campaign token to sell
     * @param tokenAmount Token amount to sell
     * @return usdcOut Estimated USDC to receive
     * @return minUsdcOut Minimum USDC with default slippage
     */
    function getQuoteSell(address campaignToken, uint256 tokenAmount)
        external
        view
        returns (uint256 usdcOut, uint256 minUsdcOut)
    {
        if (!isPoolRegistered[campaignToken]) revert PoolNotRegistered();

        // Get quote from pool
        usdcOut = _getQuote(campaignToken, tokenAmount, false);
        minUsdcOut = (usdcOut * (10000 - defaultSlippageBps)) / 10000;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute swap through Uniswap v4 pool manager
     * @param poolKey Pool key
     * @param zeroForOne Swap direction
     * @param amountIn Input amount
     * @param minAmountOut Minimum output amount
     * @return amountOut Output amount
     *
     * NOTE: This is a simplified placeholder. Real implementation would:
     * 1. Use PoolManager.swap() with proper parameters
     * 2. Handle callbacks for token transfers
     * 3. Settle balances with pool manager
     * 4. Properly encode swap parameters
     */
    function _executeSwap(
        PoolKey memory poolKey,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        // TODO: Implement actual Uniswap v4 swap logic
        // This requires:
        // 1. IPoolManager.swap() call
        // 2. Handling the swap callback
        // 3. Settling tokens with pool manager
        // 4. Extracting output amount from BalanceDelta

        // Placeholder logic for compilation
        // Real implementation would interact with pool manager
        revert("OctaPadDEX: swap not implemented");

        // Example structure (not functional):
        /*
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        });

        BalanceDelta delta = poolManager.swap(poolKey, params, "");

        amountOut = zeroForOne
            ? uint256(int256(-delta.amount1()))
            : uint256(int256(-delta.amount0()));

        if (amountOut < minAmountOut) revert InsufficientOutput();
        */
    }

    /**
     * @notice Get quote for a swap (simplified)
     * @param campaignToken Campaign token
     * @param amountIn Input amount
     * @param isBuy Whether buying (true) or selling (false)
     * @return amountOut Estimated output amount
     *
     * NOTE: Real implementation would query pool state and calculate
     * output based on current liquidity and price
     */
    function _getQuote(
        address campaignToken,
        uint256 amountIn,
        bool isBuy
    ) internal view returns (uint256 amountOut) {
        // TODO: Implement actual quote logic
        // This requires querying pool state and calculating swap output

        // Placeholder
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update default slippage tolerance
     * @param newSlippageBps New slippage in basis points
     * @dev Only admin can call
     */
    function setDefaultSlippage(uint16 newSlippageBps) external {
        if (msg.sender != admin) revert Unauthorized();
        if (newSlippageBps > MAX_SLIPPAGE_BPS) revert SlippageTooHigh();

        emit DefaultSlippageUpdated(defaultSlippageBps, newSlippageBps);
        defaultSlippageBps = newSlippageBps;
    }

    /**
     * @notice Transfer admin role
     * @param newAdmin New admin address
     * @dev Only admin can call
     */
    function transferAdmin(address newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        require(newAdmin != address(0), "OctaPadDEX: zero admin");

        admin = newAdmin;
    }

    /**
     * @notice Emergency withdraw tokens (safety mechanism)
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     * @dev Only admin can call
     */
    function emergencyWithdraw(address token, uint256 amount) external {
        if (msg.sender != admin) revert Unauthorized();

        IERC20(token).safeTransfer(admin, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get pool key for a campaign token
     * @param campaignToken Campaign token address
     * @return poolKey Pool key
     */
    function getPoolKey(address campaignToken) external view returns (PoolKey memory poolKey) {
        if (!isPoolRegistered[campaignToken]) revert PoolNotRegistered();
        return campaignPools[campaignToken];
    }

    /**
     * @notice Check if a campaign has a registered pool
     * @param campaignToken Campaign token address
     * @return registered Whether pool is registered
     */
    function isRegistered(address campaignToken) external view returns (bool registered) {
        return isPoolRegistered[campaignToken];
    }

    /**
     * @notice Get current slippage settings
     * @return defaultSlippage Default slippage in BPS
     * @return maxSlippage Maximum allowed slippage in BPS
     */
    function getSlippageSettings() external view returns (uint16 defaultSlippage, uint16 maxSlippage) {
        return (defaultSlippageBps, MAX_SLIPPAGE_BPS);
    }
}

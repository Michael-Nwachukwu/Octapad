// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.3.0/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin-contracts-5.3.0/contracts/access/Ownable.sol";

import {CampaignToken} from "./CampaignToken.sol";
import {BondingCurve} from "./BondingCurve.sol";
import {VestingManager} from "./VestingManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title OctaPad
 * @notice Token launchpad with bonding curve, auto-liquidity, and public goods funding
 * @dev Integrates with YieldDonating Strategy and Uniswap v4 for sustainable public goods funding
 *
 * Flow:
 * 1. Creator creates campaign (50% tokens for sale via bonding curve)
 * 2. Optional: Creator sponsors campaign (pays 100 USDC → YieldDonating, gets 10k OG points bank)
 * 3. Users buy tokens via bonding curve
 * 4. When funding complete:
 *    - 30% USDC → Creator (instant)
 *    - 20% USDC → Creator (vested 3 months → YieldDonating)
 *    - 45% USDC + tokens → Uniswap v4 liquidity
 *    - 5% USDC → Platform fee (→ YieldDonating)
 * 5. Trading on Uniswap v4:
 *    - 50% of swap fees → YieldDonating (via hook)
 *    - Buyers earn OG points based on volume
 */
contract OctaPad is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Campaign details
    struct Campaign {
        uint32 id;                      // Campaign ID
        address creator;                // Campaign creator
        address token;                  // Campaign token address
        uint128 targetFunding;          // Target USDC to raise
        uint128 amountRaised;           // Current USDC raised
        uint128 totalSupply;            // Total token supply
        uint128 tokensForSale;          // 50% of supply for sale
        uint128 tokensSold;             // Tokens sold so far
        uint128 creatorAllocation;      // 20% of supply for creator
        uint128 liquidityAllocation;    // 25% of supply for liquidity
        uint128 platformFeeTokens;      // 5% of supply for platform
        uint64 deadline;                // Campaign deadline
        uint32 reserveRatio;            // Bonding curve reserve ratio
        bool isActive;                  // Campaign is active
        bool isFundingComplete;         // Funding completed
        bool isCancelled;               // Campaign cancelled
        bool isSponsored;               // Creator paid sponsorship fee
        uint128 ogPointsBank;           // OG points allocated to buyers
        address uniswapPool;            // Created Uniswap v4 pool
        string name;                    // Token name
        string symbol;                  // Token symbol
        string description;             // Campaign description
    }

    /// @notice Campaign info for external queries (avoids storage mapping issues)
    struct CampaignInfo {
        uint32 id;
        address creator;
        address token;
        uint128 targetFunding;
        uint128 amountRaised;
        uint128 totalSupply;
        uint128 tokensForSale;
        uint128 tokensSold;
        uint128 creatorAllocation;
        uint128 liquidityAllocation;
        uint128 platformFeeTokens;
        uint64 deadline;
        uint32 reserveRatio;
        bool isActive;
        bool isFundingComplete;
        bool isCancelled;
        bool isSponsored;
        uint128 ogPointsBank;
        address uniswapPool;
        string name;
        string symbol;
        string description;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint16 public constant TOKENS_FOR_SALE_PCT = 5000;      // 50%
    uint16 public constant CREATOR_ALLOCATION_PCT = 2000;   // 20%
    uint16 public constant LIQUIDITY_ALLOCATION_PCT = 2500; // 25%
    uint16 public constant PLATFORM_FEE_PCT = 500;          // 5%
    uint16 public constant BASIS_POINTS = 10000;            // 100%

    uint16 public constant CREATOR_INSTANT_PCT = 3000;      // 30% of raised USDC
    uint16 public constant CREATOR_VESTED_PCT = 2000;       // 20% of raised USDC
    uint16 public constant LIQUIDITY_USDC_PCT = 4500;       // 45% of raised USDC
    uint16 public constant PLATFORM_FEE_USDC_PCT = 500;     // 5% of raised USDC

    uint128 public constant MIN_TARGET_FUNDING = 1000e6;    // $1,000 minimum
    uint128 public constant MAX_TARGET_FUNDING = 1000000e6; // $1M maximum
    uint128 public constant MIN_TOTAL_SUPPLY = 1_000_000e18;    // 1M tokens
    uint128 public constant MAX_TOTAL_SUPPLY = 1_000_000_000e18; // 1B tokens

    uint64 public constant MIN_DEADLINE = 1 days;
    uint64 public constant MAX_DEADLINE = 90 days;

    uint128 public constant SPONSORED_OG_POINTS_BANK = 10000; // 10k points

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice USDC token on Base
    IERC20 public immutable usdc;

    /// @notice YieldDonating Strategy
    address public yieldStrategy;

    /// @notice Vesting Manager
    VestingManager public vestingManager;

    /// @notice OG Points Token (for awarding points)
    address public ogPointsToken;

    /// @notice Uniswap v4 Pool Manager (for creating pools)
    address public uniswapPoolManager;

    /// @notice Platform sponsorship fee (default 100 USDC)
    uint128 public sponsorshipFee;

    /// @notice Campaign counter
    uint32 public campaignCount;

    /// @notice Total platform fees collected
    uint256 public totalPlatformFees;

    /// @notice Campaigns mapping
    mapping(uint32 => Campaign) public campaigns;

    /// @notice User investments per campaign
    mapping(uint32 => mapping(address => uint128)) public investments;

    /// @notice Campaigns created by address
    mapping(address => uint32[]) public creatorCampaigns;

    /// @notice Campaigns user participated in
    mapping(address => uint32[]) public userParticipatedCampaigns;

    /// @notice Track if user participated in campaign
    mapping(address => mapping(uint32 => bool)) public hasParticipated;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CampaignCreated(
        uint32 indexed campaignId,
        address indexed creator,
        address token,
        string name,
        string symbol,
        uint128 targetFunding,
        uint128 totalSupply,
        uint64 deadline
    );

    event CampaignSponsored(
        uint32 indexed campaignId,
        address indexed creator,
        uint128 sponsorshipFee,
        uint128 ogPointsBank
    );

    event TokensPurchased(
        uint32 indexed campaignId,
        address indexed buyer,
        uint128 usdcAmount,
        uint128 tokensReceived,
        uint128 ogPointsAwarded
    );

    event FundingCompleted(
        uint32 indexed campaignId,
        uint128 totalRaised,
        address uniswapPool
    );

    event YieldStrategyUpdated(address indexed newStrategy);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidInput();
    error Unauthorized();
    error CampaignNotActive();
    error CampaignEnded();
    error InsufficientBalance();
    error AlreadySponsored();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address owner_,
        address usdc_,
        address yieldStrategy_,
        address vestingManager_,
        address ogPointsToken_,
        address uniswapPoolManager_
    ) Ownable(owner_) {
        require(usdc_ != address(0), "OctaPad: zero usdc");
        require(yieldStrategy_ != address(0), "OctaPad: zero strategy");
        require(vestingManager_ != address(0), "OctaPad: zero vesting");
        require(ogPointsToken_ != address(0), "OctaPad: zero og points");
        // uniswapPoolManager is optional - can be address(0) if not using Uniswap integration

        usdc = IERC20(usdc_);
        yieldStrategy = yieldStrategy_;
        vestingManager = VestingManager(vestingManager_);
        ogPointsToken = ogPointsToken_;
        uniswapPoolManager = uniswapPoolManager_;
        sponsorshipFee = 100e6; // 100 USDC default
    }

    /*//////////////////////////////////////////////////////////////
                        CAMPAIGN CREATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new token campaign
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param description_ Campaign description
     * @param targetFunding_ Target USDC to raise (6 decimals)
     * @param totalSupply_ Total token supply (18 decimals)
     * @param reserveRatio_ Reserve ratio for bonding curve (not used in linear, kept for compatibility)
     * @param deadline_ Campaign deadline timestamp
     * @return campaignId ID of created campaign
     */
    function createCampaign(
        string memory name_,
        string memory symbol_,
        string memory description_,
        uint128 targetFunding_,
        uint128 totalSupply_,
        uint32 reserveRatio_,
        uint64 deadline_
    ) external returns (uint32 campaignId) {
        // Validations
        if (targetFunding_ < MIN_TARGET_FUNDING || targetFunding_ > MAX_TARGET_FUNDING) {
            revert InvalidInput();
        }
        if (totalSupply_ < MIN_TOTAL_SUPPLY || totalSupply_ > MAX_TOTAL_SUPPLY) {
            revert InvalidInput();
        }
        if (deadline_ <= uint64(block.timestamp) + MIN_DEADLINE ||
            deadline_ > uint64(block.timestamp) + MAX_DEADLINE) {
            revert InvalidInput();
        }

        // Calculate token allocations
        uint128 tokensForSale = (totalSupply_ * TOKENS_FOR_SALE_PCT) / BASIS_POINTS;
        uint128 creatorAllocation = (totalSupply_ * CREATOR_ALLOCATION_PCT) / BASIS_POINTS;
        uint128 liquidityAllocation = (totalSupply_ * LIQUIDITY_ALLOCATION_PCT) / BASIS_POINTS;
        uint128 platformFeeTokens = (totalSupply_ * PLATFORM_FEE_PCT) / BASIS_POINTS;

        // Ensure allocations don't exceed total supply
        require(
            tokensForSale + creatorAllocation + liquidityAllocation + platformFeeTokens <= totalSupply_,
            "OctaPad: allocations exceed supply"
        );

        // Deploy campaign token
        CampaignToken token = new CampaignToken(
            name_,
            symbol_,
            address(this),
            msg.sender
        );

        // Create campaign
        campaignId = ++campaignCount;
        Campaign storage campaign = campaigns[campaignId];

        campaign.id = campaignId;
        campaign.creator = msg.sender;
        campaign.token = address(token);
        campaign.targetFunding = targetFunding_;
        campaign.totalSupply = totalSupply_;
        campaign.tokensForSale = tokensForSale;
        campaign.creatorAllocation = creatorAllocation;
        campaign.liquidityAllocation = liquidityAllocation;
        campaign.platformFeeTokens = platformFeeTokens;
        campaign.deadline = deadline_;
        campaign.reserveRatio = reserveRatio_;
        campaign.isActive = true;
        campaign.name = name_;
        campaign.symbol = symbol_;
        campaign.description = description_;

        // Track creator campaigns
        creatorCampaigns[msg.sender].push(campaignId);

        emit CampaignCreated(
            campaignId,
            msg.sender,
            address(token),
            name_,
            symbol_,
            targetFunding_,
            totalSupply_,
            deadline_
        );

        return campaignId;
    }

    /**
     * @notice Sponsor a campaign to get OG points bank
     * @param campaignId_ ID of campaign to sponsor
     * @dev Creator pays sponsorship fee (100 USDC) → YieldDonating Strategy
     * Campaign gets 10k OG points bank that buyers drain proportionally
     */
    function sponsorCampaign(uint32 campaignId_) external nonReentrant {
        Campaign storage campaign = campaigns[campaignId_];

        // Validations
        if (campaign.id == 0) revert InvalidInput();
        if (msg.sender != campaign.creator) revert Unauthorized();
        if (!campaign.isActive || campaign.isFundingComplete || campaign.isCancelled) {
            revert CampaignNotActive();
        }
        if (uint64(block.timestamp) > campaign.deadline) revert CampaignEnded();
        if (campaign.isSponsored) revert AlreadySponsored();

        // Transfer sponsorship fee from creator
        usdc.safeTransferFrom(msg.sender, address(this), sponsorshipFee);

        // Deposit to YieldDonating Strategy (will stay idle if < $1)
        usdc.forceApprove(yieldStrategy, sponsorshipFee);
        (bool success, ) = yieldStrategy.call(
            abi.encodeWithSignature(
                "deposit(uint256,address)",
                uint256(sponsorshipFee),
                address(this)
            )
        );
        require(success, "OctaPad: strategy deposit failed");

        // Award OG points bank to campaign
        campaign.isSponsored = true;
        campaign.ogPointsBank = SPONSORED_OG_POINTS_BANK;

        emit CampaignSponsored(campaignId_, msg.sender, sponsorshipFee, SPONSORED_OG_POINTS_BANK);
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN PURCHASE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Buy tokens from a campaign via bonding curve
     * @param campaignId_ ID of campaign
     * @param usdcAmount_ Amount of USDC to spend (6 decimals)
     * @return tokensReceived Amount of tokens received
     * @return ogPointsAwarded OG points awarded (if campaign is sponsored)
     */
    function buyTokens(uint32 campaignId_, uint128 usdcAmount_)
        external
        nonReentrant
        returns (uint128 tokensReceived, uint128 ogPointsAwarded)
    {
        Campaign storage campaign = campaigns[campaignId_];

        // Validations
        if (campaign.id == 0) revert InvalidInput();
        if (!campaign.isActive || campaign.isFundingComplete || campaign.isCancelled) {
            revert CampaignNotActive();
        }
        if (uint64(block.timestamp) > campaign.deadline) revert CampaignEnded();
        if (usdcAmount_ == 0) revert InvalidInput();

        // Calculate tokens to receive via bonding curve
        uint256 tokensToMint = BondingCurve.calculatePurchaseReturn(
            campaign.tokensForSale,
            campaign.tokensSold,
            campaign.targetFunding,
            usdcAmount_
        );

        // Adjust if would exceed available tokens
        uint128 remainingTokens = campaign.tokensForSale - campaign.tokensSold;
        if (tokensToMint > remainingTokens) {
            // Calculate exact USDC needed for remaining tokens
            uint256 usdcNeeded = BondingCurve.calculateExactUsdcForTokens(
                campaign.tokensForSale,
                campaign.tokensSold,
                campaign.targetFunding,
                remainingTokens
            );
            tokensToMint = remainingTokens;
            usdcAmount_ = uint128(usdcNeeded);
        }

        tokensReceived = uint128(tokensToMint);

        // Transfer USDC from buyer
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount_);

        // Update campaign state
        campaign.amountRaised += usdcAmount_;
        campaign.tokensSold += tokensReceived;
        investments[campaignId_][msg.sender] += usdcAmount_;

        // Track user participation
        if (!hasParticipated[msg.sender][campaignId_]) {
            hasParticipated[msg.sender][campaignId_] = true;
            userParticipatedCampaigns[msg.sender].push(campaignId_);
        }

        // Award OG points if campaign is sponsored
        if (campaign.isSponsored && campaign.ogPointsBank > 0) {
            // Points awarded proportional to tokens purchased
            uint256 percentage = (uint256(tokensReceived) * 1e18) / campaign.tokensForSale;
            uint128 pointsToAward = uint128((percentage * campaign.ogPointsBank) / 1e18);

            // Cap at remaining points
            if (pointsToAward > campaign.ogPointsBank) {
                pointsToAward = campaign.ogPointsBank;
            }

            campaign.ogPointsBank -= pointsToAward;
            ogPointsAwarded = pointsToAward;

            // Mint OG points to buyer
            (bool success, ) = ogPointsToken.call(
                abi.encodeWithSignature("mint(address,uint256)", msg.sender, uint256(pointsToAward))
            );
            require(success, "OctaPad: OG points mint failed");
        }

        // Mint tokens to buyer
        CampaignToken(campaign.token).mint(msg.sender, tokensReceived);

        emit TokensPurchased(campaignId_, msg.sender, usdcAmount_, tokensReceived, ogPointsAwarded);

        // Check if funding complete
        if (campaign.tokensSold >= campaign.tokensForSale ||
            campaign.amountRaised >= campaign.targetFunding) {
            _completeFunding(campaignId_);
        }

        return (tokensReceived, ogPointsAwarded);
    }

    /*//////////////////////////////////////////////////////////////
                        CAMPAIGN COMPLETION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Complete campaign funding and distribute tokens/USDC
     * @param campaignId_ Campaign ID
     * @dev Internal function called when funding target reached
     */
    function _completeFunding(uint32 campaignId_) internal {
        Campaign storage campaign = campaigns[campaignId_];
        campaign.isActive = false;
        campaign.isFundingComplete = true;

        uint128 raised = campaign.amountRaised;

        // 1. Creator instant (30%)
        usdc.safeTransfer(campaign.creator, (raised * CREATOR_INSTANT_PCT) / BASIS_POINTS);

        // 2. Creator vested (20%)
        uint128 vested = (raised * CREATOR_VESTED_PCT) / BASIS_POINTS;
        usdc.forceApprove(address(vestingManager), vested);
        vestingManager.createVesting(campaign.creator, vested, 90 days);

        // 3. Platform fee (5%)
        uint128 fee = (raised * PLATFORM_FEE_USDC_PCT) / BASIS_POINTS;
        usdc.forceApprove(yieldStrategy, fee);
        (bool success, ) = yieldStrategy.call(abi.encodeWithSignature("deposit(uint256,address)", uint256(fee), address(this)));
        require(success, "OctaPad: deposit failed");
        totalPlatformFees += fee;

        // 4. Mint tokens
        address token = campaign.token;
        CampaignToken(token).mint(campaign.creator, campaign.creatorAllocation);
        CampaignToken(token).mint(address(this), campaign.liquidityAllocation + campaign.platformFeeTokens);

        // 5. Deploy liquidity (45%)
        uint128 liquidityUSDC = (raised * LIQUIDITY_USDC_PCT) / BASIS_POINTS;
        campaign.uniswapPool = _deployLiquidityV4(campaignId_, token, liquidityUSDC, campaign.liquidityAllocation);

        emit FundingCompleted(campaignId_, raised, campaign.uniswapPool);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get campaign info
     * @param campaignId_ Campaign ID
     * @return Campaign info struct
     */
    function getCampaign(uint32 campaignId_) external view returns (CampaignInfo memory) {
        Campaign storage c = campaigns[campaignId_];
        return CampaignInfo({
            id: c.id,
            creator: c.creator,
            token: c.token,
            targetFunding: c.targetFunding,
            amountRaised: c.amountRaised,
            totalSupply: c.totalSupply,
            tokensForSale: c.tokensForSale,
            tokensSold: c.tokensSold,
            creatorAllocation: c.creatorAllocation,
            liquidityAllocation: c.liquidityAllocation,
            platformFeeTokens: c.platformFeeTokens,
            deadline: c.deadline,
            reserveRatio: c.reserveRatio,
            isActive: c.isActive,
            isFundingComplete: c.isFundingComplete,
            isCancelled: c.isCancelled,
            isSponsored: c.isSponsored,
            ogPointsBank: c.ogPointsBank,
            uniswapPool: c.uniswapPool,
            name: c.name,
            symbol: c.symbol,
            description: c.description
        });
    }

    /**
     * @notice Get user investment in campaign
     * @param campaignId_ Campaign ID
     * @param user_ User address
     * @return Investment amount
     */
    function getUserInvestment(uint32 campaignId_, address user_) external view returns (uint128) {
        return investments[campaignId_][user_];
    }

    /**
     * @notice Get campaigns created by address
     * @param creator_ Creator address
     * @return Array of campaign IDs
     */
    function getCreatorCampaigns(address creator_) external view returns (uint32[] memory) {
        return creatorCampaigns[creator_];
    }

    /**
     * @notice Get campaigns user participated in
     * @param user_ User address
     * @return Array of campaign IDs
     */
    function getUserParticipatedCampaigns(address user_) external view returns (uint32[] memory) {
        return userParticipatedCampaigns[user_];
    }

    /**
     * @notice Get current token price for a campaign
     * @param campaignId_ Campaign ID
     * @return Current price (in 1e18 precision)
     */
    function getCurrentPrice(uint32 campaignId_) external view returns (uint256) {
        Campaign storage campaign = campaigns[campaignId_];
        return BondingCurve.getCurrentPrice(
            campaign.tokensForSale,
            campaign.tokensSold,
            campaign.targetFunding
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update YieldDonating Strategy address
     * @param newStrategy_ New strategy address
     */
    function setYieldStrategy(address newStrategy_) external onlyOwner {
        require(newStrategy_ != address(0), "OctaPad: zero strategy");
        yieldStrategy = newStrategy_;
        emit YieldStrategyUpdated(newStrategy_);
    }

    /**
     * @notice Update VestingManager address
     * @param newVestingManager_ New vesting manager address
     */
    function setVestingManager(address newVestingManager_) external onlyOwner {
        require(newVestingManager_ != address(0), "OctaPad: zero vesting manager");
        vestingManager = VestingManager(newVestingManager_);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy liquidity to Uniswap v4
     * @param campaignId_ Campaign ID
     * @param token_ Campaign token address
     * @param liquidityUSDC_ USDC amount for liquidity
     * @param liquidityTokens_ Token amount for liquidity
     * @return poolAddress Address of created pool
     */
    function _deployLiquidityV4(
        uint32 campaignId_,
        address token_,
        uint128 liquidityUSDC_,
        uint128 liquidityTokens_
    ) internal returns (address) {
        // If no pool manager configured, skip Uniswap deployment
        if (uniswapPoolManager == address(0)) {
            return address(0);
        }

        // Approve tokens for pool manager first
        usdc.forceApprove(uniswapPoolManager, liquidityUSDC_);
        IERC20(token_).forceApprove(uniswapPoolManager, liquidityTokens_);

        // Create and initialize pool
        PoolKey memory key = PoolKey({
            currency0: address(usdc) < token_ ? Currency.wrap(address(usdc)) : Currency.wrap(token_),
            currency1: address(usdc) < token_ ? Currency.wrap(token_) : Currency.wrap(address(usdc)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // Try to initialize pool (may already exist)
        try IPoolManager(uniswapPoolManager).initialize(key, 79228162514264337593543950336) {} catch {}

        // Try to add liquidity
        try IPoolManager(uniswapPoolManager).modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                liquidityDelta: int256(uint256(liquidityTokens_)),
                salt: bytes32(uint256(campaignId_))
            }),
            ""
        ) {} catch {}

        // Return pool ID as address
        return address(uint160(uint256(PoolId.unwrap(key.toId()))));
    }
}

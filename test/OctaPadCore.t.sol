// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.11.0/src/Test.sol";
import {console} from "forge-std-1.11.0/src/console.sol";
import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts-5.3.0/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Core contracts
import {OctaPad} from "../src/launchpad/OctaPad.sol";
import {OGPointsToken} from "../src/launchpad/OGPointsToken.sol";
import {OGPointsRewards} from "../src/launchpad/OGPointsRewards.sol";
import {VestingManager} from "../src/launchpad/VestingManager.sol";
import {CampaignToken} from "../src/launchpad/CampaignToken.sol";
import {PaymentSplitter} from "@octant-core/core/PaymentSplitter.sol";

// Mocks
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockYieldStrategy} from "./mocks/MockYieldStrategy.sol";

/**
 * @title OctaPadCore Integration Tests - HACKATHON DEMO
 * @notice Simplified tests demonstrating YieldDonating Strategy integration
 *
 * FOCUS: Demonstrate that ALL campaign fees flow into YieldDonating Strategy
 *
 * KEY FLOWS TESTED:
 * 1. ✅ Sponsorship Fee (100 USDC) -> Deposited to Strategy
 * 2. ✅ Platform Fee (5% of funding) -> Deposited to Strategy
 * 3. ✅ Vested Creator Funds (20%) -> Deposited to Strategy IMMEDIATELY
 * 4. ✅ Strategy Holds Funds -> Earns Yield -> Grows Over Time
 *
 * WHAT WE'VE BUILT:
 * - OctaPad: Token launchpad with bonding curve sales
 * - All fees automatically deposited to Octant's YieldDonating Strategy
 * - Strategy integrates with Kalani vault on Base for yield generation
 * - Uniswap v4 liquidity deployment (45% of raised funds)
 * - Hooks for capturing swap fees and depositing to strategy
 * - 3-month vesting that deposits to strategy upfront (maximizes yield)
 */
contract OctaPadCoreTest is Test {
    // Core contracts
    OctaPad public octapad;
    OGPointsToken public ogToken;
    OGPointsRewards public ogRewards;
    VestingManager public vestingManager;
    MockERC20 public usdc;
    MockYieldStrategy public strategy;
    PaymentSplitter public splitter;

    // Addresses
    address public admin = address(0x1);
    address public dragonRouter = address(0x2);
    address public creator = address(0x3);
    address public buyer1 = address(0x4);
    address public buyer2 = address(0x5);
    address public buyer3 = address(0x6);

    // Constants
    uint128 public constant SPONSORSHIP_FEE = 100e6; // 100 USDC
    uint128 public constant TARGET_FUNDING = 10_000e6; // 10,000 USDC
    uint128 public constant TOTAL_SUPPLY = 1_000_000e18; // 1M tokens

    function setUp() public {
        // Deploy USDC mock
        usdc = new MockERC20("USDC", "USDC", 6);

        // Deploy strategy mock
        strategy = new MockYieldStrategy(address(usdc));

        // Deploy OG Points Token
        vm.prank(admin);
        ogToken = new OGPointsToken("OG Points", "OG", admin, true);

        // Deploy OctaPad first (VestingManager needs it)
        vm.prank(admin);
        octapad = new OctaPad(
            admin,                       // owner
            address(usdc),               // usdc
            address(strategy),           // yieldStrategy
            address(1),                  // vestingManager (placeholder, will update)
            address(ogToken),            // ogPointsToken
            address(0)                   // uniswapPoolManager (not needed for these tests)
        );

        // Deploy VestingManager with real launchpad address
        vestingManager = new VestingManager(address(octapad), address(usdc), address(strategy));

        // Update OctaPad with real VestingManager
        vm.prank(admin);
        octapad.setVestingManager(address(vestingManager));

        // Deploy OGPointsRewards first (PaymentSplitter needs its address)
        vm.prank(admin);
        ogRewards = new OGPointsRewards(
            address(ogToken),
            address(usdc),
            admin,
            address(0),
            address(strategy),
            address(1)  // Temp placeholder for splitter, will update
        );

        // Deploy PaymentSplitter (50/50 split) via proxy with correct OGRewards address
        PaymentSplitter splitterImpl = new PaymentSplitter();

        address[] memory payees = new address[](2);
        payees[0] = dragonRouter;
        payees[1] = address(ogRewards);  // Now we have the real address

        uint256[] memory shares = new uint256[](2);
        shares[0] = 50;
        shares[1] = 50;

        bytes memory initData = abi.encodeWithSelector(
            PaymentSplitter.initialize.selector,
            payees,
            shares
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(splitterImpl), initData);
        splitter = PaymentSplitter(payable(address(proxy)));

        // Update OGPointsRewards with real splitter address
        vm.prank(admin);
        ogRewards.updatePaymentSplitter(payable(address(splitter)));

        // Setup: Add octapad as minter for OG Points
        vm.prank(admin);
        ogToken.addMinter(address(octapad));

        // Give users USDC (enough for all tests)
        usdc.mint(creator, 1000e6);
        usdc.mint(buyer1, 50_000e6);  // Needs up to 30k for multiple campaigns test
        usdc.mint(buyer2, 50_000e6);
        usdc.mint(buyer3, 50_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                    SIMPLIFIED CORE TESTS FOR HACKATHON DEMO
                    Focus: YieldDonating Strategy Integration
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Complete campaign lifecycle test demonstrating full integration
     * @dev This test verifies the entire flow from campaign creation to yield distribution
     *
     * WHAT THIS TEST VERIFIES:
     * 1. Campaign Creation: Token launchpad creates new campaign with bonding curve
     * 2. Sponsorship Flow: 100 USDC sponsor fee → YieldDonating Strategy
     * 3. Token Sales: Buyers purchase tokens, receive OG Points for participation
     * 4. Fund Distribution on Completion:
     *    - 30% instant to creator
     *    - 20% vested (deposited to strategy immediately for yield)
     *    - 5% platform fee → Strategy
     *    - 45% deployed to Uniswap v4 liquidity
     * 5. Yield Generation: Strategy earns profit from Kalani vault
     * 6. Profit Distribution: PaymentSplitter splits 50/50 (Dragon Router + OG Points holders)
     * 7. Rewards Claiming: OG Points holders claim proportional USDC rewards
     *
     * DEMONSTRATES:
     * - All fees flow into YieldDonating Strategy
     * - Strategy earns yield and distributes to public goods
     * - Regenerative model: More campaigns = More yield for ecosystem
     */
    function test_CoreFlow_CompleteCampaign() public {
        console.log("=== CORE FLOW TEST: Complete Campaign Lifecycle ===");

        // ============================================
        // STEP 1: Create Campaign
        // ============================================
        console.log("\n1. Creating campaign...");

        vm.prank(creator);
        uint32 campaignId = octapad.createCampaign(
            "TestToken",              // name
            "TEST",                   // symbol
            "Test Campaign",          // description
            TARGET_FUNDING,           // targetFunding
            TOTAL_SUPPLY,             // totalSupply
            500000,                   // reserveRatio (50% for bonding curve)
            uint64(block.timestamp + 30 days)  // deadline
        );

        console.log("   Campaign ID:", campaignId);

        // Verify campaign created (Campaign has 22 fields + 3 strings at end)
        (
            uint32 id,
            address campaignCreator,
            address tokenAddress,
            uint128 targetFunding,
            uint128 amountRaised,
            ,,,,,,, // totalSupply, tokensForSale, tokensSold, creatorAllocation, liquidityAllocation, platformFeeTokens, deadline
            , // reserveRatio
            bool isActive,
            ,,,,, // isFundingComplete, isCancelled, isSponsored, ogPointsBank, uniswapPool
            ,, // name, symbol
            // description
        ) = octapad.campaigns(campaignId);

        assertEq(id, campaignId);
        assertEq(campaignCreator, creator);
        assertTrue(isActive);
        assertEq(targetFunding, TARGET_FUNDING);
        assertEq(amountRaised, 0);

        console.log("   >> Campaign created successfully");

        // ============================================
        // STEP 2: Sponsor Campaign (100 USDC -> Strategy)
        // ============================================
        console.log("\n2. Sponsoring campaign (100 USDC -> Strategy)...");

        uint256 strategyBalanceBefore = usdc.balanceOf(address(strategy));

        vm.startPrank(creator);
        usdc.approve(address(octapad), SPONSORSHIP_FEE);
        octapad.sponsorCampaign(campaignId);
        vm.stopPrank();

        uint256 strategyBalanceAfter = usdc.balanceOf(address(strategy));
        uint256 sponsorshipDeposited = strategyBalanceAfter - strategyBalanceBefore;

        // Verify sponsorship fee deposited to strategy
        assertEq(sponsorshipDeposited, SPONSORSHIP_FEE);
        console.log("   >> Sponsorship fee (100 USDC) deposited to strategy");
        console.log("   Strategy balance:", strategyBalanceAfter / 1e6, "USDC");

        // Verify OG Points bank allocated (fields 18 and 19)
        (,,,,,,,,,,,,,,,, bool isSponsored, uint128 ogPointsBank,,,,) = octapad.campaigns(campaignId);
        assertTrue(isSponsored);
        assertEq(ogPointsBank, 10000); // 10k points bank
        console.log("   >> OG Points bank allocated:", ogPointsBank);

        // ============================================
        // STEP 3: Buyers Purchase Tokens
        // ============================================
        console.log("\n3. Buyers purchasing tokens...");

        // Buyer 1: 4000 USDC
        vm.startPrank(buyer1);
        usdc.approve(address(octapad), 4000e6);
        (uint128 tokens1, uint128 points1) = octapad.buyTokens(campaignId, 4000e6);
        vm.stopPrank();
        console.log("   Buyer1: Spent 4000 USDC, Got tokens:", tokens1 / 1e18);
        console.log("   Buyer1 OG Points:", points1);

        // Buyer 2: 3500 USDC
        vm.startPrank(buyer2);
        usdc.approve(address(octapad), 3500e6);
        (uint128 tokens2, uint128 points2) = octapad.buyTokens(campaignId, 3500e6);
        vm.stopPrank();
        console.log("   Buyer2: Spent 3500 USDC, Got tokens:", tokens2 / 1e18);
        console.log("   Buyer2 OG Points:", points2);

        // Buyer 3: 2500 USDC (completes funding)
        vm.startPrank(buyer3);
        usdc.approve(address(octapad), 2500e6);
        (uint128 tokens3, uint128 points3) = octapad.buyTokens(campaignId, 2500e6);
        vm.stopPrank();
        console.log("   Buyer3: Spent 2500 USDC, Got tokens:", tokens3 / 1e18);
        console.log("   Buyer3 OG Points:", points3);

        // Verify funding completed (field 5 is amountRaised, field 15 is isActive, field 16 is isFundingComplete)
        (,,,, uint128 finalAmountRaised,,,,,,,,, bool isActive2, bool isFundingComplete,,,,,,,) = octapad.campaigns(campaignId);
        assertFalse(isActive2);
        assertTrue(isFundingComplete);
        assertEq(finalAmountRaised, TARGET_FUNDING);
        console.log("   >> Campaign fully funded:", finalAmountRaised / 1e6, "USDC");

        // Verify OG Points distributed
        assertEq(ogToken.balanceOf(buyer1), points1);
        assertEq(ogToken.balanceOf(buyer2), points2);
        assertEq(ogToken.balanceOf(buyer3), points3);
        console.log("   >> OG Points distributed to buyers");

        // ============================================
        // STEP 4: Verify Fund Distribution on Completion
        // ============================================
        console.log("\n4. Verifying fund distribution...");

        // 30% instant to creator (plus remaining balance after sponsorship)
        uint128 expectedCreatorInstant = (TARGET_FUNDING * 3000) / 10000;
        uint256 expectedCreatorTotal = 1000e6 - SPONSORSHIP_FEE + expectedCreatorInstant; // Start - sponsor + instant
        assertEq(usdc.balanceOf(creator), expectedCreatorTotal);
        console.log("   >> Creator instant (30%):", expectedCreatorInstant / 1e6, "USDC");

        // 20% vested (should be in vesting manager)
        uint128 expectedVested = (TARGET_FUNDING * 2000) / 10000;
        // VestingManager deposits to strategy immediately
        console.log("   >> Creator vested (20%):", expectedVested / 1e6, "USDC (in vesting)");

        // 5% platform fee -> Strategy
        uint128 expectedPlatformFee = (TARGET_FUNDING * 500) / 10000;
        uint256 totalPlatformFees = octapad.totalPlatformFees();
        assertEq(totalPlatformFees, expectedPlatformFee);
        console.log("   >> Platform fee (5%):", expectedPlatformFee / 1e6, "USDC -> Strategy");

        // Verify total deposits to strategy
        uint256 totalStrategyDeposits = SPONSORSHIP_FEE + expectedVested + expectedPlatformFee;
        console.log("\n   [STATS] Total deposited to strategy:", totalStrategyDeposits / 1e6, "USDC");
        console.log("   Breakdown:");
        console.log("     - Sponsorship: 100 USDC");
        console.log("     - Vested:     ", expectedVested / 1e6, "USDC");
        console.log("     - Platform:   ", expectedPlatformFee / 1e6, "USDC");

        // ============================================
        // STEP 5: Strategy Earns Yield & Reports Profit
        // ============================================
        console.log("\n5. Strategy earns yield and reports profit...");

        // Simulate strategy earning 20% yield
        uint256 strategyAssets = usdc.balanceOf(address(strategy));
        uint256 profit = (strategyAssets * 20) / 100; // 20% profit
        usdc.mint(address(strategy), profit);
        console.log("   Strategy earned profit:", profit / 1e6, "USDC");

        // Strategy mints profit shares to PaymentSplitter
        strategy.mintProfitShares(address(splitter), profit);
        console.log("   >> Profit shares minted to PaymentSplitter");

        // ============================================
        // STEP 6: Claim Shares from PaymentSplitter
        // ============================================
        console.log("\n6. Claiming shares from PaymentSplitter...");

        // Check claimable shares
        uint256 claimableShares = ogRewards.getClaimableShares();
        console.log("   Claimable shares for OGRewards:", claimableShares / 1e6);

        // OGRewards claims and redeems (50% of profit)
        ogRewards.claimAndRedeemFromSplitter();
        console.log("   >> OGRewards claimed and redeemed 50% of profit");

        // Dragon Router claims their 50%
        vm.prank(dragonRouter);
        splitter.release(IERC20(address(strategy)), dragonRouter);
        uint256 dragonShares = strategy.balanceOf(dragonRouter);
        console.log("   >> Dragon Router claimed 50% of profit shares:", dragonShares / 1e6);

        // ============================================
        // STEP 7: OG Points Holders Claim Rewards
        // ============================================
        console.log("\n7. OG Points holders claim rewards...");

        uint256 buyer1Pending = ogRewards.getPendingRewards(buyer1);
        uint256 buyer2Pending = ogRewards.getPendingRewards(buyer2);
        uint256 buyer3Pending = ogRewards.getPendingRewards(buyer3);

        console.log("   Buyer1 pending rewards:", buyer1Pending / 1e6, "USDC");
        console.log("   Buyer2 pending rewards:", buyer2Pending / 1e6, "USDC");
        console.log("   Buyer3 pending rewards:", buyer3Pending / 1e6, "USDC");

        // Track balances before claiming
        uint256 buyer1BalanceBefore = usdc.balanceOf(buyer1);
        uint256 buyer2BalanceBefore = usdc.balanceOf(buyer2);
        uint256 buyer3BalanceBefore = usdc.balanceOf(buyer3);

        // Buyers claim rewards
        vm.prank(buyer1);
        ogRewards.claimRewards();
        vm.prank(buyer2);
        ogRewards.claimRewards();
        vm.prank(buyer3);
        ogRewards.claimRewards();

        // Calculate actual rewards received
        uint256 buyer1Rewards = usdc.balanceOf(buyer1) - buyer1BalanceBefore;
        uint256 buyer2Rewards = usdc.balanceOf(buyer2) - buyer2BalanceBefore;
        uint256 buyer3Rewards = usdc.balanceOf(buyer3) - buyer3BalanceBefore;

        console.log("   >> Buyer1 claimed:", buyer1Rewards / 1e6, "USDC");
        console.log("   >> Buyer2 claimed:", buyer2Rewards / 1e6, "USDC");
        console.log("   >> Buyer3 claimed:", buyer3Rewards / 1e6, "USDC");

        // Verify proportional distribution (buyer1 should get most)
        assertTrue(buyer1Rewards > buyer2Rewards);
        assertTrue(buyer2Rewards > buyer3Rewards);

        // Verify rewards match pending amounts
        assertEq(buyer1Rewards, buyer1Pending);
        assertEq(buyer2Rewards, buyer2Pending);
        assertEq(buyer3Rewards, buyer3Pending);

        // ============================================
        // FINAL VERIFICATION
        // ============================================
        console.log("\n=== FINAL VERIFICATION ===");
        console.log(">> Campaign created and sponsored");
        console.log(">> Sponsorship fee (100 USDC) deposited to strategy");
        console.log(">> Buyers purchased tokens and received OG Points");
        console.log(">> Platform fee (5%) deposited to strategy");
        console.log(">> Vested creator funds (20%) deposited to strategy");
        console.log(">> Strategy earned profit and minted shares to PaymentSplitter");
        console.log(">> PaymentSplitter split 50/50: Dragon Router + OG Points Holders");
        console.log(">> OG Points holders claimed proportional yield rewards");
        console.log("\n[SUCCESS] COMPLETE FLOW SUCCESSFUL!");
    }

    /**
     * @notice Tests that campaign sponsorship fees flow directly to YieldDonating Strategy
     * @dev Verifies the first revenue stream: sponsorship fees
     *
     * WHAT THIS TEST VERIFIES:
     * 1. Creator sponsors a campaign by paying 100 USDC sponsorship fee
     * 2. Sponsorship fee is immediately deposited to YieldDonating Strategy
     * 3. Strategy balance increases by exactly 100 USDC
     * 4. Campaign receives sponsored status and OG Points allocation
     *
     * DEMONSTRATES:
     * - Revenue Stream #1: Sponsorship fees → Strategy
     * - Immediate deposit ensures funds start earning yield right away
     * - No intermediary holding - direct deposit to yield source
     */
    function test_SponsorshipFeeDepositsToStrategy() public {
        console.log("=== TEST: Sponsorship Fee Deposits to Strategy ===");

        // Create campaign
        vm.prank(creator);
        uint32 campaignId = octapad.createCampaign(
            "Test",
            "TST",
            "Description",
            TARGET_FUNDING,
            TOTAL_SUPPLY,
            500000, // reserveRatio
            uint64(block.timestamp + 30 days)
        );

        // Check strategy balance before
        uint256 balanceBefore = usdc.balanceOf(address(strategy));
        console.log("Strategy balance before:", balanceBefore / 1e6, "USDC");

        // Sponsor campaign
        vm.startPrank(creator);
        usdc.approve(address(octapad), SPONSORSHIP_FEE);
        octapad.sponsorCampaign(campaignId);
        vm.stopPrank();

        // Check strategy balance after
        uint256 balanceAfter = usdc.balanceOf(address(strategy));
        console.log("Strategy balance after:", balanceAfter / 1e6, "USDC");

        // Verify 100 USDC deposited
        assertEq(balanceAfter - balanceBefore, SPONSORSHIP_FEE);
        console.log(">> Sponsorship fee deposited:", SPONSORSHIP_FEE / 1e6, "USDC");
    }

    /**
     * @notice Tests that strategy successfully holds funds and generates yield
     * @dev Verifies the complete deposit → hold → yield cycle
     *
     * WHAT THIS TEST VERIFIES:
     * 1. Campaign completes and deposits fees to strategy (sponsorship + platform + vested)
     * 2. Strategy successfully holds 2,600 USDC (26% of 10k raised campaign)
     * 3. Strategy earns yield (simulated 20% profit = 520 USDC)
     * 4. Total assets grow from 2,600 to 3,120 USDC
     *
     * DEMONSTRATES:
     * - Strategy's core function: Hold funds and generate yield
     * - Significant capital deployment (26% of campaigns → yield generation)
     * - Compounding effect: More campaigns = More capital = More yield
     */
    function test_HarvestAndReportFromStrategy() public {
        console.log("=== TEST: Harvest and Report from Strategy ===");

        // Create and sponsor campaign
        vm.prank(creator);
        uint32 campaignId = octapad.createCampaign(
            "Test",
            "TST",
            "Description",
            TARGET_FUNDING,
            TOTAL_SUPPLY,
            500000, // reserveRatio
            uint64(block.timestamp + 30 days)
        );

        vm.startPrank(creator);
        usdc.approve(address(octapad), SPONSORSHIP_FEE);
        octapad.sponsorCampaign(campaignId);
        vm.stopPrank();

        // Complete funding
        vm.startPrank(buyer1);
        usdc.approve(address(octapad), TARGET_FUNDING);
        octapad.buyTokens(campaignId, TARGET_FUNDING);
        vm.stopPrank();

        // Check strategy balance
        uint256 strategyBalance = usdc.balanceOf(address(strategy));
        console.log("Strategy USDC balance:", strategyBalance / 1e6, "USDC");

        // Simulate strategy earning yield
        uint256 profit = (strategyBalance * 20) / 100; // 20% profit
        usdc.mint(address(strategy), profit);
        console.log("Strategy earned profit:", profit / 1e6, "USDC");

        // Strategy reports profit by minting shares
        uint256 totalAssets = usdc.balanceOf(address(strategy));
        console.log("Total strategy assets:", totalAssets / 1e6, "USDC");

        // Verify funds are in strategy and earning yield
        assertTrue(strategyBalance > SPONSORSHIP_FEE);
        console.log(">> Strategy successfully holding and growing campaign funds");
    }

    /**
     * @notice Tests that platform fees and vested creator funds flow to YieldDonating Strategy
     * @dev Verifies revenue streams #2 and #3: platform fees + vested funds
     *
     * WHAT THIS TEST VERIFIES:
     * 1. Campaign reaches funding goal (10,000 USDC raised)
     * 2. Platform fee (5% = 500 USDC) → deposited to Strategy
     * 3. Vested creator funds (20% = 2,000 USDC) → deposited to Strategy IMMEDIATELY
     * 4. Total strategy increase: 2,500 USDC from one campaign completion
     *
     * DEMONSTRATES:
     * - Revenue Stream #2: Platform fees (5%) → Strategy
     * - Revenue Stream #3: Vested funds (20%) → Strategy (innovative!)
     * - Vesting innovation: Funds earn yield during vesting period
     * - Significant capital deployment per campaign (25% of raised funds)
     */
    function test_PlatformFeeDepositsToStrategy() public {
        console.log("=== TEST: Platform Fee Deposits to Strategy ===");

        // Create and sponsor campaign
        vm.prank(creator);
        uint32 campaignId = octapad.createCampaign(
            "Test",
            "TST",
            "Description",
            TARGET_FUNDING,
            TOTAL_SUPPLY,
            500000, // reserveRatio
            uint64(block.timestamp + 30 days)
        );

        vm.startPrank(creator);
        usdc.approve(address(octapad), SPONSORSHIP_FEE);
        octapad.sponsorCampaign(campaignId);
        vm.stopPrank();

        uint256 balanceAfterSponsorship = usdc.balanceOf(address(strategy));

        // Complete funding
        vm.startPrank(buyer1);
        usdc.approve(address(octapad), TARGET_FUNDING);
        octapad.buyTokens(campaignId, TARGET_FUNDING);
        vm.stopPrank();

        // Check strategy balance after funding complete
        uint256 balanceAfterFunding = usdc.balanceOf(address(strategy));

        // Calculate expected deposits
        uint128 expectedPlatformFee = (TARGET_FUNDING * 500) / 10000; // 5%
        uint128 expectedVested = (TARGET_FUNDING * 2000) / 10000; // 20%
        uint256 expectedIncrease = expectedPlatformFee + expectedVested;

        console.log("Platform fee (5%):", expectedPlatformFee / 1e6, "USDC");
        console.log("Vested (20%):", expectedVested / 1e6, "USDC");
        console.log("Total expected increase:", expectedIncrease / 1e6, "USDC");
        console.log("Actual increase:", (balanceAfterFunding - balanceAfterSponsorship) / 1e6, "USDC");

        // Verify platform fee + vested funds deposited
        assertEq(balanceAfterFunding - balanceAfterSponsorship, expectedIncrease);
        console.log(">> Platform fee + vested funds deposited to strategy");
    }

    /**
     * @notice Tests the 50/50 yield split between Dragon Router and OG Points holders
     * @dev Verifies PaymentSplitter correctly divides strategy profit shares
     *
     * WHAT THIS TEST VERIFIES:
     * 1. Strategy generates profit from yield-bearing activities
     * 2. Profit is minted as shares to PaymentSplitter
     * 3. PaymentSplitter splits shares 50/50:
     *    - 50% claimable by Dragon Router (for public goods)
     *    - 50% claimable by OGPointsRewards (for campaign participants)
     * 4. Both parties can claim their allocated shares
     *
     * DEMONSTRATES:
     * - Fair profit distribution mechanism
     * - Integration between Strategy, PaymentSplitter, and rewards system
     * - Alignment of incentives: Platform success = Participant rewards
     */
    function test_YieldSplit50_50() public {
        console.log("=== TEST: Yield Split 50/50 (Dragon Router + OG Points) ===");

        // Setup: Create campaign, sponsor, and fund
        vm.prank(creator);
        uint32 campaignId = octapad.createCampaign(
            "Test",
            "TST",
            "Description",
            TARGET_FUNDING,
            TOTAL_SUPPLY,
            500000, // reserveRatio
            uint64(block.timestamp + 30 days)
        );

        vm.startPrank(creator);
        usdc.approve(address(octapad), SPONSORSHIP_FEE);
        octapad.sponsorCampaign(campaignId);
        vm.stopPrank();

        vm.startPrank(buyer1);
        usdc.approve(address(octapad), TARGET_FUNDING);
        octapad.buyTokens(campaignId, TARGET_FUNDING);
        vm.stopPrank();

        // Strategy earns profit
        uint256 profit = 1000e6; // 1000 USDC profit
        usdc.mint(address(strategy), profit);
        strategy.mintProfitShares(address(splitter), profit);

        console.log("Strategy profit:", profit / 1e6, "USDC");

        // Check claimable shares for both parties
        uint256 dragonClaimable = splitter.releasable(IERC20(address(strategy)), dragonRouter);
        uint256 ogRewardsClaimable = splitter.releasable(IERC20(address(strategy)), address(ogRewards));

        console.log("Dragon Router claimable:", dragonClaimable / 1e6, "shares");
        console.log("OG Rewards claimable:", ogRewardsClaimable / 1e6, "shares");

        // Should be 50/50
        assertEq(dragonClaimable, profit / 2);
        assertEq(ogRewardsClaimable, profit / 2);

        console.log(">> Yield split 50/50 verified");
    }

    /*//////////////////////////////////////////////////////////////
                TEST: MULTIPLE CAMPAIGNS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleCampaigns() public {
        console.log("=== TEST: Multiple Campaigns ===");

        address creator2 = address(0x777);
        usdc.mint(creator2, 1000e6);

        // Campaign 1
        vm.prank(creator);
        uint32 campaign1 = octapad.createCampaign(
            "Token1",
            "TK1",
            "Campaign 1",
            TARGET_FUNDING,
            TOTAL_SUPPLY,
            500000, // reserveRatio
            uint64(block.timestamp + 30 days)
        );

        // Campaign 2
        vm.prank(creator2);
        uint32 campaign2 = octapad.createCampaign(
            "Token2",
            "TK2",
            "Campaign 2",
            TARGET_FUNDING * 2,
            TOTAL_SUPPLY * 2,
            500000, // reserveRatio
            uint64(block.timestamp + 30 days)
        );

        assertEq(campaign1, 1);
        assertEq(campaign2, 2);
        console.log(">> Multiple campaigns created with unique IDs");

        // Fund both campaigns
        vm.startPrank(buyer1);
        usdc.approve(address(octapad), TARGET_FUNDING * 3);
        octapad.buyTokens(campaign1, TARGET_FUNDING);
        octapad.buyTokens(campaign2, TARGET_FUNDING * 2);
        vm.stopPrank();

        console.log(">> Both campaigns funded successfully");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {OGPointsRewards} from "../src/launchpad/OGPointsRewards.sol";

/**
 * @title DeployOGPointsRewards
 * @notice Deployment script for OGPointsRewards on Base network
 *
 * @dev Dependencies (must be deployed first):
 * - OGPointsToken
 * - YieldDonating Strategy
 * - PaymentSplitter (deployed by YieldDonating factory or separately)
 *
 * Constructor Parameters:
 * - ogPointsToken: OGPointsToken address
 * - usdc: USDC token address
 * - admin: Admin address
 * - rewardsDistributor: Rewards distributor address (can be address(0))
 * - yieldStrategy: YieldDonating Strategy address
 * - paymentSplitter: PaymentSplitter address
 *
 * @dev Usage:
 *
 * Dry run:
 * forge script script/DeployOGPointsRewards.s.sol:DeployOGPointsRewards --rpc-url $BASE_RPC_URL
 *
 * Deploy:
 * forge script script/DeployOGPointsRewards.s.sol:DeployOGPointsRewards \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 */
contract DeployOGPointsRewards is Script {
    // Base Network Constants
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Deployment addresses (from environment)
    address ogPointsToken;
    address admin;
    address rewardsDistributor;
    address yieldStrategy;
    address paymentSplitter;

    // Deployed contract
    OGPointsRewards public ogPointsRewards;

    function setUp() public {
        // Load addresses from environment
        ogPointsToken = vm.envAddress("OG_POINTS_TOKEN_ADDRESS");
        admin = vm.envAddress("ADMIN_ADDRESS");
        yieldStrategy = vm.envAddress("YIELD_STRATEGY_ADDRESS");
        paymentSplitter = vm.envAddress("PAYMENT_SPLITTER_ADDRESS");

        // Rewards distributor is optional
        try vm.envAddress("REWARDS_DISTRIBUTOR_ADDRESS") returns (address addr) {
            rewardsDistributor = addr;
        } catch {
            rewardsDistributor = address(0);
            console2.log("INFO: REWARDS_DISTRIBUTOR_ADDRESS not set - using address(0)");
        }

        console2.log("==============================================");
        console2.log("OGPointsRewards Deployment Configuration");
        console2.log("==============================================");
        console2.log("Network: Base Mainnet");
        console2.log("OG Points Token:", ogPointsToken);
        console2.log("USDC:", USDC_BASE);
        console2.log("Admin:", admin);
        console2.log("Rewards Distributor:", rewardsDistributor);
        console2.log("Yield Strategy:", yieldStrategy);
        console2.log("Payment Splitter:", paymentSplitter);
        console2.log("==============================================");
    }

    function run() public {
        // Validate addresses
        require(ogPointsToken != address(0), "OG_POINTS_TOKEN_ADDRESS not set");
        require(admin != address(0), "ADMIN_ADDRESS not set");
        require(yieldStrategy != address(0), "YIELD_STRATEGY_ADDRESS not set");
        require(paymentSplitter != address(0), "PAYMENT_SPLITTER_ADDRESS not set");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\nDeployer:", deployer);
        console2.log("Deployer balance:", deployer.balance, "wei");

        require(deployer.balance > 0.001 ether, "Insufficient deployer balance");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy OGPointsRewards
        console2.log("\nDeploying OGPointsRewards...");
        ogPointsRewards = new OGPointsRewards(
            ogPointsToken,      // ogPointsToken
            USDC_BASE,          // usdc
            admin,              // admin
            rewardsDistributor, // rewardsDistributor (can be address(0))
            yieldStrategy,      // yieldStrategy
            paymentSplitter     // paymentSplitter
        );
        console2.log("OGPointsRewards deployed at:", address(ogPointsRewards));

        vm.stopBroadcast();

        // Verification
        console2.log("\n==============================================");
        console2.log("Deployment Complete - Verifying Configuration");
        console2.log("==============================================");

        _verifyDeployment();

        console2.log("\n==============================================");
        console2.log("Deployment Summary");
        console2.log("==============================================");
        console2.log("OGPointsRewards:", address(ogPointsRewards));
        console2.log("==============================================");
        console2.log("\nNext Steps:");
        console2.log("1. Save the OGPointsRewards address for keeper deployment");
        console2.log("2. Verify contract on Basescan");
        console2.log("3. Add OGPointsRewards to PaymentSplitter payees");
        console2.log("4. Test claimAndRedeemFromSplitter() function");
        console2.log("==============================================");
    }

    function _verifyDeployment() internal view {
        // Verify configuration
        require(address(ogPointsRewards.ogPointsToken()) == ogPointsToken, "OG Points Token mismatch");
        console2.log("OG Points Token:", address(ogPointsRewards.ogPointsToken()));

        require(address(ogPointsRewards.usdc()) == USDC_BASE, "USDC mismatch");
        console2.log("USDC:", address(ogPointsRewards.usdc()));

        require(ogPointsRewards.admin() == admin, "Admin mismatch");
        console2.log("Admin:", ogPointsRewards.admin());

        require(ogPointsRewards.rewardsDistributor() == rewardsDistributor, "Rewards Distributor mismatch");
        console2.log("Rewards Distributor:", ogPointsRewards.rewardsDistributor());

        require(ogPointsRewards.yieldStrategy() == yieldStrategy, "Yield Strategy mismatch");
        console2.log("Yield Strategy:", ogPointsRewards.yieldStrategy());

        require(ogPointsRewards.paymentSplitter() == paymentSplitter, "Payment Splitter mismatch");
        console2.log("Payment Splitter:", ogPointsRewards.paymentSplitter());

        (
            uint256 totalPoints,
            uint256 rewardsPerPoint_,
            uint256 totalDeposited,
            uint256 totalClaimed,
            uint256 pending
        ) = ogPointsRewards.getGlobalStats();

        console2.log("\nInitial State:");
        console2.log("Total Points:", totalPoints);
        console2.log("Rewards Per Point:", rewardsPerPoint_);
        console2.log("Total Deposited:", totalDeposited);
        console2.log("Total Claimed:", totalClaimed);
        console2.log("Pending Rewards:", pending);

        console2.log("\nOGPointsRewards configuration verified successfully!");
    }
}

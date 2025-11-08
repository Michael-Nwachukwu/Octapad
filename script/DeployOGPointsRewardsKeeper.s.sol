// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {OGPointsRewardsKeeper} from "../src/launchpad/OGPointsRewardsKeeper.sol";

/**
 * @title DeployOGPointsRewardsKeeper
 * @notice Deployment script for OGPointsRewardsKeeper on Base network
 *
 * @dev Dependencies (must be deployed first):
 * - OGPointsRewards
 *
 * Constructor Parameters:
 * - ogPointsRewards: OGPointsRewards address
 * - minHarvestAmount: Minimum strategy shares to trigger harvest (e.g., $1 = 1e6)
 *
 * @dev Usage:
 *
 * Dry run:
 * forge script script/DeployOGPointsRewardsKeeper.s.sol:DeployOGPointsRewardsKeeper --rpc-url $BASE_RPC_URL
 *
 * Deploy:
 * forge script script/DeployOGPointsRewardsKeeper.s.sol:DeployOGPointsRewardsKeeper \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 */
contract DeployOGPointsRewardsKeeper is Script {
    // Configuration
    uint256 constant MIN_HARVEST_AMOUNT = 1e6; // $1 in USDC (6 decimals)

    // Deployment addresses (from environment)
    address ogPointsRewards;

    // Deployed contract
    OGPointsRewardsKeeper public keeper;

    function setUp() public {
        // Load addresses from environment
        ogPointsRewards = vm.envAddress("OG_POINTS_REWARDS_ADDRESS");

        console2.log("==============================================");
        console2.log("OGPointsRewardsKeeper Deployment Configuration");
        console2.log("==============================================");
        console2.log("Network: Base Mainnet");
        console2.log("OG Points Rewards:", ogPointsRewards);
        console2.log("Min Harvest Amount:", MIN_HARVEST_AMOUNT, "(USDC - 6 decimals)");
        console2.log("==============================================");
    }

    function run() public {
        // Validate addresses
        require(ogPointsRewards != address(0), "OG_POINTS_REWARDS_ADDRESS not set");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\nDeployer:", deployer);
        console2.log("Deployer balance:", deployer.balance, "wei");

        require(deployer.balance > 0.001 ether, "Insufficient deployer balance");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy OGPointsRewardsKeeper
        console2.log("\nDeploying OGPointsRewardsKeeper...");
        keeper = new OGPointsRewardsKeeper(
            ogPointsRewards,    // ogPointsRewards
            MIN_HARVEST_AMOUNT  // minHarvestAmount
        );
        console2.log("OGPointsRewardsKeeper deployed at:", address(keeper));

        vm.stopBroadcast();

        // Verification
        console2.log("\n==============================================");
        console2.log("Deployment Complete - Verifying Configuration");
        console2.log("==============================================");

        _verifyDeployment();

        console2.log("\n==============================================");
        console2.log("Deployment Summary");
        console2.log("==============================================");
        console2.log("OGPointsRewardsKeeper:", address(keeper));
        console2.log("==============================================");
        console2.log("\nNext Steps:");
        console2.log("1. Verify contract on Basescan");
        console2.log("2. Set up Gelato/Chainlink automation for performUpkeep()");
        console2.log("3. Monitor keeper operations");
        console2.log("4. Adjust minHarvestAmount if needed");
        console2.log("==============================================");
    }

    function _verifyDeployment() internal view {
        // Verify configuration
        require(address(keeper.ogPointsRewards()) == ogPointsRewards, "OG Points Rewards mismatch");
        console2.log("OG Points Rewards:", address(keeper.ogPointsRewards()));

        require(keeper.minHarvestAmount() == MIN_HARVEST_AMOUNT, "Min Harvest Amount mismatch");
        console2.log("Min Harvest Amount:", keeper.minHarvestAmount());

        // Check upkeep status
        (bool upkeepNeeded, ) = keeper.checkUpkeep("");
        console2.log("Upkeep Needed:", upkeepNeeded);

        console2.log("\nOGPointsRewardsKeeper configuration verified successfully!");
    }
}

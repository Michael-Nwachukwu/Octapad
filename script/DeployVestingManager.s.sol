// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {VestingManager} from "../src/launchpad/VestingManager.sol";

/**
 * @title DeployVestingManager
 * @notice Deployment script for VestingManager on Base network
 *
 * @dev Dependencies:
 * - YieldDonating Strategy (must be deployed first)
 * - OctaPad address (will be set after OctaPad deployment via setLaunchpad())
 *
 * Constructor Parameters:
 * - launchpad: OctaPad address (can be address(0) initially, set later)
 * - usdc: USDC token address
 * - yieldStrategy: YieldDonating Strategy address
 *
 * @dev Usage:
 *
 * Dry run:
 * forge script script/DeployVestingManager.s.sol:DeployVestingManager --rpc-url $BASE_RPC_URL
 *
 * Deploy:
 * forge script script/DeployVestingManager.s.sol:DeployVestingManager \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 */
contract DeployVestingManager is Script {
    // Base Network Constants
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Deployment addresses (from environment)
    address yieldStrategy;
    address octaPad; // Can be address(0) initially

    // Deployed contract
    VestingManager public vestingManager;

    function setUp() public {
        // Load addresses from environment
        yieldStrategy = vm.envAddress("YIELD_STRATEGY_ADDRESS");

        // OctaPad address may not exist yet (circular dependency)
        // We'll deploy with address(0) and set it later
        try vm.envAddress("OCTAPAD_ADDRESS") returns (address addr) {
            octaPad = addr;
        } catch {
            octaPad = address(0);
            console2.log("WARNING: OCTAPAD_ADDRESS not set - will need to call setLaunchpad() after OctaPad deployment");
        }

        console2.log("==============================================");
        console2.log("VestingManager Deployment Configuration");
        console2.log("==============================================");
        console2.log("Network: Base Mainnet");
        console2.log("USDC:", USDC_BASE);
        console2.log("Yield Strategy:", yieldStrategy);
        console2.log("OctaPad (can be zero):", octaPad);
        console2.log("==============================================");
    }

    function run() public {
        // Validate addresses
        require(yieldStrategy != address(0), "YIELD_STRATEGY_ADDRESS not set");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\nDeployer:", deployer);
        console2.log("Deployer balance:", deployer.balance, "wei");

        require(deployer.balance > 0.001 ether, "Insufficient deployer balance");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy VestingManager
        console2.log("\nDeploying VestingManager...");
        vestingManager = new VestingManager(
            octaPad,        // launchpad (can be address(0))
            USDC_BASE,      // usdc
            yieldStrategy   // yieldStrategy
        );
        console2.log("VestingManager deployed at:", address(vestingManager));

        vm.stopBroadcast();

        // Verification
        console2.log("\n==============================================");
        console2.log("Deployment Complete - Verifying Configuration");
        console2.log("==============================================");

        _verifyDeployment();

        console2.log("\n==============================================");
        console2.log("Deployment Summary");
        console2.log("==============================================");
        console2.log("VestingManager:", address(vestingManager));
        console2.log("==============================================");
        console2.log("\nNext Steps:");
        console2.log("1. Save the VestingManager address for OctaPad deployment");
        console2.log("2. After OctaPad is deployed, call vestingManager.setLaunchpad(octaPadAddress)");
        console2.log("3. Verify contract on Basescan");
        console2.log("==============================================");
    }

    function _verifyDeployment() internal view {
        // Verify configuration
        require(address(vestingManager.usdc()) == USDC_BASE, "USDC mismatch");
        console2.log("USDC:", address(vestingManager.usdc()));

        require(vestingManager.yieldStrategy() == yieldStrategy, "Strategy mismatch");
        console2.log("Yield Strategy:", vestingManager.yieldStrategy());

        console2.log("Launchpad:", vestingManager.launchpad());
        if (octaPad != address(0)) {
            require(vestingManager.launchpad() == octaPad, "Launchpad mismatch");
        }

        console2.log("\nVestingManager configuration verified successfully!");
    }
}

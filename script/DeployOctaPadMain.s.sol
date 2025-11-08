// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {OctaPad} from "../src/launchpad/OctaPad.sol";

/**
 * @title DeployOctaPadMain
 * @notice Deployment script for OctaPad main contract on Base network
 *
 * @dev Dependencies (must be deployed first):
 * - OGPointsToken
 * - VestingManager
 * - YieldDonating Strategy
 * - Uniswap v4 Pool Manager
 *
 * Constructor Parameters:
 * - owner: Owner address (protocol governance/multisig)
 * - usdc: USDC token address
 * - yieldStrategy: YieldDonating Strategy address
 * - vestingManager: VestingManager address
 * - ogPointsToken: OGPointsToken address
 * - uniswapPoolManager: Uniswap v4 Pool Manager address
 *
 * @dev Usage:
 *
 * Dry run:
 * forge script script/DeployOctaPadMain.s.sol:DeployOctaPadMain --rpc-url $BASE_RPC_URL
 *
 * Deploy:
 * forge script script/DeployOctaPadMain.s.sol:DeployOctaPadMain \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 */
contract DeployOctaPadMain is Script {
    // Base Network Constants
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant POOL_MANAGER_BASE = 0x282DD0400E594C650A15830e0d4490A52249841f;

    // Deployment addresses (from environment)
    address owner;
    address yieldStrategy;
    address vestingManager;
    address ogPointsToken;

    // Deployed contract
    OctaPad public octaPad;

    function setUp() public {
        // Load addresses from environment
        owner = vm.envAddress("OWNER_ADDRESS");
        yieldStrategy = vm.envAddress("YIELD_STRATEGY_ADDRESS");
        vestingManager = vm.envAddress("VESTING_MANAGER_ADDRESS");
        ogPointsToken = vm.envAddress("OG_POINTS_TOKEN_ADDRESS");

        console2.log("==============================================");
        console2.log("OctaPad Deployment Configuration");
        console2.log("==============================================");
        console2.log("Network: Base Mainnet");
        console2.log("Owner:", owner);
        console2.log("USDC:", USDC_BASE);
        console2.log("Yield Strategy:", yieldStrategy);
        console2.log("Vesting Manager:", vestingManager);
        console2.log("OG Points Token:", ogPointsToken);
        console2.log("Pool Manager:", POOL_MANAGER_BASE);
        console2.log("==============================================");
    }

    function run() public {
        // Validate addresses
        require(owner != address(0), "OWNER_ADDRESS not set");
        require(yieldStrategy != address(0), "YIELD_STRATEGY_ADDRESS not set");
        require(vestingManager != address(0), "VESTING_MANAGER_ADDRESS not set");
        require(ogPointsToken != address(0), "OG_POINTS_TOKEN_ADDRESS not set");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\nDeployer:", deployer);
        console2.log("Deployer balance:", deployer.balance, "wei");

        require(deployer.balance > 0.001 ether, "Insufficient deployer balance");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy OctaPad
        console2.log("\nDeploying OctaPad...");
        octaPad = new OctaPad(
            owner,              // owner
            USDC_BASE,          // usdc
            yieldStrategy,      // yieldStrategy
            vestingManager,     // vestingManager
            ogPointsToken,      // ogPointsToken
            POOL_MANAGER_BASE   // uniswapPoolManager
        );
        console2.log("OctaPad deployed at:", address(octaPad));

        vm.stopBroadcast();

        // Verification
        console2.log("\n==============================================");
        console2.log("Deployment Complete - Verifying Configuration");
        console2.log("==============================================");

        _verifyDeployment();

        console2.log("\n==============================================");
        console2.log("Deployment Summary");
        console2.log("==============================================");
        console2.log("OctaPad:", address(octaPad));
        console2.log("==============================================");
        console2.log("\nNext Steps:");
        console2.log("1. Call vestingManager.setLaunchpad(", address(octaPad), ")");
        console2.log("2. Set up YieldDonatingFeeHook via setYieldDonatingFeeHook()");
        console2.log("3. Verify contract on Basescan");
        console2.log("4. Create first campaign");
        console2.log("==============================================");
    }

    function _verifyDeployment() internal view {
        // Verify configuration
        require(octaPad.owner() == owner, "Owner mismatch");
        console2.log("Owner:", octaPad.owner());

        require(address(octaPad.usdc()) == USDC_BASE, "USDC mismatch");
        console2.log("USDC:", address(octaPad.usdc()));

        require(octaPad.yieldStrategy() == yieldStrategy, "Strategy mismatch");
        console2.log("Yield Strategy:", octaPad.yieldStrategy());

        require(address(octaPad.vestingManager()) == vestingManager, "Vesting Manager mismatch");
        console2.log("Vesting Manager:", address(octaPad.vestingManager()));

        require(address(octaPad.ogPointsToken()) == ogPointsToken, "OG Points Token mismatch");
        console2.log("OG Points Token:", address(octaPad.ogPointsToken()));

        require(address(octaPad.uniswapPoolManager()) == POOL_MANAGER_BASE, "Pool Manager mismatch");
        console2.log("Pool Manager:", address(octaPad.uniswapPoolManager()));

        console2.log("\nOctaPad configuration verified successfully!");
    }
}

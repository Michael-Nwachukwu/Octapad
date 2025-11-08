// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {OctaPadDEX} from "../src/launchpad/OctaPadDEX.sol";

/**
 * @title DeployOctaPadDEX
 * @notice Deployment script for OctaPadDEX on Base network
 *
 * @dev Dependencies:
 * - Uniswap v4 Pool Manager (provided: 0x282DD0400E594C650A15830e0d4490A52249841f)
 *
 * Constructor Parameters:
 * - poolManager: Uniswap v4 Pool Manager address
 * - usdc: USDC token address
 * - admin: Admin address (can register pools, set slippage)
 *
 * @dev Usage:
 *
 * Dry run:
 * forge script script/DeployOctaPadDEX.s.sol:DeployOctaPadDEX --rpc-url $BASE_RPC_URL
 *
 * Deploy:
 * forge script script/DeployOctaPadDEX.s.sol:DeployOctaPadDEX \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 */
contract DeployOctaPadDEX is Script {
    // Base Network Constants
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant POOL_MANAGER_BASE = 0x282DD0400E594C650A15830e0d4490A52249841f;

    // Deployment addresses (from environment)
    address admin;

    // Deployed contract
    OctaPadDEX public octaPadDEX;

    function setUp() public {
        // Load addresses from environment
        admin = vm.envAddress("ADMIN_ADDRESS");

        console2.log("==============================================");
        console2.log("OctaPadDEX Deployment Configuration");
        console2.log("==============================================");
        console2.log("Network: Base Mainnet");
        console2.log("USDC:", USDC_BASE);
        console2.log("Pool Manager:", POOL_MANAGER_BASE);
        console2.log("Admin:", admin);
        console2.log("==============================================");
    }

    function run() public {
        // Validate addresses
        require(admin != address(0), "ADMIN_ADDRESS not set");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\nDeployer:", deployer);
        console2.log("Deployer balance:", deployer.balance, "wei");

        require(deployer.balance > 0.001 ether, "Insufficient deployer balance");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy OctaPadDEX
        console2.log("\nDeploying OctaPadDEX...");
        octaPadDEX = new OctaPadDEX(
            POOL_MANAGER_BASE,  // poolManager
            USDC_BASE,          // usdc
            admin               // admin
        );
        console2.log("OctaPadDEX deployed at:", address(octaPadDEX));

        vm.stopBroadcast();

        // Verification
        console2.log("\n==============================================");
        console2.log("Deployment Complete - Verifying Configuration");
        console2.log("==============================================");

        _verifyDeployment();

        console2.log("\n==============================================");
        console2.log("Deployment Summary");
        console2.log("==============================================");
        console2.log("OctaPadDEX:", address(octaPadDEX));
        console2.log("==============================================");
        console2.log("\nNext Steps:");
        console2.log("1. Verify contract on Basescan");
        console2.log("2. Register campaign pools via registerPool()");
        console2.log("3. Set up frontend integration");
        console2.log("==============================================");
    }

    function _verifyDeployment() internal view {
        // Verify configuration
        require(address(octaPadDEX.poolManager()) == POOL_MANAGER_BASE, "Pool Manager mismatch");
        console2.log("Pool Manager:", address(octaPadDEX.poolManager()));

        require(address(octaPadDEX.usdc()) == USDC_BASE, "USDC mismatch");
        console2.log("USDC:", address(octaPadDEX.usdc()));

        require(octaPadDEX.admin() == admin, "Admin mismatch");
        console2.log("Admin:", octaPadDEX.admin());

        (uint16 defaultSlippage, uint16 maxSlippage) = octaPadDEX.getSlippageSettings();
        console2.log("Default Slippage:", defaultSlippage, "bps");
        console2.log("Max Slippage:", maxSlippage, "bps");

        console2.log("\nOctaPadDEX configuration verified successfully!");
    }
}

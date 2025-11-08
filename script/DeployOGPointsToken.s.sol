// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {OGPointsToken} from "../src/launchpad/OGPointsToken.sol";

/**
 * @title DeployOGPointsToken
 * @notice Deployment script for OGPointsToken on Base network
 *
 * @dev This contract has NO dependencies and should be deployed FIRST
 *
 * Constructor Parameters:
 * - name: Token name (e.g., "OctaPad OG Points")
 * - symbol: Token symbol (e.g., "OGP")
 * - admin: Admin address (can mint/burn)
 * - isNonTransferable: Whether token is transferable (true for OG points)
 *
 * @dev Usage:
 *
 * Dry run:
 * forge script script/DeployOGPointsToken.s.sol:DeployOGPointsToken --rpc-url $BASE_RPC_URL
 *
 * Deploy:
 * forge script script/DeployOGPointsToken.s.sol:DeployOGPointsToken \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 */
contract DeployOGPointsToken is Script {
    // Configuration
    string constant TOKEN_NAME = "OctaPad OG Points";
    string constant TOKEN_SYMBOL = "OGP";
    bool constant IS_NON_TRANSFERABLE = true; // OG Points are non-transferable

    // Deployment addresses (from environment)
    address admin;

    // Deployed contract
    OGPointsToken public ogPointsToken;

    function setUp() public {
        // Load addresses from environment
        admin = vm.envAddress("ADMIN_ADDRESS");

        console2.log("==============================================");
        console2.log("OGPointsToken Deployment Configuration");
        console2.log("==============================================");
        console2.log("Network: Base Mainnet");
        console2.log("Token Name:", TOKEN_NAME);
        console2.log("Token Symbol:", TOKEN_SYMBOL);
        console2.log("Admin:", admin);
        console2.log("Non-Transferable:", IS_NON_TRANSFERABLE);
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

        // Deploy OGPointsToken
        console2.log("\nDeploying OGPointsToken...");
        ogPointsToken = new OGPointsToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            admin,
            IS_NON_TRANSFERABLE
        );
        console2.log("OGPointsToken deployed at:", address(ogPointsToken));

        vm.stopBroadcast();

        // Verification
        console2.log("\n==============================================");
        console2.log("Deployment Complete - Verifying Configuration");
        console2.log("==============================================");

        _verifyDeployment();

        console2.log("\n==============================================");
        console2.log("Deployment Summary");
        console2.log("==============================================");
        console2.log("OGPointsToken:", address(ogPointsToken));
        console2.log("==============================================");
        console2.log("\nNext Steps:");
        console2.log("1. Save the OGPointsToken address for other deployments");
        console2.log("2. Verify contract on Basescan");
        console2.log("3. Set up minter role (OctaPad will need mint permissions)");
        console2.log("==============================================");
    }

    function _verifyDeployment() internal view {
        // Verify token configuration
        require(
            keccak256(bytes(ogPointsToken.name())) == keccak256(bytes(TOKEN_NAME)),
            "Token name mismatch"
        );
        console2.log("Token Name:", ogPointsToken.name());

        require(
            keccak256(bytes(ogPointsToken.symbol())) == keccak256(bytes(TOKEN_SYMBOL)),
            "Token symbol mismatch"
        );
        console2.log("Token Symbol:", ogPointsToken.symbol());

        require(ogPointsToken.totalSupply() == 0, "Should have no supply initially");
        console2.log("Total Supply:", ogPointsToken.totalSupply());

        console2.log("\nOGPointsToken configuration verified successfully!");
    }
}

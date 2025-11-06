// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {YieldDonatingStrategy} from "../src/strategies/yieldDonating/YieldDonatingStrategy.sol";
import {YieldDonatingStrategyFactory} from "../src/strategies/yieldDonating/YieldDonatingStrategyFactory.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

/**
 * @title DeployYieldDonating
 * @notice Deployment script for YieldDonating Strategy on Base network
 *
 * @dev Usage:
 *
 * Dry run:
 * forge script script/DeployYieldDonating.s.sol:DeployYieldDonating --rpc-url $BASE_RPC_URL
 *
 * Deploy:
 * forge script script/DeployYieldDonating.s.sol:DeployYieldDonating \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $BASESCAN_API_KEY
 */
contract DeployYieldDonating is Script {
    // Base Network Constants
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant KALANI_VAULT_BASE = 0x7ea9FAC329636f532aE29E1c9EC9A964337bDA24;

    // Strategy configuration
    string constant STRATEGY_NAME = "Kalani USDC YieldDonating Strategy";
    bool constant ENABLE_BURNING = true;

    // Deployment addresses (from environment)
    address management;
    address keeper;
    address emergencyAdmin;
    address dragonRouter;

    // Deployed contracts
    YieldDonatingTokenizedStrategy public tokenizedStrategy;
    YieldDonatingStrategyFactory public factory;
    IStrategyInterface public strategy;

    function setUp() public {
        // Load addresses from environment
        management = vm.envAddress("MANAGEMENT_ADDRESS");
        keeper = vm.envAddress("KEEPER_ADDRESS");
        emergencyAdmin = vm.envAddress("EMERGENCY_ADMIN_ADDRESS");
        dragonRouter = vm.envAddress("DRAGON_ROUTER_ADDRESS");

        console2.log("==============================================");
        console2.log("YieldDonating Strategy Deployment Configuration");
        console2.log("==============================================");
        console2.log("Network: Base Mainnet");
        console2.log("Asset (USDC):", USDC_BASE);
        console2.log("Yield Source (Kalani):", KALANI_VAULT_BASE);
        console2.log("Management:", management);
        console2.log("Keeper:", keeper);
        console2.log("Emergency Admin:", emergencyAdmin);
        console2.log("Dragon Router:", dragonRouter);
        console2.log("==============================================");
    }

    function run() public {
        // Validate addresses
        require(management != address(0), "MANAGEMENT_ADDRESS not set");
        require(keeper != address(0), "KEEPER_ADDRESS not set");
        require(emergencyAdmin != address(0), "EMERGENCY_ADMIN_ADDRESS not set");
        require(dragonRouter != address(0), "DRAGON_ROUTER_ADDRESS not set");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\nDeployer:", deployer);
        console2.log("Deployer balance:", deployer.balance, "wei");

        require(deployer.balance > 0.01 ether, "Insufficient deployer balance");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy YieldDonatingStrategyFactory
        // Factory constructor: (management, donationAddress, keeper, emergencyAdmin)
        console2.log("\n[1/2] Deploying YieldDonatingStrategyFactory...");
        factory = new YieldDonatingStrategyFactory(
            management,
            dragonRouter, // donationAddress
            keeper,
            emergencyAdmin
        );
        console2.log("YieldDonatingStrategyFactory deployed at:", address(factory));

        // Get the tokenized strategy address deployed by factory
        tokenizedStrategy = YieldDonatingTokenizedStrategy(factory.tokenizedStrategyAddress());
        console2.log("YieldDonatingTokenizedStrategy deployed at:", address(tokenizedStrategy));

        // Step 2: Deploy YieldDonatingStrategy via factory
        // newStrategy(compounderVault, asset, name)
        console2.log("\n[2/2] Deploying YieldDonatingStrategy...");
        address strategyAddress = factory.newStrategy(
            KALANI_VAULT_BASE, // _compounderVault (yield source)
            USDC_BASE,         // _asset
            STRATEGY_NAME      // _name
        );

        strategy = IStrategyInterface(strategyAddress);
        console2.log("YieldDonatingStrategy deployed at:", strategyAddress);

        vm.stopBroadcast();

        // Verification
        console2.log("\n==============================================");
        console2.log("Deployment Complete - Verifying Configuration");
        console2.log("==============================================");

        _verifyDeployment();

        console2.log("\n==============================================");
        console2.log("Deployment Summary");
        console2.log("==============================================");
        console2.log("YieldDonatingTokenizedStrategy:", address(tokenizedStrategy));
        console2.log("YieldDonatingStrategyFactory:", address(factory));
        console2.log("YieldDonatingStrategy:", address(strategy));
        console2.log("==============================================");
        console2.log("\nNext Steps:");
        console2.log("1. Verify contracts on Basescan");
        console2.log("2. Test with small deposit");
        console2.log("3. Set up keeper automation");
        console2.log("4. Monitor vault health");
        console2.log("==============================================");
    }

    function _verifyDeployment() internal view {
        // Verify strategy configuration
        require(strategy.asset() == USDC_BASE, "Asset mismatch");
        console2.log("Asset:", strategy.asset());

        require(strategy.management() == management, "Management mismatch");
        console2.log("Management:", strategy.management());

        require(strategy.keeper() == keeper, "Keeper mismatch");
        console2.log("Keeper:", strategy.keeper());

        require(strategy.emergencyAdmin() == emergencyAdmin, "Emergency admin mismatch");
        console2.log("Emergency Admin:", strategy.emergencyAdmin());

        // Check yield source using low-level call since it's not in IStrategy
        (bool success, bytes memory data) = address(strategy).staticcall(
            abi.encodeWithSignature("yieldSource()")
        );
        require(success, "yieldSource call failed");
        address yieldSource = abi.decode(data, (address));
        require(yieldSource == KALANI_VAULT_BASE, "Yield source mismatch");
        console2.log("Yield Source:", yieldSource);

        // Check dragon router using TokenizedStrategy interface
        (success, data) = address(strategy).staticcall(
            abi.encodeWithSignature("dragonRouter()")
        );
        require(success, "dragonRouter call failed");
        address router = abi.decode(data, (address));
        require(router == dragonRouter, "Dragon router mismatch");
        console2.log("Dragon Router:", router);

        // Check vault health
        (success, data) = address(strategy).staticcall(
            abi.encodeWithSignature("getVaultHealth()")
        );
        require(success, "getVaultHealth call failed");
        (bool isPaused, uint256 failures, uint256 lastFailure) = abi.decode(
            data,
            (bool, uint256, uint256)
        );
        console2.log("Vault Paused:", isPaused);
        console2.log("Consecutive Failures:", failures);
        console2.log("Last Failure Time:", lastFailure);

        require(!isPaused, "Vault should not be paused");
        require(failures == 0, "Should have no failures");

        // Check initial state
        require(strategy.totalAssets() == 0, "Should have no assets initially");
        console2.log("Total Assets:", strategy.totalAssets());

        require(!strategy.isShutdown(), "Should not be shutdown");
        console2.log("Is Shutdown:", strategy.isShutdown());

        console2.log("\nStrategy configuration verified successfully!");
    }
}

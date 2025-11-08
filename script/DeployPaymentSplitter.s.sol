// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {PaymentSplitter} from "@octant-core/core/PaymentSplitter.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts-5.3.0/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPaymentSplitter
 * @notice Deploy PaymentSplitter for 50/50 yield distribution
 *
 * @dev Splits YieldDonating Strategy profit shares:
 * - 50% to Dragon Router (protocol treasury)
 * - 50% to OGPointsRewards (for OG Points holders)
 *
 * Usage:
 * forge script script/DeployPaymentSplitter.s.sol:DeployPaymentSplitter \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify
 */
contract DeployPaymentSplitter is Script {
    function run() public {
        // Load addresses from environment
        address dragonRouter = vm.envAddress("DRAGON_ROUTER_ADDRESS");

        // OGPointsRewards address - may not exist yet
        address ogPointsRewards;
        try vm.envAddress("OG_POINTS_REWARDS_ADDRESS") returns (address addr) {
            ogPointsRewards = addr;
        } catch {
            // If not deployed yet, use placeholder (you'll update later)
            ogPointsRewards = address(0);
            console2.log("WARNING: OG_POINTS_REWARDS_ADDRESS not set - using address(0)");
            console2.log("You'll need to add OGPointsRewards as payee after deployment");
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("==============================================");
        console2.log("PaymentSplitter Deployment");
        console2.log("==============================================");
        console2.log("Deployer:", deployer);
        console2.log("Dragon Router:", dragonRouter);
        console2.log("OG Points Rewards:", ogPointsRewards);
        console2.log("==============================================");

        require(dragonRouter != address(0), "DRAGON_ROUTER_ADDRESS not set");

        vm.startBroadcast(deployerPrivateKey);

        // Prepare payees and shares
        address[] memory payees;
        uint256[] memory shares;

        if (ogPointsRewards != address(0)) {
            // Both payees configured
            payees = new address[](2);
            shares = new uint256[](2);
            payees[0] = dragonRouter;
            payees[1] = ogPointsRewards;
            shares[0] = 50; // 50%
            shares[1] = 50; // 50%
        } else {
            // Only Dragon Router for now
            payees = new address[](1);
            shares = new uint256[](1);
            payees[0] = dragonRouter;
            shares[0] = 100; // 100% temporarily
        }

        // Step 1: Deploy PaymentSplitter implementation
        console2.log("\nDeploying PaymentSplitter implementation...");
        PaymentSplitter implementation = new PaymentSplitter();
        console2.log("Implementation deployed at:", address(implementation));

        // Step 2: Encode initialize call
        bytes memory initData = abi.encodeWithSelector(
            PaymentSplitter.initialize.selector,
            payees,
            shares
        );

        // Step 3: Deploy ERC1967 Proxy pointing to implementation
        console2.log("\nDeploying ERC1967 Proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console2.log("Proxy deployed at:", address(proxy));

        // Wrap proxy in PaymentSplitter interface
        PaymentSplitter splitter = PaymentSplitter(payable(address(proxy)));

        vm.stopBroadcast();

        console2.log("\n==============================================");
        console2.log("DEPLOYMENT COMPLETE");
        console2.log("==============================================");
        console2.log("PaymentSplitter Implementation:", address(implementation));
        console2.log("PaymentSplitter Proxy (USE THIS):", address(splitter));
        console2.log("==============================================");
        console2.log("\nAdd to .env:");
        console2.log("PAYMENT_SPLITTER_ADDRESS=", address(splitter));

        if (ogPointsRewards == address(0)) {
            console2.log("\nWARNING:");
            console2.log("PaymentSplitter initialized with only Dragon Router (100%)");
            console2.log("Payee list is IMMUTABLE after initialization!");
            console2.log("");
            console2.log("IMPORTANT: You MUST know the OGPointsRewards address BEFORE deploying PaymentSplitter");
            console2.log("If you don't have it yet:");
            console2.log("1. Deploy OGPointsRewards first (it needs PaymentSplitter address)");
            console2.log("2. Use a placeholder address for PaymentSplitter in OGPointsRewards");
            console2.log("3. Then deploy PaymentSplitter with BOTH addresses");
            console2.log("");
            console2.log("Current setup will send 100% of yield to Dragon Router only.");
        } else {
            console2.log("\nPayee Configuration:");
            console2.log("  Dragon Router: 50%");
            console2.log("  OG Points Rewards: 50%");
        }
        console2.log("==============================================");
    }
}

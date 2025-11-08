// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

/**
 * @title InteractYieldDonating
 * @notice Script to interact with deployed YieldDonating Strategy
 *
 * @dev Available operations:
 * - deposit: Deposit USDC to strategy
 * - withdraw: Withdraw USDC from strategy
 * - report: Trigger harvest and report
 * - deployFunds: Deploy idle USDC to Kalani
 * - freeFunds: Withdraw USDC from Kalani to idle
 * - status: View strategy status
 *
 * Usage Examples:
 *
 * 1. Deposit $1 USDC:
 * forge script script/InteractYieldDonating.s.sol:InteractYieldDonating \
 *   --sig "deposit(uint256)" 1000000 \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast
 *
 * 2. Report (harvest):
 * forge script script/InteractYieldDonating.s.sol:InteractYieldDonating \
 *   --sig "report()" \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast
 *
 * 3. Deploy idle funds to Kalani:
 * forge script script/InteractYieldDonating.s.sol:InteractYieldDonating \
 *   --sig "deployFunds(uint256)" 5000000 \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast
 *
 * 4. Free funds from Kalani:
 * forge script script/InteractYieldDonating.s.sol:InteractYieldDonating \
 *   --sig "freeFunds(uint256)" 5000000 \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast
 *
 * 5. View status (no broadcast needed):
 * forge script script/InteractYieldDonating.s.sol:InteractYieldDonating \
 *   --sig "status()" \
 *   --rpc-url $BASE_RPC_URL
 *
 * 6. Withdraw $5:
 * forge script script/InteractYieldDonating.s.sol:InteractYieldDonating \
 *   --sig "withdraw(uint256)" 1000000 \
 *   --rpc-url $BASE_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast
 */
contract InteractYieldDonating is Script {
    // Base Network Constants
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Strategy address (load from env)
    address strategyAddress;
    IStrategyInterface strategy;
    IERC20 usdc;

    function setUp() public {
        strategyAddress = vm.envAddress("YIELD_STRATEGY_ADDRESS");
        strategy = IStrategyInterface(strategyAddress);
        usdc = IERC20(USDC_BASE);

        console2.log("==============================================");
        console2.log("YieldDonating Strategy Interaction");
        console2.log("==============================================");
        console2.log("Strategy:", strategyAddress);
        console2.log("USDC:", USDC_BASE);
        console2.log("==============================================");
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT OPERATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit USDC to strategy
     * @param amount Amount in USDC (6 decimals, e.g., 10000000 = $10)
     */
    function deposit(uint256 amount) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\n[DEPOSIT] Depositing", amount, "USDC to strategy");
        console2.log("From:", deployer);

        // Check USDC balance
        uint256 balance = usdc.balanceOf(deployer);
        console2.log("Current USDC balance:", balance);
        require(balance >= amount, "Insufficient USDC balance");

        vm.startBroadcast(deployerPrivateKey);

        // Approve strategy
        usdc.approve(strategyAddress, amount);
        console2.log("Approved strategy for", amount, "USDC");

        // Deposit
        uint256 shares = strategy.deposit(amount, deployer);
        console2.log("Received", shares, "strategy shares");

        vm.stopBroadcast();

        console2.log("\nDeposit successful!");
        console2.log("New total assets:", strategy.totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW OPERATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw USDC from strategy
     * @param amount Amount in USDC (6 decimals)
     */
    function withdraw(uint256 amount) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\n[WITHDRAW] Withdrawing", amount, "USDC from strategy");
        console2.log("To:", deployer);

        uint256 shares = strategy.balanceOf(deployer);
        console2.log("Your shares:", shares);

        vm.startBroadcast(deployerPrivateKey);

        // Withdraw
        uint256 withdrawn = strategy.withdraw(amount, deployer, deployer);
        console2.log("Withdrawn", withdrawn, "USDC");

        vm.stopBroadcast();

        console2.log("\nWithdraw successful!");
        console2.log("New total assets:", strategy.totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                        REPORT OPERATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Trigger harvest and report (keeper function)
     * @dev Only keeper can call this
     */
    function report() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\n[REPORT] Triggering harvest and report");
        console2.log("Caller:", deployer);

        address keeper = strategy.keeper();
        console2.log("Strategy keeper:", keeper);

        if (deployer != keeper) {
            console2.log("WARNING: You are not the keeper!");
            console2.log("Report may fail if caller is not keeper");
        }

        console2.log("\nBefore report:");
        console2.log("  Total Assets:", strategy.totalAssets());

        vm.startBroadcast(deployerPrivateKey);

        // Call report
        (uint256 profit, uint256 loss) = strategy.report();

        vm.stopBroadcast();

        console2.log("\nReport complete!");
        console2.log("  Profit:", profit);
        console2.log("  Loss:", loss);
        console2.log("  New Total Assets:", strategy.totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOY FUNDS OPERATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy idle USDC to Kalani vault
     * @param amount Amount to deploy (6 decimals)
     */
    function deployFunds(uint256 amount) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\n[DEPLOY FUNDS] Deploying", amount, "USDC to Kalani");
        console2.log("Caller:", deployer);

        // Get management address
        address management = strategy.management();
        console2.log("Strategy management:", management);

        if (deployer != management) {
            console2.log("WARNING: You are not the management!");
            console2.log("deployFunds may fail");
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy funds (this is a low-level call since deployFunds may not be in interface)
        (bool success, ) = strategyAddress.call(
            abi.encodeWithSignature("deployFunds(uint256)", amount)
        );
        require(success, "deployFunds failed");

        vm.stopBroadcast();

        console2.log("\nFunds deployed to Kalani!");
        console2.log("New total assets:", strategy.totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                        FREE FUNDS OPERATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw USDC from Kalani to idle
     * @param amount Amount to withdraw from Kalani (6 decimals)
     */
    function freeFunds(uint256 amount) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("\n[FREE FUNDS] Withdrawing", amount, "USDC from Kalani");
        console2.log("Caller:", deployer);

        address management = strategy.management();
        console2.log("Strategy management:", management);

        if (deployer != management) {
            console2.log("WARNING: You are not the management!");
            console2.log("freeFunds may fail");
        }

        vm.startBroadcast(deployerPrivateKey);

        // Free funds
        (bool success, ) = strategyAddress.call(
            abi.encodeWithSignature("freeFunds(uint256)", amount)
        );
        require(success, "freeFunds failed");

        vm.stopBroadcast();

        console2.log("\nFunds freed from Kalani!");
        console2.log("New total assets:", strategy.totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                        STATUS VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice View strategy status (read-only)
     */
    function status() public view {
        console2.log("\n==============================================");
        console2.log("STRATEGY STATUS");
        console2.log("==============================================");

        // Basic info
        console2.log("Strategy:", strategyAddress);
        console2.log("Asset (USDC):", address(strategy.asset()));

        // Roles
        console2.log("\nRoles:");
        console2.log("  Management:", strategy.management());
        console2.log("  Keeper:", strategy.keeper());
        console2.log("  Emergency Admin:", strategy.emergencyAdmin());

        // Get yield source using low-level call
        (bool success, bytes memory data) = strategyAddress.staticcall(
            abi.encodeWithSignature("yieldSource()")
        );
        if (success) {
            address yieldSource = abi.decode(data, (address));
            console2.log("  Yield Source (Kalani):", yieldSource);
        }

        // Get dragon router
        (success, data) = strategyAddress.staticcall(
            abi.encodeWithSignature("dragonRouter()")
        );
        if (success) {
            address router = abi.decode(data, (address));
            console2.log("  Dragon Router:", router);
        }

        // Assets
        console2.log("\nAssets:");
        console2.log("  Total Assets:", strategy.totalAssets());
        console2.log("  Total Supply (shares):", strategy.totalSupply());

        // Get deployed amount
        (success, data) = strategyAddress.staticcall(
            abi.encodeWithSignature("deployedAmount()")
        );
        if (success) {
            uint256 deployed = abi.decode(data, (uint256));
            console2.log("  Deployed to Kalani:", deployed);
            uint256 idle = strategy.totalAssets() - deployed;
            console2.log("  Idle USDC:", idle);
        }

        // State
        console2.log("\nState:");
        console2.log("  Is Shutdown:", strategy.isShutdown());

        // Vault health
        (success, data) = strategyAddress.staticcall(
            abi.encodeWithSignature("getVaultHealth()")
        );
        if (success) {
            (bool isPaused, uint256 failures, uint256 lastFailure) = abi.decode(
                data,
                (bool, uint256, uint256)
            );
            console2.log("  Vault Paused:", isPaused);
            console2.log("  Consecutive Failures:", failures);
            console2.log("  Last Failure:", lastFailure);
        }

        console2.log("==============================================");
    }
}

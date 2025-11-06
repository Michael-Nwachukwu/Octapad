// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, ERC20, IStrategyInterface, ITokenizedStrategy} from "./YieldDonatingSetup.sol";

/**
 * @title YieldDonatingOperationTest
 * @notice Comprehensive fork tests for YieldDonating strategy operations with Kalani vault
 */
contract YieldDonatingOperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(ITokenizedStrategy(address(strategy)).dragonRouter(), dragonRouter);
        assertEq(strategy.keeper(), keeper);
        // Check enableBurning using low-level call since it's not in the interface
        (bool success, bytes memory data) = address(strategy).staticcall(abi.encodeWithSignature("enableBurning()"));
        require(success, "enableBurning call failed");
        bool currentEnableBurning = abi.decode(data, (bool));
        assertEq(currentEnableBurning, enableBurning);
    }

    function test_profitableReport(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint256 _timeInDays = 30; // Fixed 30 days

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Move forward in time to simulate yield accrual period
        uint256 timeElapsed = _timeInDays * 1 days;
        skip(timeElapsed);

        // Report profit - should detect the simulated yield
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values - should have profit equal to simulated yield
        assertGt(profit, 0, "!profit should equal expected yield");
        assertEq(loss, 0, "!loss should be 0");

        // Check that profit was minted to dragon router
        uint256 dragonRouterShares = strategy.balanceOf(dragonRouter);
        assertGt(dragonRouterShares, 0, "!dragon router shares");

        // Convert shares back to assets to verify
        uint256 dragonRouterAssets = strategy.convertToAssets(dragonRouterShares);
        assertEq(dragonRouterAssets, profit, "!dragon router assets should equal profit");

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds (user gets original amount, dragon router gets the yield)
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        // Assert that dragon router still has shares (the yield portion)
        uint256 dragonRouterSharesAfter = strategy.balanceOf(dragonRouter);
        assertGt(dragonRouterSharesAfter, 0, "!dragon router shares after withdrawal");
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(30 days);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger);
    }

    // ============================================
    // ADDITIONAL COMPREHENSIVE TESTS
    // ============================================

    function test_depositAndWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Check total assets
        assertEq(strategy.totalAssets(), _amount, "!totalAssets after deposit");

        // Check user shares
        assertEq(strategy.balanceOf(user), _amount, "!user shares");

        // Withdraw all
        uint256 balanceBefore = asset.balanceOf(user);
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Check final balance
        assertEq(asset.balanceOf(user), balanceBefore + _amount, "!final balance after withdrawal");
    }

    function test_multipleDeposits(uint256 _amount1, uint256 _amount2) public {
        vm.assume(_amount1 > minFuzzAmount && _amount1 < maxFuzzAmount / 2);
        vm.assume(_amount2 > minFuzzAmount && _amount2 < maxFuzzAmount / 2);

        address user2 = address(20);

        // First deposit
        mintAndDepositIntoStrategy(strategy, user, _amount1);
        assertEq(strategy.balanceOf(user), _amount1, "!user1 shares");

        // Second deposit
        mintAndDepositIntoStrategy(strategy, user2, _amount2);
        assertEq(strategy.balanceOf(user2), _amount2, "!user2 shares");

        // Check total assets
        assertEq(strategy.totalAssets(), _amount1 + _amount2, "!total assets");
    }

    function test_profitableReportWithYieldSimulation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Simulate yield accrual (5% yield) by airdropping to vault
        uint256 vaultYield = (_amount * 5) / 100;
        simulateYieldAccrual(vaultYield);

        // Skip time
        skip(1 days);

        // Report profit
        (uint256 profit, uint256 loss) = report();

        // Check profit and loss
        assertGt(profit, 0, "!profit should be greater than 0");
        assertEq(loss, 0, "!loss should be 0");

        // Check that profit was minted to dragon router
        uint256 dragonRouterShares = strategy.balanceOf(dragonRouter);
        assertGt(dragonRouterShares, 0, "!dragon router shares");

        // Convert shares back to assets to verify
        uint256 dragonRouterAssets = strategy.convertToAssets(dragonRouterShares);
        assertApproxEq(dragonRouterAssets, profit, "!dragon router assets should equal profit");
    }

    function test_multipleReportsAccumulateProfit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // First report with yield
        uint256 vaultYield1 = (_amount * 2) / 100;
        simulateYieldAccrual(vaultYield1);
        skip(7 days);
        (uint256 profit1, ) = report();
        assertGt(profit1, 0, "!profit1");

        // Second report with more yield
        uint256 totalAssets1 = strategy.totalAssets();
        uint256 vaultYield2 = (totalAssets1 * 3) / 100;
        simulateYieldAccrual(vaultYield2);
        skip(7 days);
        (uint256 profit2, ) = report();
        assertGt(profit2, 0, "!profit2");

        // Check dragon router accumulated shares
        uint256 dragonRouterShares = strategy.balanceOf(dragonRouter);
        uint256 dragonRouterAssets = strategy.convertToAssets(dragonRouterShares);
        assertGt(dragonRouterAssets, profit1, "!dragon router should have accumulated profits");
    }

    function test_tendDeploysIdleFunds(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit - funds are auto-deployed on deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Get asset breakdown - funds should already be in vault
        (uint256 vaultBefore, uint256 idleBefore, ) = getAssetBreakdown();

        // Funds are auto-deployed on deposit, so vault should have funds
        assertGt(vaultBefore, 0, "!vault should have funds after deposit");
        assertEq(idleBefore, 0, "!idle should be 0 after auto-deployment");

        // Airdrop some additional funds to create idle balance
        uint256 additionalFunds = _amount / 10; // 10% more
        airdrop(asset, address(strategy), additionalFunds);

        // Check we have idle funds now
        (, uint256 idleAfter, ) = getAssetBreakdown();
        assertEq(idleAfter, additionalFunds, "!idle should equal additional funds");

        // Call tend to deploy idle funds
        tend();

        // Get asset breakdown after tend
        (uint256 vaultAfterTend, uint256 idleAfterTend, ) = getAssetBreakdown();

        // Idle should be reduced (deployed to vault)
        assertLt(idleAfterTend, idleAfter, "!idle should be less after tend");
        assertGt(vaultAfterTend, vaultBefore, "!vault should have more funds after tend");
    }

    function test_assetBreakdown(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Check initial breakdown
        (uint256 vaultAssets, uint256 idleAssets, uint256 totalAssets) = getAssetBreakdown();
        assertEq(vaultAssets, 0, "!vault should be empty");
        assertEq(idleAssets, 0, "!idle should be empty");
        assertEq(totalAssets, 0, "!total should be empty");

        // Deposit and check breakdown
        mintAndDepositIntoStrategy(strategy, user, _amount);
        (vaultAssets, idleAssets, totalAssets) = getAssetBreakdown();

        assertEq(totalAssets, _amount, "!total should equal deposit");
        assertEq(vaultAssets + idleAssets, totalAssets, "!vault + idle should equal total");
    }

    function test_vaultHealthInitialState() public {
        (bool isPaused, uint256 failures, uint256 lastFailure) = checkVaultHealth();

        assertFalse(isPaused, "!vault should not be paused initially");
        assertEq(failures, 0, "!failures should be 0 initially");
        assertEq(lastFailure, 0, "!lastFailure should be 0 initially");
    }

    function test_depositLimit() public {
        uint256 maxDeposit = getMaxDeposit();
        // Should have some deposit capacity
        assertGt(maxDeposit, 0, "!max deposit should be greater than 0");
    }

    function test_withdrawLimit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Initially, withdraw limit should be 0
        uint256 withdrawLimit = getMaxWithdraw();
        assertEq(withdrawLimit, 0, "!initial withdraw limit should be 0");

        // After deposit, should have withdraw capacity
        mintAndDepositIntoStrategy(strategy, user, _amount);
        withdrawLimit = getMaxWithdraw();
        assertGe(withdrawLimit, _amount, "!withdraw limit should be >= deposit amount");
    }

    function test_changeDragonRouter(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        address newDragonRouter = address(999);

        // Deposit and generate profit
        mintAndDepositIntoStrategy(strategy, user, _amount);
        uint256 vaultYield = (_amount * 5) / 100;
        simulateYieldAccrual(vaultYield);
        skip(1 days);
        report();

        // Check old dragon router has shares
        uint256 oldDragonShares = strategy.balanceOf(dragonRouter);
        assertGt(oldDragonShares, 0, "!old dragon should have shares");

        // Change dragon router
        setDragonRouter(newDragonRouter);

        // Verify change
        assertEq(ITokenizedStrategy(address(strategy)).dragonRouter(), newDragonRouter, "!dragon router not changed");

        // Generate more profit
        vaultYield = (_amount * 3) / 100;
        simulateYieldAccrual(vaultYield);
        skip(1 days);
        (uint256 profit2, ) = report();
        assertGt(profit2, 0, "!profit2");

        // New dragon router should receive new profits
        uint256 newDragonShares = strategy.balanceOf(newDragonRouter);
        assertGt(newDragonShares, 0, "!new dragon should have shares");

        // Old dragon router should still have old shares
        assertEq(strategy.balanceOf(dragonRouter), oldDragonShares, "!old dragon shares should remain");
    }

    function test_reportWithNoYield(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Report without yield
        skip(1 days);
        (uint256 profit, uint256 loss) = report();

        // Should have no profit or loss
        assertEq(profit, 0, "!profit should be 0");
        assertEq(loss, 0, "!loss should be 0");
    }
}

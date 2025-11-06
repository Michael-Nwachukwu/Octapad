// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, ERC20, IStrategyInterface} from "./YieldDonatingSetup.sol";

/**
 * @title YieldDonatingShutdownTest
 * @notice Tests for emergency shutdown and withdrawal functionality
 */
contract YieldDonatingShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(30 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_emergencyWithdraw_maxUint(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(30 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // should be able to pass uint 256 max and not revert.
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_emergencyWithdrawWithVaultFunds(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Deploy funds to vault using report
        vm.prank(keeper);
        strategy.report();

        // Verify funds are in vault
        (uint256 vaultAssets, , ) = getAssetBreakdown();
        assertGt(vaultAssets, 0, "!vault should have funds");

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Emergency withdraw should pull from vault
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(_amount);

        // User can still withdraw
        uint256 balanceBefore = asset.balanceOf(user);
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    function test_reportAfterShutdownReturnsZero(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Reporting after shutdown is allowed but returns (0, 0)
        // This is TokenizedStrategy behavior - not a revert
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0, "!profit should be 0 after shutdown");
        assertEq(loss, 0, "!loss should be 0 after shutdown");
    }

    function test_cannotDepositAfterShutdown(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Depositing should revert after shutdown
        airdrop(asset, user, _amount);
        vm.prank(user);
        asset.approve(address(strategy), _amount);

        vm.prank(user);
        vm.expectRevert();
        strategy.deposit(_amount, user);
    }

    function test_multipleUsersWithdrawAfterShutdown(uint256 _amount1, uint256 _amount2) public {
        vm.assume(_amount1 > minFuzzAmount && _amount1 < maxFuzzAmount / 2);
        vm.assume(_amount2 > minFuzzAmount && _amount2 < maxFuzzAmount / 2);

        address user2 = address(20);

        // Multiple users deposit
        mintAndDepositIntoStrategy(strategy, user, _amount1);
        mintAndDepositIntoStrategy(strategy, user2, _amount2);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Both users can withdraw
        uint256 balanceBefore1 = asset.balanceOf(user);
        vm.prank(user);
        strategy.redeem(_amount1, user, user);
        assertGe(asset.balanceOf(user), balanceBefore1 + _amount1, "!user1 final balance");

        uint256 balanceBefore2 = asset.balanceOf(user2);
        vm.prank(user2);
        strategy.redeem(_amount2, user2, user2);
        assertGe(asset.balanceOf(user2), balanceBefore2 + _amount2, "!user2 final balance");
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {YieldDonatingStrategy as Strategy, ERC20} from "../../strategies/yieldDonating/YieldDonatingStrategy.sol";
import {YieldDonatingStrategyFactory as StrategyFactory} from "../../strategies/yieldDonating/YieldDonatingStrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

// Interface for yield source (ERC4626 vault)
interface IYieldSource {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

/**
 * @title YieldDonatingSetup
 * @notice Base test setup for YieldDonating strategy with Kalani vault
 */
contract YieldDonatingSetup is Test, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    StrategyFactory public strategyFactory;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public dragonRouter = address(3); // This is the donation address
    address public emergencyAdmin = address(5);

    // YieldDonating specific variables
    bool public enableBurning = true;
    address public tokenizedStrategyAddress;
    address public yieldSource; // Kalani vault

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $10 of 1e6 stable coins up to 1,000,000 of the asset
    // Note: Kalani vault may have minimum deposit requirements, so we start at $10
    uint256 public maxFuzzAmount;
    uint256 public minFuzzAmount = 10e6; // $10 USDC minimum

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        // Read configuration from environment or use defaults for Base network
        address testAssetAddress = vm.envOr("TEST_ASSET_ADDRESS", address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)); // USDC on Base
        address testYieldSource = vm.envOr("TEST_YIELD_SOURCE", address(0x7ea9FAC329636f532aE29E1c9EC9A964337bDA24)); // Kalani vault on Base

        require(testAssetAddress != address(0), "TEST_ASSET_ADDRESS not set");
        require(testYieldSource != address(0), "TEST_YIELD_SOURCE not set");

        // Set asset
        asset = ERC20(testAssetAddress);

        // Set decimals
        decimals = asset.decimals();

        // Set max fuzz amount to 1,000,000 of the asset
        maxFuzzAmount = 1_000_000 * 10 ** decimals;

        // Set yield source (Kalani vault)
        yieldSource = testYieldSource;

        // Deploy YieldDonatingTokenizedStrategy implementation
        tokenizedStrategyAddress = address(new YieldDonatingTokenizedStrategy());

        strategyFactory = new StrategyFactory(management, dragonRouter, keeper, emergencyAdmin);

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(dragonRouter, "dragonRouter");
        vm.label(yieldSource, "kalaniVault");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new Strategy(
                    yieldSource,
                    address(asset),
                    "Kalani USDC YieldDonating Strategy",
                    management,
                    keeper,
                    emergencyAdmin,
                    dragonRouter, // Use dragonRouter as the donation address
                    enableBurning,
                    tokenizedStrategyAddress
                )
            )
        );

        return address(_strategy);
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public view {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setDragonRouter(address _newDragonRouter) public {
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setDragonRouter(_newDragonRouter);

        // Fast forward to bypass cooldown
        skip(7 days);

        // Anyone can finalize after cooldown
        ITokenizedStrategy(address(strategy)).finalizeDragonRouterChange();
    }

    function setEnableBurning(bool _enableBurning) public {
        vm.prank(management);
        // Call using low-level call since setEnableBurning may not be in all interfaces
        (bool success, ) = address(strategy).call(abi.encodeWithSignature("setEnableBurning(bool)", _enableBurning));
        require(success, "setEnableBurning failed");
    }

    /**
     * @notice Gets detailed asset breakdown from strategy
     * @return vault Assets in vault
     * @return idle Idle assets
     * @return total Total assets
     */
    function getAssetBreakdown() public view returns (uint256 vault, uint256 idle, uint256 total) {
        (bool success, bytes memory data) = address(strategy).staticcall(abi.encodeWithSignature("getAssetBreakdown()"));
        if (success && data.length > 0) {
            return abi.decode(data, (uint256, uint256, uint256));
        }
        // Fallback: calculate manually
        vault = strategy.totalAssets() - asset.balanceOf(address(strategy));
        idle = asset.balanceOf(address(strategy));
        total = strategy.totalAssets();
    }

    /**
     * @notice Triggers report as keeper
     * @return profit Reported profit
     * @return loss Reported loss
     */
    function report() public returns (uint256 profit, uint256 loss) {
        vm.prank(keeper);
        return strategy.report();
    }

    /**
     * @notice Triggers tend as keeper
     */
    function tend() public {
        vm.prank(keeper);
        strategy.tend();
    }

    /**
     * @notice Simulates time passing
     * @param _seconds Seconds to skip
     */
    function skipTime(uint256 _seconds) public {
        skip(_seconds);
    }

    /**
     * @notice Simulates yield accrual for ERC4626 vault
     * @dev ERC4626 vaults calculate share price as totalAssets / totalShares
     *      Simply airdropping doesn't work because the vault needs to update internal state.
     *
     *      To properly simulate yield on a real Kalani vault fork:
     *      1. Airdrop assets to the vault
     *      2. Make a deposit/withdraw cycle to force the vault to update its state
     *
     *      Note: This may not work perfectly with all ERC4626 implementations.
     *      Some vaults have yield distribution mechanisms that require time or specific actions.
     *
     * @param _vaultYield Yield to add to vault
     */
    function simulateYieldAccrual(uint256 _vaultYield) public {
        if (_vaultYield == 0) return;

        // Airdrop to vault
        airdrop(asset, yieldSource, _vaultYield);

        // For real Kalani vault, we need to trigger a state update
        // Try depositing and immediately withdrawing a tiny amount to force accounting update
        // This simulates a transaction that would trigger the vault's internal accounting
        uint256 tinyAmount = 1e6; // $1

        // Mint tiny amount to strategy for the cycle
        airdrop(asset, address(strategy), tinyAmount);

        // Prank as strategy to approve and deposit/withdraw
        vm.startPrank(address(strategy));

        // Approve vault
        asset.approve(yieldSource, tinyAmount);

        // Try to deposit and withdraw to trigger state update
        try IYieldSource(yieldSource).deposit(tinyAmount, address(strategy)) returns (uint256 shares) {
            // Immediately withdraw to return to original state
            try IYieldSource(yieldSource).redeem(shares, address(strategy), address(strategy)) {
                // Success - vault state updated
            } catch {
                // If redeem fails, vault might have the funds
            }
        } catch {
            // If deposit fails, vault might not accept deposits
            // Just leave the airdropped funds there
        }

        vm.stopPrank();
    }

    /**
     * @notice Checks vault health status
     * @return isPaused Vault paused status
     * @return failures Consecutive failures
     * @return lastFailure Last failure timestamp
     */
    function checkVaultHealth() public view returns (bool isPaused, uint256 failures, uint256 lastFailure) {
        (bool success, bytes memory data) = address(strategy).staticcall(abi.encodeWithSignature("getVaultHealth()"));
        if (success && data.length > 0) {
            return abi.decode(data, (bool, uint256, uint256));
        }
        return (false, 0, 0);
    }

    /**
     * @notice Asserts approximate equality (within 0.01%)
     * @param a First value
     * @param b Second value
     * @param message Error message
     */
    function assertApproxEq(uint256 a, uint256 b, string memory message) public pure {
        uint256 delta = a > b ? a - b : b - a;
        uint256 tolerance = (a * 1) / 10000; // 0.01% tolerance
        require(delta <= tolerance, message);
    }

    /**
     * @notice Gets maximum deposit limit
     * @return Maximum deposit amount
     */
    function getMaxDeposit() public view returns (uint256) {
        return strategy.availableDepositLimit(address(0));
    }

    /**
     * @notice Gets maximum withdrawal limit
     * @return Maximum withdrawal amount
     */
    function getMaxWithdraw() public view returns (uint256) {
        return strategy.availableWithdrawLimit(address(0));
    }
}

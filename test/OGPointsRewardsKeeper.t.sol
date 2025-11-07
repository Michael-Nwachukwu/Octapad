// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.11.0/src/Test.sol";
import {console} from "forge-std-1.11.0/src/console.sol";
import {OGPointsRewardsKeeper} from "../src/launchpad/OGPointsRewardsKeeper.sol";

// Mock OGPointsRewards for testing
contract MockOGPointsRewards {
    uint256 public claimableShares;
    uint256 public heldShares;
    bool public shouldRevert;
    uint256 public claimCount;

    function setClaimableShares(uint256 _claimableShares) external {
        claimableShares = _claimableShares;
    }

    function setHeldShares(uint256 _heldShares) external {
        heldShares = _heldShares;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function getClaimableShares() external view returns (uint256) {
        return claimableShares;
    }

    function getHeldShares() external view returns (uint256) {
        return heldShares;
    }

    function claimAndRedeemFromSplitter() external {
        if (shouldRevert) {
            revert("Mock revert");
        }
        claimCount++;
        claimableShares = 0; // Simulate successful claim
    }
}

contract OGPointsRewardsKeeperTest is Test {
    OGPointsRewardsKeeper public keeper;
    MockOGPointsRewards public mockRewards;

    uint256 public constant MIN_HARVEST = 1e18; // 1 share minimum

    address public caller = address(0x1);

    event HarvestTriggered(address indexed caller, uint256 sharesClaimable);

    function setUp() public {
        mockRewards = new MockOGPointsRewards();
        keeper = new OGPointsRewardsKeeper(address(mockRewards), MIN_HARVEST);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment() public {
        assertEq(address(keeper.ogPointsRewards()), address(mockRewards));
        assertEq(keeper.minHarvestAmount(), MIN_HARVEST);
    }

    function testRevert_DeploymentZeroAddress() public {
        vm.expectRevert("OGPointsRewardsKeeper: zero address");
        new OGPointsRewardsKeeper(address(0), MIN_HARVEST);
    }

    /*//////////////////////////////////////////////////////////////
                        SHOULD HARVEST TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ShouldHarvestTrue() public {
        // Set claimable shares above minimum
        mockRewards.setClaimableShares(MIN_HARVEST);

        assertTrue(keeper.shouldHarvest());
    }

    function test_ShouldHarvestFalse() public {
        // Set claimable shares below minimum
        mockRewards.setClaimableShares(MIN_HARVEST - 1);

        assertFalse(keeper.shouldHarvest());
    }

    function test_ShouldHarvestExactlyAtThreshold() public {
        mockRewards.setClaimableShares(MIN_HARVEST);

        assertTrue(keeper.shouldHarvest());
    }

    function test_ShouldHarvestZeroShares() public {
        mockRewards.setClaimableShares(0);

        assertFalse(keeper.shouldHarvest());
    }

    function test_ShouldHarvestLargeAmount() public {
        mockRewards.setClaimableShares(1000e18);

        assertTrue(keeper.shouldHarvest());
    }

    /*//////////////////////////////////////////////////////////////
                    HARVEST AND DISTRIBUTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_HarvestAndDistribute() public {
        // Setup: claimable shares above threshold
        mockRewards.setClaimableShares(10e18);

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit HarvestTriggered(caller, 10e18);

        // Call harvest
        vm.prank(caller);
        bool success = keeper.harvestAndDistribute();

        assertTrue(success);
        assertEq(mockRewards.claimCount(), 1);
    }

    function test_HarvestAndDistributeMultipleTimes() public {
        // First harvest
        mockRewards.setClaimableShares(10e18);
        vm.prank(caller);
        keeper.harvestAndDistribute();

        assertEq(mockRewards.claimCount(), 1);

        // Second harvest
        mockRewards.setClaimableShares(20e18);
        vm.prank(caller);
        keeper.harvestAndDistribute();

        assertEq(mockRewards.claimCount(), 2);
    }

    function test_HarvestAndDistributeWhenBelowThreshold() public {
        // Setup: claimable shares below threshold
        mockRewards.setClaimableShares(MIN_HARVEST - 1);

        // Should return false and not harvest
        vm.prank(caller);
        bool success = keeper.harvestAndDistribute();

        assertFalse(success);
        assertEq(mockRewards.claimCount(), 0);
    }

    function testRevert_HarvestAndDistributeFails() public {
        mockRewards.setClaimableShares(10e18);
        mockRewards.setShouldRevert(true);

        vm.prank(caller);
        vm.expectRevert("OGPointsRewardsKeeper: harvest failed");
        keeper.harvestAndDistribute();
    }

    function test_HarvestAndDistributePermissionless() public {
        mockRewards.setClaimableShares(10e18);

        // Anyone can call
        address randomCaller = address(0x999);
        vm.prank(randomCaller);
        bool success = keeper.harvestAndDistribute();

        assertTrue(success);
        assertEq(mockRewards.claimCount(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                    CHAINLINK AUTOMATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CheckUpkeepTrue() public {
        mockRewards.setClaimableShares(10e18);

        (bool upkeepNeeded, bytes memory performData) = keeper.checkUpkeep("");

        assertTrue(upkeepNeeded);
        assertEq(performData.length, 0);
    }

    function test_CheckUpkeepFalse() public {
        mockRewards.setClaimableShares(MIN_HARVEST - 1);

        (bool upkeepNeeded, ) = keeper.checkUpkeep("");

        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeepWithData() public {
        mockRewards.setClaimableShares(10e18);

        // Check upkeep with arbitrary data (should be ignored)
        (bool upkeepNeeded, ) = keeper.checkUpkeep(hex"1234567890");

        assertTrue(upkeepNeeded);
    }

    function testRevert_PerformUpkeepWhenNotNeeded() public {
        mockRewards.setClaimableShares(MIN_HARVEST - 1);

        vm.expectRevert("OGPointsRewardsKeeper: upkeep not needed");
        keeper.performUpkeep("");
    }

    function test_PerformUpkeepWithData() public {
        mockRewards.setClaimableShares(10e18);

        // Perform upkeep with arbitrary data (should be ignored)
        keeper.performUpkeep(hex"1234567890");

        assertEq(mockRewards.claimCount(), 1);
    }

    function test_ChainlinkAutomationFlow() public {
        mockRewards.setClaimableShares(10e18);

        // 1. Check if upkeep is needed
        (bool upkeepNeeded, bytes memory performData) = keeper.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // 2. Perform upkeep
        keeper.performUpkeep(performData);

        assertEq(mockRewards.claimCount(), 1);

        // 3. Check again (should be false now)
        mockRewards.setClaimableShares(0);
        (upkeepNeeded, ) = keeper.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetClaimableShares() public {
        mockRewards.setClaimableShares(123e18);

        uint256 claimable = keeper.getClaimableShares();

        assertEq(claimable, 123e18);
    }

    function test_GetHeldShares() public {
        mockRewards.setHeldShares(456e18);

        uint256 held = keeper.getHeldShares();

        assertEq(held, 456e18);
    }

    function test_GetKeeperStats() public {
        mockRewards.setClaimableShares(10e18);
        mockRewards.setHeldShares(5e18);

        (
            uint256 claimable,
            uint256 held,
            bool shouldTrigger,
            uint256 minAmount
        ) = keeper.getKeeperStats();

        assertEq(claimable, 10e18);
        assertEq(held, 5e18);
        assertTrue(shouldTrigger);
        assertEq(minAmount, MIN_HARVEST);
    }

    function test_GetKeeperStatsBelowThreshold() public {
        mockRewards.setClaimableShares(MIN_HARVEST - 1);
        mockRewards.setHeldShares(0);

        (
            uint256 claimable,
            uint256 held,
            bool shouldTrigger,
            uint256 minAmount
        ) = keeper.getKeeperStats();

        assertEq(claimable, MIN_HARVEST - 1);
        assertEq(held, 0);
        assertFalse(shouldTrigger);
        assertEq(minAmount, MIN_HARVEST);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RealisticKeeperScenario() public {
        // 1. Start with no claimable shares
        mockRewards.setClaimableShares(0);
        assertFalse(keeper.shouldHarvest());

        // 2. Shares accumulate but still below threshold
        mockRewards.setClaimableShares(0.5e18);
        assertFalse(keeper.shouldHarvest());

        // 3. Shares reach threshold
        mockRewards.setClaimableShares(MIN_HARVEST);
        assertTrue(keeper.shouldHarvest());

        // 4. Keeper triggers harvest
        vm.prank(caller);
        bool success = keeper.harvestAndDistribute();
        assertTrue(success);

        // 5. Shares now at 0 (claimed)
        assertFalse(keeper.shouldHarvest());

        // 6. More shares accumulate
        mockRewards.setClaimableShares(5e18);
        assertTrue(keeper.shouldHarvest());

        // 7. Another harvest
        vm.prank(caller);
        keeper.harvestAndDistribute();

        assertEq(mockRewards.claimCount(), 2);
    }

    function test_MultipleKeepersCompeting() public {
        mockRewards.setClaimableShares(10e18);

        address keeper1 = address(0x1);
        address keeper2 = address(0x2);
        address keeper3 = address(0x3);

        // All keepers check and see upkeep needed
        assertTrue(keeper.shouldHarvest());

        // First keeper harvests
        vm.prank(keeper1);
        keeper.harvestAndDistribute();

        // Shares now 0
        mockRewards.setClaimableShares(0);

        // Other keepers should see no upkeep needed
        assertFalse(keeper.shouldHarvest());

        // They try to harvest but return false
        vm.prank(keeper2);
        bool success2 = keeper.harvestAndDistribute();
        assertFalse(success2);

        vm.prank(keeper3);
        bool success3 = keeper.harvestAndDistribute();
        assertFalse(success3);

        // Only one harvest happened
        assertEq(mockRewards.claimCount(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ShouldHarvest(uint256 claimableAmount) public {
        mockRewards.setClaimableShares(claimableAmount);

        bool shouldHarvest = keeper.shouldHarvest();

        if (claimableAmount >= MIN_HARVEST) {
            assertTrue(shouldHarvest);
        } else {
            assertFalse(shouldHarvest);
        }
    }

    function testFuzz_HarvestAndDistribute(uint128 claimableAmount) public {
        vm.assume(claimableAmount >= MIN_HARVEST);

        mockRewards.setClaimableShares(claimableAmount);

        vm.prank(caller);
        bool success = keeper.harvestAndDistribute();

        assertTrue(success);
        assertEq(mockRewards.claimCount(), 1);
    }

    function testFuzz_MultipleHarvests(uint8 numHarvests) public {
        vm.assume(numHarvests > 0 && numHarvests <= 50);

        for (uint256 i = 0; i < numHarvests; i++) {
            mockRewards.setClaimableShares(MIN_HARVEST * (i + 1));

            vm.prank(caller);
            keeper.harvestAndDistribute();
        }

        assertEq(mockRewards.claimCount(), numHarvests);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_HarvestAtExactThreshold() public {
        mockRewards.setClaimableShares(MIN_HARVEST);

        assertTrue(keeper.shouldHarvest());

        vm.prank(caller);
        bool success = keeper.harvestAndDistribute();

        assertTrue(success);
    }

    function test_HarvestJustBelowThreshold() public {
        mockRewards.setClaimableShares(MIN_HARVEST - 1);

        assertFalse(keeper.shouldHarvest());

        vm.prank(caller);
        bool success = keeper.harvestAndDistribute();

        assertFalse(success);
        assertEq(mockRewards.claimCount(), 0);
    }

    function test_HarvestWithZeroMinimum() public {
        // Deploy keeper with 0 minimum
        OGPointsRewardsKeeper zeroMinKeeper = new OGPointsRewardsKeeper(
            address(mockRewards),
            0
        );

        // Even 1 wei should trigger harvest
        mockRewards.setClaimableShares(1);

        assertTrue(zeroMinKeeper.shouldHarvest());
    }

    function test_HarvestWithVeryLargeMinimum() public {
        // Deploy keeper with very large minimum
        uint256 largeMin = 1000000e18;
        OGPointsRewardsKeeper largeMinKeeper = new OGPointsRewardsKeeper(
            address(mockRewards),
            largeMin
        );

        mockRewards.setClaimableShares(999999e18);

        assertFalse(largeMinKeeper.shouldHarvest());

        mockRewards.setClaimableShares(largeMin);

        assertTrue(largeMinKeeper.shouldHarvest());
    }

    function test_ContinuousHarvesting() public {
        // Simulate continuous accumulation and harvesting
        for (uint256 i = 0; i < 10; i++) {
            // Accumulate shares
            mockRewards.setClaimableShares(MIN_HARVEST * (i + 1));

            // Harvest when needed
            if (keeper.shouldHarvest()) {
                vm.prank(caller);
                keeper.harvestAndDistribute();

                // Reset for next iteration
                mockRewards.setClaimableShares(0);
            }
        }

        // Should have harvested 10 times
        assertEq(mockRewards.claimCount(), 10);
    }
}

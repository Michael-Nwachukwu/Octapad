// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title OGPointsRewardsKeeper
 * @notice Automation contract for harvesting and distributing OG Points rewards
 * @dev Can be called by anyone, or integrated with Chainlink Automation / Gelato
 *
 * Key Features:
 * - Checks if rewards are claimable from PaymentSplitter
 * - Triggers claim and redemption process
 * - Permissionless (anyone can call)
 * - Gas efficient view functions for automation upkeep
 */
contract OGPointsRewardsKeeper {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice OGPointsRewards contract
    address public immutable ogPointsRewards;

    /// @notice Minimum shares to trigger harvest (prevents dust harvests)
    uint256 public immutable minHarvestAmount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event HarvestTriggered(address indexed caller, uint256 sharesClaimable);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the keeper
     * @param _ogPointsRewards Address of OGPointsRewards contract
     * @param _minHarvestAmount Minimum shares to trigger harvest (e.g., 1e18 = 1 share)
     */
    constructor(address _ogPointsRewards, uint256 _minHarvestAmount) {
        require(_ogPointsRewards != address(0), "OGPointsRewardsKeeper: zero address");
        ogPointsRewards = _ogPointsRewards;
        minHarvestAmount = _minHarvestAmount;
    }

    /*//////////////////////////////////////////////////////////////
                            KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Trigger harvest if conditions are met
     * @dev Can be called by anyone
     * @return success Whether harvest was triggered
     */
    function harvestAndDistribute() external returns (bool success) {
        // Check if harvest should be triggered
        if (!shouldHarvest()) {
            return false;
        }

        // Get claimable amount for event
        uint256 claimable = getClaimableShares();

        // Trigger harvest
        (bool callSuccess, ) = ogPointsRewards.call(
            abi.encodeWithSignature("claimAndRedeemFromSplitter()")
        );

        require(callSuccess, "OGPointsRewardsKeeper: harvest failed");

        emit HarvestTriggered(msg.sender, claimable);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if harvest should be triggered
     * @dev Used by Chainlink Automation / Gelato Network
     * @return shouldTrigger Whether to trigger harvest
     */
    function shouldHarvest() public view returns (bool shouldTrigger) {
        uint256 claimable = getClaimableShares();
        return claimable >= minHarvestAmount;
    }

    /**
     * @notice Get claimable shares from PaymentSplitter
     * @return shares Amount of strategy shares claimable
     */
    function getClaimableShares() public view returns (uint256 shares) {
        (bool success, bytes memory data) = ogPointsRewards.staticcall(
            abi.encodeWithSignature("getClaimableShares()")
        );

        if (success) {
            shares = abi.decode(data, (uint256));
        }

        return shares;
    }

    /**
     * @notice Get held shares (already claimed but not redeemed)
     * @return shares Amount of strategy shares held by OGPointsRewards
     */
    function getHeldShares() public view returns (uint256 shares) {
        (bool success, bytes memory data) = ogPointsRewards.staticcall(
            abi.encodeWithSignature("getHeldShares()")
        );

        if (success) {
            shares = abi.decode(data, (uint256));
        }

        return shares;
    }

    /**
     * @notice Chainlink Automation compatible check function
     * @dev Returns upkeepNeeded and performData for Chainlink Automation
     * @return upkeepNeeded Whether upkeep is needed
     * @return performData Data to pass to performUpkeep (empty in our case)
     */
    function checkUpkeep(bytes calldata /* checkData */)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = shouldHarvest();
        performData = ""; // No data needed
    }

    /**
     * @notice Chainlink Automation compatible perform function
     * @dev Called by Chainlink Automation when upkeep is needed
     */
    function performUpkeep(bytes calldata /* performData */) external {
        require(shouldHarvest(), "OGPointsRewardsKeeper: upkeep not needed");

        (bool success, ) = ogPointsRewards.call(
            abi.encodeWithSignature("claimAndRedeemFromSplitter()")
        );

        require(success, "OGPointsRewardsKeeper: harvest failed");

        emit HarvestTriggered(msg.sender, getClaimableShares());
    }

    /**
     * @notice Get keeper statistics
     * @return claimable Claimable shares from PaymentSplitter
     * @return held Held shares in OGPointsRewards
     * @return shouldTrigger Whether harvest should be triggered
     * @return minAmount Minimum harvest amount threshold
     */
    function getKeeperStats()
        external
        view
        returns (
            uint256 claimable,
            uint256 held,
            bool shouldTrigger,
            uint256 minAmount
        )
    {
        return (
            getClaimableShares(),
            getHeldShares(),
            shouldHarvest(),
            minHarvestAmount
        );
    }
}

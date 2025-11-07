// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VestingManager
 * @notice Manages 3-month linear vesting for campaign creators
 * @dev Vested USDC is immediately deposited to YieldDonating Strategy to earn yield
 * Beneficiaries can claim their vested shares over time
 */
contract VestingManager {
    using SafeERC20 for IERC20;

    /// @notice Vesting schedule for a beneficiary
    struct Vesting {
        address beneficiary;     // Address of the campaign creator
        uint128 totalAmount;     // Total USDC amount vesting
        uint128 released;        // Amount already released
        uint64 startTime;        // Vesting start timestamp
        uint64 duration;         // Vesting duration in seconds
        bool revoked;            // Whether vesting was revoked
    }

    /// @notice USDC token on Base
    IERC20 public immutable usdc;

    /// @notice YieldDonating Strategy that receives released USDC
    address public yieldStrategy;

    /// @notice Address that can create vestings (OctaPad launchpad)
    address public immutable launchpad;

    /// @notice Mapping of vesting ID to vesting schedule
    mapping(uint256 => Vesting) public vestings;

    /// @notice Current vesting ID counter
    uint256 public vestingCount;

    /// @notice Mapping of beneficiary to their vesting IDs
    mapping(address => uint256[]) public beneficiaryVestings;

    event VestingCreated(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint128 amount,
        uint64 duration
    );

    event VestingReleased(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint128 amount,
        address strategy
    );

    event VestingRevoked(uint256 indexed vestingId);

    event YieldStrategyUpdated(address indexed oldStrategy, address indexed newStrategy);

    error Unauthorized();
    error InvalidAmount();
    error NothingToRelease();
    error AlreadyRevoked();

    /**
     * @notice Initialize vesting manager
     * @param launchpad_ Address of OctaPad launchpad
     * @param usdc_ Address of USDC token on Base
     * @param yieldStrategy_ Address of YieldDonating Strategy
     */
    constructor(address launchpad_, address usdc_, address yieldStrategy_) {
        require(launchpad_ != address(0), "VestingManager: zero launchpad");
        require(usdc_ != address(0), "VestingManager: zero usdc");
        require(yieldStrategy_ != address(0), "VestingManager: zero strategy");

        launchpad = launchpad_;
        usdc = IERC20(usdc_);
        yieldStrategy = yieldStrategy_;
    }

    /**
     * @notice Create a new vesting schedule
     * @param beneficiary Address of the campaign creator
     * @param amount Total USDC amount to vest
     * @param duration Vesting duration in seconds (90 days for campaigns)
     * @return vestingId ID of the created vesting schedule
     * @dev Only callable by launchpad contract
     */
    function createVesting(
        address beneficiary,
        uint128 amount,
        uint64 duration
    ) external returns (uint256 vestingId) {
        if (msg.sender != launchpad) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();
        require(beneficiary != address(0), "VestingManager: zero beneficiary");
        require(duration > 0, "VestingManager: zero duration");

        // Transfer USDC from launchpad to this contract
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Immediately deposit to YieldDonating Strategy to start earning yield
        usdc.forceApprove(yieldStrategy, amount);
        (bool success, ) = yieldStrategy.call(
            abi.encodeWithSignature("deposit(uint256,address)", uint256(amount), address(this))
        );
        require(success, "VestingManager: deposit failed");

        // Create vesting schedule
        vestingId = ++vestingCount;
        vestings[vestingId] = Vesting({
            beneficiary: beneficiary,
            totalAmount: amount,
            released: 0,
            startTime: uint64(block.timestamp),
            duration: duration,
            revoked: false
        });

        // Track vesting for beneficiary
        beneficiaryVestings[beneficiary].push(vestingId);

        emit VestingCreated(vestingId, beneficiary, amount, duration);

        return vestingId;
    }

    /**
     * @notice Release vested USDC to YieldDonating Strategy
     * @param vestingId ID of the vesting schedule
     * @dev Can be called by anyone (beneficiary, keeper, or anyone)
     * This allows for automated release via keepers
     */
    function release(uint256 vestingId) external {
        Vesting storage v = vestings[vestingId];
        require(!v.revoked, "VestingManager: revoked");

        uint128 releasable = _computeReleasable(v);
        if (releasable == 0) revert NothingToRelease();

        v.released += releasable;

        // Deposit released USDC to YieldDonating Strategy
        // Strategy will keep it idle if < $1, or deploy to Kalani if >= $1
        usdc.forceApprove(yieldStrategy, releasable);

        // Call deposit on strategy (assume it has deposit function)
        (bool success, ) = yieldStrategy.call(
            abi.encodeWithSignature(
                "deposit(uint256,address)",
                uint256(releasable),
                address(this)
            )
        );
        require(success, "VestingManager: deposit failed");

        emit VestingReleased(vestingId, v.beneficiary, releasable, yieldStrategy);
    }

    /**
     * @notice Batch release multiple vestings
     * @param vestingIds Array of vesting IDs to release
     * @dev Useful for keepers to release multiple vestings in one tx
     */
    function batchRelease(uint256[] calldata vestingIds) external {
        for (uint256 i = 0; i < vestingIds.length; i++) {
            // Use try-catch to continue even if one release fails
            try this.release(vestingIds[i]) {} catch {}
        }
    }

    /**
     * @notice Revoke a vesting schedule (emergency only)
     * @param vestingId ID of the vesting schedule
     * @dev Only callable by launchpad (for emergency situations)
     * Unreleased tokens stay in contract, can be recovered by launchpad
     */
    function revokeVesting(uint256 vestingId) external {
        if (msg.sender != launchpad) revert Unauthorized();

        Vesting storage v = vestings[vestingId];
        if (v.revoked) revert AlreadyRevoked();

        v.revoked = true;

        emit VestingRevoked(vestingId);
    }

    /**
     * @notice Update YieldDonating Strategy address
     * @param newStrategy New strategy address
     * @dev Only callable by launchpad
     */
    function setYieldStrategy(address newStrategy) external {
        if (msg.sender != launchpad) revert Unauthorized();
        require(newStrategy != address(0), "VestingManager: zero strategy");

        address oldStrategy = yieldStrategy;
        yieldStrategy = newStrategy;

        emit YieldStrategyUpdated(oldStrategy, newStrategy);
    }

    /**
     * @notice Compute releasable amount for a vesting schedule
     * @param v Vesting schedule
     * @return Releasable amount
     */
    function _computeReleasable(Vesting storage v) internal view returns (uint128) {
        uint256 elapsed = block.timestamp - v.startTime;

        // If vesting complete, return all unvested
        if (elapsed >= v.duration) {
            return v.totalAmount - v.released;
        }

        // Calculate vested amount based on elapsed time
        uint128 vested = uint128((uint256(v.totalAmount) * elapsed) / v.duration);

        // Return vested minus already released
        return vested - v.released;
    }

    /**
     * @notice Get releasable amount for a vesting schedule
     * @param vestingId ID of the vesting schedule
     * @return Releasable amount
     */
    function getReleasable(uint256 vestingId) external view returns (uint128) {
        Vesting storage v = vestings[vestingId];
        if (v.revoked) return 0;
        return _computeReleasable(v);
    }

    /**
     * @notice Get all vesting IDs for a beneficiary
     * @param beneficiary Address to query
     * @return Array of vesting IDs
     */
    function getBeneficiaryVestings(address beneficiary) external view returns (uint256[] memory) {
        return beneficiaryVestings[beneficiary];
    }

    /**
     * @notice Get vesting details
     * @param vestingId ID of the vesting schedule
     * @return beneficiary Address of the vesting beneficiary
     * @return totalAmount Total amount being vested
     * @return released Amount already released
     * @return startTime Vesting start timestamp
     * @return duration Duration of vesting period
     * @return revoked Whether vesting has been revoked
     * @return releasable Amount currently claimable
     */
    function getVesting(uint256 vestingId)
        external
        view
        returns (
            address beneficiary,
            uint128 totalAmount,
            uint128 released,
            uint64 startTime,
            uint64 duration,
            bool revoked,
            uint128 releasable
        )
    {
        Vesting storage v = vestings[vestingId];
        return (
            v.beneficiary,
            v.totalAmount,
            v.released,
            v.startTime,
            v.duration,
            v.revoked,
            v.revoked ? 0 : _computeReleasable(v)
        );
    }
}

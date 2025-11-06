// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/ERC20.sol";

/**
 * @title OGPointsToken
 * @notice Non-transferable ERC20 token for OG loyalty points
 * @dev Points are awarded for campaign participation and trading activity
 *
 * Key Features:
 * - Non-transferable (soulbound to address)
 * - Only authorized minters can mint (OctaPad, OGPointsHook)
 * - Holders can claim 50% of Kalani yield via OGPointsRewards contract
 * - Burning allowed (for point redemption mechanisms)
 * - Snapshot of balances for reward calculations
 *
 * Use Cases:
 * - Campaign sponsors: 10,000 points bank
 * - Token buyers: proportional points from campaign bank
 * - Traders: volume-based points from OGPointsHook
 * - Yield claimants: points → USDC rewards from Kalani yield
 *
 * Non-Transferable Design:
 * - Points represent loyalty/participation, not speculative assets
 * - Prevents gaming through wash trading
 * - Aligns incentives with long-term community building
 * - Can only be earned through legitimate activity
 */
contract OGPointsToken is ERC20 {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Admin address (can add/remove minters)
    address public admin;

    /// @notice Authorized minters (OctaPad, OGPointsHook, etc.)
    mapping(address => bool) public minters;

    /// @notice Whether token is non-transferable (immutable after construction)
    bool public immutable isNonTransferable;

    /// @notice Total points minted (for statistics)
    uint256 public totalMinted;

    /// @notice Total points burned (for statistics)
    uint256 public totalBurned;

    /// @notice Points minted per user (for statistics)
    mapping(address => uint256) public userMinted;

    /// @notice Points burned per user (for statistics)
    mapping(address => uint256) public userBurned;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event PointsMinted(address indexed to, uint256 amount, address indexed minter);
    event PointsBurned(address indexed from, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error TransferDisabled();
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory name_,
        string memory symbol_,
        address admin_,
        bool isNonTransferable_
    ) ERC20(name_, symbol_) {
        require(admin_ != address(0), "OGPointsToken: zero admin");

        admin = admin_;
        isNonTransferable = isNonTransferable_;
    }

    /*//////////////////////////////////////////////////////////////
                            MINTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint OG points to an address
     * @param to Recipient address
     * @param amount Amount of points to mint
     * @dev Only authorized minters can call
     */
    function mint(address to, uint256 amount) external {
        if (!minters[msg.sender]) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();

        _mint(to, amount);

        totalMinted += amount;
        userMinted[to] += amount;

        emit PointsMinted(to, amount, msg.sender);
    }

    /**
     * @notice Burn OG points from caller's balance
     * @param amount Amount of points to burn
     * @dev Anyone can burn their own points
     */
    function burn(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        _burn(msg.sender, amount);

        totalBurned += amount;
        userBurned[msg.sender] += amount;

        emit PointsBurned(msg.sender, amount);
    }

    /**
     * @notice Burn OG points from a specific address
     * @param from Address to burn from
     * @param amount Amount of points to burn
     * @dev Only authorized minters can burn from other addresses (for redemption mechanisms)
     */
    function burnFrom(address from, uint256 amount) external {
        if (!minters[msg.sender]) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();

        _burn(from, amount);

        totalBurned += amount;
        userBurned[from] += amount;

        emit PointsBurned(from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER RESTRICTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Override transfer to make non-transferable
     * @dev Reverts if isNonTransferable is true
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (isNonTransferable) revert TransferDisabled();
        return super.transfer(to, amount);
    }

    /**
     * @notice Override transferFrom to make non-transferable
     * @dev Reverts if isNonTransferable is true
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (isNonTransferable) revert TransferDisabled();
        return super.transferFrom(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add authorized minter
     * @param minter Minter address to add
     * @dev Only admin can call
     */
    function addMinter(address minter) external {
        if (msg.sender != admin) revert Unauthorized();
        require(minter != address(0), "OGPointsToken: zero minter");
        require(!minters[minter], "OGPointsToken: already minter");

        minters[minter] = true;
        emit MinterAdded(minter);
    }

    /**
     * @notice Remove authorized minter
     * @param minter Minter address to remove
     * @dev Only admin can call
     */
    function removeMinter(address minter) external {
        if (msg.sender != admin) revert Unauthorized();
        require(minters[minter], "OGPointsToken: not minter");

        minters[minter] = false;
        emit MinterRemoved(minter);
    }

    /**
     * @notice Transfer admin role
     * @param newAdmin New admin address
     * @dev Only admin can call
     */
    function transferAdmin(address newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        require(newAdmin != address(0), "OGPointsToken: zero admin");

        admin = newAdmin;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if address is authorized minter
     * @param account Address to check
     * @return isMinter Whether address is minter
     */
    function isMinter(address account) external view returns (bool isMinter) {
        return minters[account];
    }

    /**
     * @notice Get user statistics
     * @param user User address
     * @return balance Current balance
     * @return minted Total minted
     * @return burned Total burned
     */
    function getUserStats(address user)
        external
        view
        returns (
            uint256 balance,
            uint256 minted,
            uint256 burned
        )
    {
        return (balanceOf(user), userMinted[user], userBurned[user]);
    }

    /**
     * @notice Get global statistics
     * @return totalSupply_ Current total supply
     * @return totalMinted_ Total minted
     * @return totalBurned_ Total burned
     */
    function getGlobalStats()
        external
        view
        returns (
            uint256 totalSupply_,
            uint256 totalMinted_,
            uint256 totalBurned_
        )
    {
        return (totalSupply(), totalMinted, totalBurned);
    }

    /**
     * @notice Get net points for a user (minted - burned)
     * @param user User address
     * @return netPoints Net points accumulated
     */
    function getNetPoints(address user) external view returns (uint256 netPoints) {
        return userMinted[user] - userBurned[user];
    }
}

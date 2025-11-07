// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockYieldStrategy
 * @notice Simplified mock of YieldDonating Strategy for testing
 * @dev Acts as both a strategy and ERC20 share token
 *      Mimics ERC4626-like behavior for deposit/redeem
 */
contract MockYieldStrategy is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    uint256 public totalAssets;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Redeem(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event ProfitSharesMinted(address indexed recipient, uint256 shares);

    constructor(address _asset) ERC20("Mock Strategy Shares", "mSTRAT") {
        asset = IERC20(_asset);
    }

    /**
     * @notice Deposit assets into strategy
     * @dev Mints 1:1 shares for simplicity
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets > 0, "MockYieldStrategy: zero assets");

        // Transfer assets from caller
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Mint shares 1:1 for simplicity
        shares = assets;
        _mint(receiver, shares);

        totalAssets += assets;

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    /**
     * @notice Redeem shares for assets
     * @dev Burns shares and returns assets 1:1
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(shares > 0, "MockYieldStrategy: zero shares");
        require(balanceOf(owner) >= shares, "MockYieldStrategy: insufficient shares");

        // Burn shares
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);

        // Transfer assets 1:1
        assets = shares;
        require(asset.balanceOf(address(this)) >= assets, "MockYieldStrategy: insufficient liquidity");

        asset.safeTransfer(receiver, assets);
        totalAssets -= assets;

        emit Redeem(msg.sender, receiver, assets, shares);
        return assets;
    }

    /**
     * @notice Convert shares to assets
     * @dev 1:1 conversion for simplicity
     */
    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /**
     * @notice Convert assets to shares
     * @dev 1:1 conversion for simplicity
     */
    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /**
     * @notice Mock function to mint profit shares (simulates yield)
     * @dev This is NOT part of real strategy - only for testing
     *      Simulates the strategy minting shares to donation address after earning yield
     */
    function mintProfitShares(address recipient, uint256 profitAmount) external {
        // Mint shares representing profit
        _mint(recipient, profitAmount);

        emit ProfitSharesMinted(recipient, profitAmount);
    }

    /**
     * @notice Get max deposit (unlimited for mock)
     */
    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Get max redeem
     */
    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    /**
     * @notice Get total assets under management
     */
    function totalAssetsManaged() external view returns (uint256) {
        return totalAssets;
    }
}

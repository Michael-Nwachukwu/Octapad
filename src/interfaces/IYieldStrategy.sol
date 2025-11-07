// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IYieldStrategy
 * @notice Interface for YieldDonating Strategy
 * @dev Simplified ERC4626-like interface for interacting with strategy shares
 */
interface IYieldStrategy {
    /**
     * @notice Returns the underlying asset (USDC)
     * @return asset Address of the underlying asset
     */
    function asset() external view returns (address);

    /**
     * @notice Returns the strategy share balance of an account
     * @param account Address to query
     * @return balance Share balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Returns total supply of strategy shares
     * @return totalSupply Total shares outstanding
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Deposit assets and mint shares to receiver
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @notice Withdraw assets by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Address that owns the shares
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Address that owns the shares
     * @return assets Amount of assets received
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /**
     * @notice Convert shares to assets
     * @param shares Amount of shares
     * @return assets Equivalent assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Convert assets to shares
     * @param assets Amount of assets
     * @return shares Equivalent shares
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Returns maximum assets that can be deposited
     * @param receiver Address that would receive shares
     * @return maxAssets Maximum depositale assets
     */
    function maxDeposit(address receiver) external view returns (uint256 maxAssets);

    /**
     * @notice Returns maximum assets that can be withdrawn
     * @param owner Address that owns shares
     * @return maxAssets Maximum withdrawable assets
     */
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    /**
     * @notice Returns maximum shares that can be redeemed
     * @param owner Address that owns shares
     * @return maxShares Maximum redeemable shares
     */
    function maxRedeem(address owner) external view returns (uint256 maxShares);
}

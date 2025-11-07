// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IPaymentSplitter
 * @notice Interface for Octant PaymentSplitter
 * @dev Used to claim shares from the splitter
 */
interface IPaymentSplitter {
    /**
     * @notice Returns the total shares across all payees
     * @return total Sum of all payee shares
     */
    function totalShares() external view returns (uint256);

    /**
     * @notice Returns the share allocation for a payee
     * @param account Address of the payee
     * @return shares Number of shares assigned to payee
     */
    function shares(address account) external view returns (uint256);

    /**
     * @notice Returns amount of ERC20 tokens already released to a payee
     * @param token Address of the ERC20 token
     * @param account Address of the payee
     * @return amount Tokens already released
     */
    function released(address token, address account) external view returns (uint256);

    /**
     * @notice Returns amount of ERC20 tokens claimable by a payee
     * @param token Address of the ERC20 token
     * @param account Address of the payee
     * @return amount Claimable tokens
     */
    function releasable(address token, address account) external view returns (uint256);

    /**
     * @notice Releases owed ERC20 tokens to a payee
     * @param token Address of the ERC20 token
     * @param account Address of the payee to release payment to
     */
    function release(address token, address account) external;

    /**
     * @notice Returns the payee address at a specific index
     * @param index Index in the payees array
     * @return payee Payee address at the index
     */
    function payee(uint256 index) external view returns (address);
}

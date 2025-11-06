// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin-contracts-5.3.0/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title CampaignToken
 * @notice ERC20 token created for each campaign on OctaPad
 * @dev Only the launchpad contract can mint tokens
 */
contract CampaignToken is ERC20, ERC20Burnable {
    /// @notice Address of the launchpad that can mint tokens
    address public immutable launchpad;

    /// @notice Campaign creator who receives allocation
    address public immutable creator;

    /// @notice Timestamp when token was created
    uint256 public immutable createdAt;

    error Unauthorized();

    /**
     * @notice Create a new campaign token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param launchpad_ Address of OctaPad launchpad
     * @param creator_ Address of campaign creator
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address launchpad_,
        address creator_
    ) ERC20(name_, symbol_) {
        require(launchpad_ != address(0), "CampaignToken: zero launchpad");
        require(creator_ != address(0), "CampaignToken: zero creator");

        launchpad = launchpad_;
        creator = creator_;
        createdAt = block.timestamp;
    }

    /**
     * @notice Mint tokens - only callable by launchpad
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        if (msg.sender != launchpad) revert Unauthorized();
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from a specific address - only callable by launchpad
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     * @dev Used for refunds when campaign is cancelled
     */
    function burnFrom(address from, uint256 amount) public override {
        // Allow launchpad to burn without approval (for refunds)
        if (msg.sender == launchpad) {
            _burn(from, amount);
        } else {
            // Otherwise use normal burnFrom with allowance check
            super.burnFrom(from, amount);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title BondingCurve
 * @notice Simple linear bonding curve for token pricing
 * @dev Price increases linearly as more tokens are sold
 *
 * Formula: price = avgPrice + (avgPrice * tokensSold / tokensForSale)
 *
 * This creates a linear price increase from avgPrice to 2*avgPrice
 * where avgPrice = targetFunding / tokensForSale
 */
library BondingCurve {
    /**
     * @notice Calculate how many tokens a buyer receives for a given USDC amount
     * @param tokensForSale Total tokens available for sale
     * @param tokensSold Tokens already sold
     * @param targetFunding Target USDC to raise
     * @param usdcAmount USDC amount buyer is spending
     * @return tokensOut Number of tokens buyer receives
     *
     * @dev Uses linear pricing: as more tokens sell, price increases proportionally
     *
     * Example:
     * - tokensForSale = 1,000,000
     * - targetFunding = 100,000 USDC
     * - avgPrice = 0.1 USDC per token
     * - At 0% sold: price = 0.1 USDC
     * - At 50% sold: price = 0.15 USDC
     * - At 100% sold: price = 0.2 USDC
     */
    function calculatePurchaseReturn(
        uint256 tokensForSale,
        uint256 tokensSold,
        uint256 targetFunding,
        uint256 usdcAmount
    ) internal pure returns (uint256 tokensOut) {
        require(tokensForSale > 0, "BondingCurve: invalid tokensForSale");
        require(tokensSold <= tokensForSale, "BondingCurve: sold exceeds available");

        // Calculate average price across entire curve (in 1e18 precision)
        uint256 avgPrice = (targetFunding * 1e18) / tokensForSale;

        // Calculate current price based on how many tokens sold
        // currentPrice = avgPrice * (1 + tokensSold / tokensForSale)
        uint256 priceFactor = 1e18 + ((tokensSold * 1e18) / tokensForSale);
        uint256 currentPrice = (avgPrice * priceFactor) / 1e18;

        // Calculate tokens out: usdcAmount / currentPrice
        tokensOut = (usdcAmount * 1e18) / currentPrice;

        // Ensure we don't exceed available tokens
        uint256 remainingTokens = tokensForSale - tokensSold;
        if (tokensOut > remainingTokens) {
            tokensOut = remainingTokens;
        }

        return tokensOut;
    }

    /**
     * @notice Calculate USDC needed to purchase an exact number of tokens
     * @param tokensForSale Total tokens available for sale
     * @param tokensSold Tokens already sold
     * @param targetFunding Target USDC to raise
     * @param tokensWanted Exact number of tokens desired
     * @return usdcNeeded USDC amount needed for purchase
     *
     * @dev Uses average price over the purchase range for simplicity
     *
     * For a more accurate calculation, we'd integrate the price curve,
     * but for simplicity and gas efficiency, we use the average price
     * at the start and end of the purchase.
     */
    function calculateExactUsdcForTokens(
        uint256 tokensForSale,
        uint256 tokensSold,
        uint256 targetFunding,
        uint256 tokensWanted
    ) internal pure returns (uint256 usdcNeeded) {
        require(tokensForSale > 0, "BondingCurve: invalid tokensForSale");
        require(tokensSold + tokensWanted <= tokensForSale, "BondingCurve: exceeds available");

        // Calculate average price
        uint256 avgPrice = (targetFunding * 1e18) / tokensForSale;

        // Calculate price at start of purchase
        uint256 startPriceFactor = 1e18 + ((tokensSold * 1e18) / tokensForSale);
        uint256 startPrice = (avgPrice * startPriceFactor) / 1e18;

        // Calculate price at end of purchase
        uint256 endPriceFactor = 1e18 + (((tokensSold + tokensWanted) * 1e18) / tokensForSale);
        uint256 endPrice = (avgPrice * endPriceFactor) / 1e18;

        // Use average of start and end price
        uint256 effectivePrice = (startPrice + endPrice) / 2;

        // Calculate USDC needed
        usdcNeeded = (tokensWanted * effectivePrice) / 1e18;

        return usdcNeeded;
    }

    /**
     * @notice Get current token price at a specific point in the sale
     * @param tokensForSale Total tokens available for sale
     * @param tokensSold Tokens already sold
     * @param targetFunding Target USDC to raise
     * @return price Current price per token (in 1e18 precision)
     */
    function getCurrentPrice(
        uint256 tokensForSale,
        uint256 tokensSold,
        uint256 targetFunding
    ) internal pure returns (uint256 price) {
        require(tokensForSale > 0, "BondingCurve: invalid tokensForSale");
        require(tokensSold <= tokensForSale, "BondingCurve: sold exceeds available");

        uint256 avgPrice = (targetFunding * 1e18) / tokensForSale;
        uint256 priceFactor = 1e18 + ((tokensSold * 1e18) / tokensForSale);
        price = (avgPrice * priceFactor) / 1e18;

        return price;
    }

    /**
     * @notice Calculate total USDC raised if all tokens sold
     * @param tokensForSale Total tokens available for sale
     * @param targetFunding Target USDC to raise
     * @return totalRaised Total USDC that would be raised
     *
     * @dev With linear curve, total raised = targetFunding * 1.5
     * because average price across curve is 1.5x the base price
     */
    function calculateTotalRaisedIfComplete(
        uint256 tokensForSale,
        uint256 targetFunding
    ) internal pure returns (uint256 totalRaised) {
        // With linear increase from avgPrice to 2*avgPrice,
        // the actual average is 1.5*avgPrice
        // So total raised = tokensForSale * (1.5 * avgPrice)
        totalRaised = (targetFunding * 3) / 2;

        return totalRaised;
    }
}

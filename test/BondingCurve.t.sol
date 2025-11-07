// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.11.0/src/Test.sol";
import {console} from "forge-std-1.11.0/src/console.sol";
import {BondingCurve} from "../src/launchpad/BondingCurve.sol";

contract BondingCurveTest is Test {
    // Test constants
    uint256 constant TOTAL_SUPPLY = 1_000_000e18; // 1M tokens
    uint256 constant TOKENS_FOR_SALE = 500_000e18; // 50% for sale
    uint256 constant TARGET_FUNDING = 10_000e6; // 10,000 USDC (6 decimals)

    /*//////////////////////////////////////////////////////////////
                        PURCHASE RETURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CalculatePurchaseReturn_FirstPurchase() public pure {
        // First purchase at initial price
        uint256 usdcAmount = 100e6; // 100 USDC

        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            0, // No tokens sold yet
            TARGET_FUNDING,
            usdcAmount
        );

        // Average price = 10,000 USDC / 500,000 tokens = 0.02 USDC per token
        // Initial price = avgPrice (since tokensSold = 0)
        // Expected tokens = 100 / 0.02 = 5,000 tokens
        assertEq(tokensOut, 5000e18);
    }

    function test_CalculatePurchaseReturn_MiddlePurchase() public pure {
        // Purchase when half the tokens are sold
        uint256 tokensSold = 250_000e18; // 50% sold
        uint256 usdcAmount = 100e6;

        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            tokensSold,
            TARGET_FUNDING,
            usdcAmount
        );

        // Price should be higher than initial
        // Average price = 0.02 USDC
        // Price at 50% sold = avgPrice * (1 + 0.5) = 0.03 USDC
        // Expected tokens = 100 / 0.03 ≈ 3,333.33 tokens
        assertApproxEqRel(tokensOut, 3333e18, 0.01e18); // Within 1%
    }

    function test_CalculatePurchaseReturn_LastPurchase() public pure {
        // Purchase near end (99% sold)
        uint256 tokensSold = 495_000e18; // 99% sold
        uint256 usdcAmount = 100e6;

        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            tokensSold,
            TARGET_FUNDING,
            usdcAmount
        );

        // Price should be near maximum (2x avgPrice)
        // Price at 99% ≈ 0.0398 USDC per token
        // Expected tokens ≈ 100 / 0.0398 ≈ 2,512 tokens
        assertApproxEqRel(tokensOut, 2512e18, 0.05e18); // Within 5%
    }

    function test_CalculatePurchaseReturn_ExceedsSupply() public pure {
        // Try to buy more than remaining
        uint256 tokensSold = 499_000e18; // 1,000 tokens left
        uint256 usdcAmount = 1000e6; // Way more USDC than needed

        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            tokensSold,
            TARGET_FUNDING,
            usdcAmount
        );

        // Should be capped at remaining tokens
        uint256 remainingTokens = TOKENS_FOR_SALE - tokensSold;
        assertEq(tokensOut, remainingTokens);
    }

    function test_CalculatePurchaseReturn_ZeroUSDC() public pure {
        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            0,
            TARGET_FUNDING,
            0
        );

        assertEq(tokensOut, 0);
    }

    function test_CalculatePurchaseReturn_SmallAmount() public pure {
        // Buy with 0.01 USDC
        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            0,
            TARGET_FUNDING,
            0.01e6
        );

        // Should get 0.5 tokens (0.01 / 0.02)
        assertEq(tokensOut, 0.5e18);
    }

    function test_CalculatePurchaseReturn_MultipleSmallPurchases() public pure {
        uint256 purchaseAmount = 10e6; // 10 USDC each
        uint256 numPurchases = 10;

        uint256 totalTokens;
        uint256 tokensSold;

        for (uint256 i = 0; i < numPurchases; i++) {
            uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
                TOKENS_FOR_SALE,
                tokensSold,
                TARGET_FUNDING,
                purchaseAmount
            );

            totalTokens += tokensOut;
            tokensSold += tokensOut;
        }

        // Total should be less than buying all at once (due to price increase)
        uint256 tokensIfBoughtAtOnce = BondingCurve.calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            0,
            TARGET_FUNDING,
            purchaseAmount * numPurchases
        );

        assertTrue(totalTokens < tokensIfBoughtAtOnce);
    }

    /*//////////////////////////////////////////////////////////////
                    EXACT USDC FOR TOKENS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CalculateExactUsdcForTokens_MiddlePurchase() public pure {
        uint256 tokensSold = 250_000e18; // 50% sold
        uint256 tokensDesired = 3333e18;

        uint256 usdcNeeded = BondingCurve.calculateExactUsdcForTokens(
            TOKENS_FOR_SALE,
            tokensSold,
            TARGET_FUNDING,
            tokensDesired
        );

        // At 50% sold, price ≈ 0.03 USDC per token
        // Expected USDC ≈ 3333 * 0.03 ≈ 100 USDC
        assertApproxEqRel(usdcNeeded, 100e6, 0.01e18);
    }

    function test_CalculateExactUsdcForTokens_ZeroTokens() public pure {
        uint256 usdcNeeded = BondingCurve.calculateExactUsdcForTokens(
            TOKENS_FOR_SALE,
            0,
            TARGET_FUNDING,
            0
        );

        assertEq(usdcNeeded, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    CURRENT PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentPrice_InitialPrice() public pure {
        uint256 price = BondingCurve.getCurrentPrice(
            TOKENS_FOR_SALE,
            0,
            TARGET_FUNDING
        );

        // Average price = 10,000 / 500,000 = 0.02 USDC per token
        // Initial price = avgPrice * 1 = 0.02 USDC
        uint256 expectedPrice = (TARGET_FUNDING * 1e18) / TOKENS_FOR_SALE;
        assertEq(price, expectedPrice);
    }

    function test_GetCurrentPrice_HalfwaySold() public pure {
        uint256 price = BondingCurve.getCurrentPrice(
            TOKENS_FOR_SALE,
            250_000e18, // 50% sold
            TARGET_FUNDING
        );

        // Price at 50% = avgPrice * 1.5 = 0.03 USDC
        uint256 avgPrice = (TARGET_FUNDING * 1e18) / TOKENS_FOR_SALE;
        uint256 expectedPrice = (avgPrice * 15) / 10; // 1.5x

        assertEq(price, expectedPrice);
    }

    function test_GetCurrentPrice_FullySold() public pure {
        uint256 price = BondingCurve.getCurrentPrice(
            TOKENS_FOR_SALE,
            TOKENS_FOR_SALE, // 100% sold
            TARGET_FUNDING
        );

        // Price at 100% = avgPrice * 2 = 0.04 USDC
        uint256 avgPrice = (TARGET_FUNDING * 1e18) / TOKENS_FOR_SALE;
        uint256 expectedPrice = avgPrice * 2;

        assertEq(price, expectedPrice);
    }

    function test_GetCurrentPrice_ProgressiveIncrease() public pure {
        // Test at 0%, 25%, 50%, 75%, 100%
        uint256[] memory percentages = new uint256[](5);
        percentages[0] = 0;
        percentages[1] = 25;
        percentages[2] = 50;
        percentages[3] = 75;
        percentages[4] = 100;

        uint256 lastPrice;
        for (uint256 i = 0; i < percentages.length; i++) {
            uint256 tokensSold = (TOKENS_FOR_SALE * percentages[i]) / 100;
            uint256 currentPrice = BondingCurve.getCurrentPrice(
                TOKENS_FOR_SALE,
                tokensSold,
                TARGET_FUNDING
            );

            // Price should be increasing
            if (i > 0) {
                assertTrue(currentPrice > lastPrice, "Price should increase");
            }

            lastPrice = currentPrice;
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION/REALISTIC SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_RealisticCampaign_SmallPurchases() public pure {
        uint256 tokensForSale = 1_000_000e18;
        uint256 targetFunding = 50_000e6; // $50k target
        uint256 purchaseSize = 100e6; // $100 per purchase

        uint256 totalTokensSold;
        uint256 totalUsdcSpent;

        // Simulate 100 users buying $100 each
        for (uint256 i = 0; i < 100; i++) {
            uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
                tokensForSale,
                totalTokensSold,
                targetFunding,
                purchaseSize
            );

            totalTokensSold += tokensOut;
            totalUsdcSpent += purchaseSize;
        }

        // Total spent = $10,000
        assertEq(totalUsdcSpent, 10_000e6);

        // Progress should be 20% (10k / 50k)
        uint256 progress = (totalUsdcSpent * 10000) / targetFunding;
        assertEq(progress, 2000); // 20%
    }

    function test_RealisticCampaign_MixedSizes() public pure {
        uint256 tokensForSale = 500_000e18;
        uint256 targetFunding = 10_000e6;

        uint256 totalTokensSold;

        // Whale buys $5,000
        uint256 whaleTokens = BondingCurve.calculatePurchaseReturn(
            tokensForSale,
            totalTokensSold,
            targetFunding,
            5000e6
        );
        totalTokensSold += whaleTokens;

        // 10 medium buyers at $200 each
        for (uint256 i = 0; i < 10; i++) {
            uint256 tokens = BondingCurve.calculatePurchaseReturn(
                tokensForSale,
                totalTokensSold,
                targetFunding,
                200e6
            );
            totalTokensSold += tokens;
        }

        // 50 small buyers at $50 each
        for (uint256 i = 0; i < 50; i++) {
            uint256 tokens = BondingCurve.calculatePurchaseReturn(
                tokensForSale,
                totalTokensSold,
                targetFunding,
                50e6
            );
            totalTokensSold += tokens;
        }

        // Total raised = $5k + $2k + $2.5k = $9.5k
        // Whale should have gotten best price (most tokens)
        assertTrue(whaleTokens > 100_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EdgeCase_SingleTokenPurchase() public pure {
        // Try to buy exactly 1 token (1e18 wei)
        uint256 usdcNeeded = BondingCurve.calculateExactUsdcForTokens(
            TOKENS_FOR_SALE,
            0,
            TARGET_FUNDING,
            1e18
        );

        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            TOKENS_FOR_SALE,
            0,
            TARGET_FUNDING,
            usdcNeeded
        );

        assertEq(tokensOut, 1e18);
    }

    function test_EdgeCase_VeryLargeNumbers() public pure {
        uint256 largeSupply = 1_000_000_000e18; // 1B tokens
        uint256 largeFunding = 1_000_000e6; // $1M USDC

        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            largeSupply,
            0,
            largeFunding,
            10_000e6 // $10k purchase
        );

        // Should not overflow or revert
        assertTrue(tokensOut > 0);
    }

    function test_EdgeCase_VerySmallNumbers() public pure {
        uint256 smallSupply = 1000e18; // 1k tokens
        uint256 smallFunding = 10e6; // $10 USDC

        uint256 tokensOut = BondingCurve.calculatePurchaseReturn(
            smallSupply,
            0,
            smallFunding,
            1e6 // $1 purchase
        );

        // Should handle small numbers
        assertTrue(tokensOut > 0);
    }

    function test_EdgeCase_PriceAtEachPercent() public pure {
        uint256 avgPrice = (TARGET_FUNDING * 1e18) / TOKENS_FOR_SALE;

        for (uint256 percent = 0; percent <= 100; percent += 10) {
            uint256 tokensSold = (TOKENS_FOR_SALE * percent) / 100;
            uint256 price = BondingCurve.getCurrentPrice(
                TOKENS_FOR_SALE,
                tokensSold,
                TARGET_FUNDING
            );

            // Price should increase linearly from avgPrice to 2*avgPrice
            uint256 expectedPrice = avgPrice + ((avgPrice * percent) / 100);
            assertApproxEqRel(price, expectedPrice, 0.01e18); // Within 1%
        }
    }
}

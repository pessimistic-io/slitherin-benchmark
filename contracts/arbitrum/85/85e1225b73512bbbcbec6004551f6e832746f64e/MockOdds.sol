// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./math_Math.sol";

library MockOddsLib {
    // Precision to be used in calculations
    uint256 public constant PRECISION = 1e6;

    /*
        * @dev Adjust the odds downwards linearly to 1
        * @param wager The amount wagered
        * @param pool The total amount in the pool
        * @return The adjusted decimal odds given
    */
    function getLinearAdjustedOdds(
        uint256 wager,
        uint256 odds,
        uint256 liquidity
    ) external pure returns (uint256) {
        return odds;
    }

    /*
        * @dev Reduces odds on a curve that approaches 0 as the payout increases, such that the payout will always be less then free liquidity. Increase the coefficient to make the curve steeper. 2 is a good starting point.
        * @param wager The amount of the wager
        * @param odds The decimals odds of the wager, expressed as a number
        * @return The new adjusted decimal odds
    */
    function getCurvedAdjustedOdds(
        uint256 wager,
        uint256 odds,
        uint256 liquidity
    ) external pure returns (uint256) {
        return odds;
    }

    // Assuming that the market previously had targetMargin, then after some runners have been scratched, correct the odds of this runner to make up the margin again
    function rebaseOddsWithScratch(uint256 odds, uint256 scratchedOdds, uint256 targetMargin) external pure returns (uint256) {
        assert(odds > 0);
        uint256 newMargin = targetMargin - PRECISION / scratchedOdds;
        return changeMargin(odds, newMargin, targetMargin);
    } 

    function changeMargin(uint256 odds, uint256 margin, uint256 targetMargin) public pure returns (uint256) {
        return addMargin(removeMargin(odds, margin), targetMargin);
    }

    function removeMargin(uint256 odds, uint256 margin) public pure returns (uint256) {
        return odds * margin / PRECISION;
    }

    function addMargin(uint256 odds, uint256 margin) public pure returns (uint256) {
        assert(margin > 0);
        return odds * PRECISION / margin;
    }

    // Given an array of odds, return the margin
    function getMargin(uint256[] calldata odds) public pure returns (uint256) {
        uint256 total; // 0
        uint256 oddsCount = odds.length;
        for (uint256 i = 0; i < oddsCount; i++) {
            if (odds[i] == 0) continue;
            total += ((PRECISION * PRECISION) / odds[i]);
        }
        return total;
    }
}

//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;
import {Math} from "./Math.sol";
// import hardhat console.log
import "./console.sol";

/**
 * @author Chef Photons, Vaultka Team serving high quality drinks; drink responsibly.
 * Slope model for calculating the reward split mechanism
 */
// @TODO maybe require a refactor
library FeeSplitStrategy {
    using Math for uint128;
    using Math for uint256;

    uint256 internal constant RATE_PRECISION = 1e30;

    struct Info {
        /**
         * @dev this constant represents the utilization rate at which the vault aims to obtain most competitive borrow rates.
         * Expressed in ray
         **/
        uint128 optimalUtilizationRate;
        // slope 1 used to control the change of reward fee split when reward is inbetween  0-40%
        uint128 maxFeeSplitSlope1;
        // slope 2 used to control the change of reward fee split when reward is inbetween  40%-80%
        uint128 maxFeeSplitSlope2;
        // slope 3 used to control the change of reward fee split when reward is inbetween  80%-100%
        uint128 maxFeeSplitSlope3;
        uint128 utilizationThreshold1;
        uint128 utilizationThreshold2;
        uint128 utilizationThreshold3;
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations.
     * NOTE This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * New protocol implementation uses the new calculateInterestRates() interface
     * @param totalDebtInUSDC The liquidity available in the corresponding aToken
     * @param waterBalanceInUSDC The total borrowed from the reserve at a variable rate
     **/
    function calculateFeeSplit(
        Info storage feeStrategy,
        uint256 waterBalanceInUSDC,
        uint256 totalDebtInUSDC
    ) internal view returns (uint256 feeSplitRate, uint256 ur) {
        uint256 utilizationRate = getUtilizationRate(waterBalanceInUSDC, totalDebtInUSDC);
        // uint256 utilizationRate = _ratio.mulDiv(_maxBPS, RATE_PRECISION);
        if (utilizationRate <= feeStrategy.utilizationThreshold1) {
            /* Slope 1
            rewardFee_{slope2} =  
                {maxFeeSplitSlope1 *  {(utilization Ratio / URThreshold1)}}
            */
            feeSplitRate = (feeStrategy.maxFeeSplitSlope1).mulDiv(utilizationRate, feeStrategy.utilizationThreshold1);

        } else if (utilizationRate > feeStrategy.utilizationThreshold1 && utilizationRate < feeStrategy.utilizationThreshold2) {
            /* Slope 2
            rewardFee_{slope2} =  
                maxFeeSplitSlope1 + 
                {(utilization Ratio - URThreshold1) / 
                (1 - UR Threshold1 - (UR Threshold3 - URThreshold2)}
                * (maxFeeSplitSlope2 -maxFeeSplitSlope1) 
            */
            uint256 subThreshold1FromUtilizationRate = utilizationRate - feeStrategy.utilizationThreshold1;
            uint256 maxBpsSubThreshold1 = RATE_PRECISION - feeStrategy.utilizationThreshold1;
            uint256 threshold3SubThreshold2 = feeStrategy.utilizationThreshold3 - feeStrategy.utilizationThreshold2;
            uint256 mSlope2SubMSlope1 = feeStrategy.maxFeeSplitSlope2 - feeStrategy.maxFeeSplitSlope1;
            uint256 feeSlpope = maxBpsSubThreshold1 - threshold3SubThreshold2;
            uint256 split = subThreshold1FromUtilizationRate.mulDiv(
                RATE_PRECISION,
                feeSlpope
            );
            feeSplitRate = mSlope2SubMSlope1.mulDiv(split, RATE_PRECISION);
            feeSplitRate = feeSplitRate + (feeStrategy.maxFeeSplitSlope1);

        } else if (utilizationRate > feeStrategy.utilizationThreshold2 && utilizationRate < feeStrategy.utilizationThreshold3) {
            /* Slope 3
            rewardFee_{slope3} =  
                maxFeeSplitSlope2 + {(utilization Ratio - URThreshold2) / 
                (1 - UR Threshold2}
                * (maxFeeSplitSlope3 -maxFeeSplitSlope2) 
            */
            uint256 subThreshold2FromUtilirationRatio = utilizationRate - feeStrategy.utilizationThreshold2;
            uint256 maxBpsSubThreshold2 = RATE_PRECISION - feeStrategy.utilizationThreshold2;
            uint256 mSlope3SubMSlope2 = feeStrategy.maxFeeSplitSlope3 - feeStrategy.maxFeeSplitSlope2;
            uint256 split = subThreshold2FromUtilirationRatio.mulDiv(RATE_PRECISION, maxBpsSubThreshold2);
            
            feeSplitRate = (split.mulDiv(mSlope3SubMSlope2, RATE_PRECISION)) + (feeStrategy.maxFeeSplitSlope2);
        }
        return (feeSplitRate, utilizationRate);
    }

    function getUtilizationRate(uint256 waterBalanceInUSDC, uint256 totalDebtInUSDC) internal pure returns (uint256) {
        return totalDebtInUSDC == 0 ? 0 : totalDebtInUSDC.mulDiv(RATE_PRECISION, waterBalanceInUSDC + totalDebtInUSDC);
    }
}


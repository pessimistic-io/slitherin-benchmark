// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ISwapAmountCalculator.sol";
import "./Constants.sol";
import "./SwapAmountCalculatorConstants.sol";
import "./ParameterVerificationHelper.sol";
import "./LiquidityNftHelper.sol";
import "./PoolHelper.sol";
import "./SafeMath.sol";

/// @dev verified, public contract
contract SwapAmountCalculator is ISwapAmountCalculator {
    using SafeMath for uint256;

    /// @dev This function is used for calculating swap amount when adding liquidity in rescaling.
    function calculateValueEqualizationSwapAmount(
        address poolAddress,
        uint256 token0Amount,
        uint256 token1Amount
    )
        public
        view
        override
        returns (address swapToken, uint256 swapAmountWithTradeFee)
    {
        // parameter verification
        ParameterVerificationHelper.verifyNotZeroAddress(poolAddress);

        // get pool information
        (address token0, address token1, uint24 poolFee, , , , ) = PoolHelper
            .getPoolInfo(poolAddress);

        // get token price ratio: (token1/token0) * 10**DECIMALS_PRECISION
        uint256 tokenPrice = PoolHelper.getTokenPriceWithDecimalsByPool(
            poolAddress,
            SwapAmountCalculatorConstants.DECIMALS_PRECISION
        );

        // input token decimal adjustment
        token0Amount = token0Amount.mul(
            10 ** (PoolHelper.getTokenDecimalAdjustment(token0))
        );
        token1Amount = token0Amount.mul(
            10 ** (PoolHelper.getTokenDecimalAdjustment(token1))
        );

        // get token0Amount to token 1 equivalent amount
        uint256 token1AmountEquivalent = getToken1AmountEquivalent(
            token0Amount,
            tokenPrice
        );

        if (token0Amount == 0 && token1Amount != 0) {
            // statement for "only input token0 amount is 0"
            return (
                token1,
                getSwapAmountFromTokenReminder(token1Amount, uint256(poolFee))
                    .div(10 ** (PoolHelper.getTokenDecimalAdjustment(token1))) // output token decimal adjustment
            );
        } else if (token1Amount == 0 && token0Amount != 0) {
            // statement for "only input token1 amount is 0"
            return (
                token0,
                getSwapAmountFromTokenReminder(token0Amount, uint256(poolFee))
                    .div(10 ** (PoolHelper.getTokenDecimalAdjustment(token0))) // output token decimal adjustment
            );
        } else if (token1AmountEquivalent > token1Amount) {
            // statement for "input token0 value more than input token1 value"
            uint256 token0AmountEquivalent = getToken0AmountEquivalent(
                token1Amount,
                tokenPrice
            );
            return (
                token0,
                getSwapAmountFromTokenReminder(
                    token0Amount - token0AmountEquivalent,
                    uint256(poolFee)
                ).div(10 ** (PoolHelper.getTokenDecimalAdjustment(token0))) // output token decimal adjustment
            );
        } else if (token1AmountEquivalent < token1Amount) {
            // statement for "input token0 value less than input token1 value"
            return (
                token1,
                getSwapAmountFromTokenReminder(
                    token1Amount - token1AmountEquivalent,
                    uint256(poolFee)
                ).div(10 ** (PoolHelper.getTokenDecimalAdjustment(token1))) // output token decimal adjustment
            );
        } else {
            // statement for "both input amount are 0" or "input token0 value equal to input token1 value"
            return (address(0), 0);
        }
    }

    /*
    tokenRemainder - swapAmount - swapAmount * tradeFee = swapAmount
    swapAmount = tokenRemainder / (2 + tradeFee)
    swapAmountWithTradeFee = swapAmount * (1 + tradeFee) = tokenRemainder * (1 + tradeFee) / (2 + tradeFee)
    */
    function getSwapAmountFromTokenReminder(
        uint256 tokenRemainder,
        uint256 tradeFee
    ) internal pure returns (uint256 swapAmountWithTradeFee) {
        uint256 denominator = uint256(2)
            .mul(SwapAmountCalculatorConstants.POOL_FEE_DENOMINATOR)
            .add(tradeFee);
        return
            tokenRemainder
                .mul(
                    uint256(SwapAmountCalculatorConstants.POOL_FEE_DENOMINATOR)
                        .add(tradeFee)
                )
                .div(denominator);
    }

    function getToken1AmountEquivalent(
        uint256 token0Amount,
        uint256 tokenPrice
    ) internal pure returns (uint256 token1AmountEquivalent) {
        return
            token0Amount.mul(tokenPrice).div(
                10 ** SwapAmountCalculatorConstants.DECIMALS_PRECISION
            );
    }

    function getToken0AmountEquivalent(
        uint256 token1Amount,
        uint256 tokenPrice
    ) internal pure returns (uint256 token0AmountEquivalent) {
        return
            token1Amount
                .mul(10 ** SwapAmountCalculatorConstants.DECIMALS_PRECISION)
                .div(tokenPrice);
    }

    /// @dev This function is used for calculating swap amount when increasing liquidity by one token.
    /*
    [Input Token0 Swap Amount Calculation]
    {token0/token1 liquiduty ratio} 
        = (inputAmount0 - token0SwapAmount - token0SwapAmount*txfee) 
            / (token0SwapAmount * {token1/token0 price ratio})
            
    [Input Token1 Swap Amount Calculation]
    {token1/token0 liquiduty ratio} 
        = (inputAmount1 - token1SwapAmount - token1SwapAmount*txfee) 
            / (token1SwapAmount * {token0/token1 price ratio})
    */
    function calculateMaximumSwapAmountForSingleTokenLiquidityIncrease(
        uint256 liquidityNftId,
        address inputToken,
        uint256 inputAmount
    ) public view override returns (uint256 swapAmountWithTradeFee) {
        // parameter verification
        ParameterVerificationHelper.verifyGreaterThanZero(liquidityNftId);
        ParameterVerificationHelper.verifyGreaterThanZero(inputAmount);
        ParameterVerificationHelper.verifyNotZeroAddress(inputToken);

        // verify inputToken is one of the token pair
        LiquidityNftHelper.verifyInputTokenIsLiquidityNftTokenPair(
            liquidityNftId,
            inputToken,
            Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
        );

        // verify current price is within nft price range
        (bool isInRange, address liquidity0Token) = LiquidityNftHelper
            .verifyCurrentPriceInLiquidityNftRange(
                liquidityNftId,
                Constants.UNISWAP_V3_FACTORY_ADDRESS,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );
        // statement for "current price is out of nft price range"
        if (!isInRange) {
            return inputToken == liquidity0Token ? 0 : inputAmount;
        }

        // statement for "current price is within nft price range"
        // get token liquiduty ratio: (token1/token0) * 10**DECIMALS_PRECISION
        uint256 liquidityRatioWithDecimals = LiquidityNftHelper
            .getInRangeLiquidityRatioWithDecimals(
                liquidityNftId,
                SwapAmountCalculatorConstants.DECIMALS_PRECISION,
                Constants.UNISWAP_V3_FACTORY_ADDRESS,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );

        // get token price ratio: (token1/token0) * 10**DECIMALS_PRECISION
        uint256 tokenPriceWithDecimals = getTokenPriceWithDecimalsByLiquidityNft(
                liquidityNftId
            );

        /*
        Token0 To Token1 preCalc: ({token1/token0 price ratio} / {token1/token0 liquiduty ratio}) + (1 + txfee)
        Token1 To Token0 preCalc: ({token1/token0 liquiduty ratio} / {token1/token0 price ratio}) + (1 + txfee)
        */
        uint256 preCalcWithDecimals = getPreCalcWithDecimals(
            liquidityNftId,
            inputToken,
            liquidityRatioWithDecimals,
            tokenPriceWithDecimals
        );

        /*
        swapAmount = (inputAmount) / preCalc
        swapAmountWithPoolFee = swapAmount * (1 + txfee)
        */
        (, , uint24 poolFee, , , , ) = LiquidityNftHelper
            .getLiquidityNftPositionsInfo(
                liquidityNftId,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );
        swapAmountWithTradeFee = inputAmount
            .mul(10 ** SwapAmountCalculatorConstants.DECIMALS_PRECISION)
            .mul(
                uint256(SwapAmountCalculatorConstants.POOL_FEE_DENOMINATOR).add(
                    poolFee
                )
            )
            .div(preCalcWithDecimals)
            .div(SwapAmountCalculatorConstants.POOL_FEE_DENOMINATOR);
    }

    function getPreCalcWithDecimals(
        uint256 liquidityNftId,
        address inputToken,
        uint256 liquidityRatioWithDecimals,
        uint256 tokenPriceWithDecimals
    ) internal view returns (uint256) {
        (address token0, , uint24 poolFee, , , , ) = LiquidityNftHelper
            .getLiquidityNftPositionsInfo(
                liquidityNftId,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );
        /*
        Token0 To Token1 preCalcWithDecimals: (tokenPriceWithDecimals / liquidityRatioWithDecimals) + 1 + (PoolFee/POOL_FEE_DENOMINATOR) with Decimals
        Token1 To Token0 preCalcWithDecimals: (liquidityRatioWithDecimals / tokenPriceWithDecimals) + 1 + (PoolFee/POOL_FEE_DENOMINATOR) with Decimals
        */
        uint256 part1 = inputToken == token0
            ? tokenPriceWithDecimals
                .mul(10 ** SwapAmountCalculatorConstants.DECIMALS_PRECISION)
                .div(liquidityRatioWithDecimals)
            : liquidityRatioWithDecimals
                .mul(10 ** SwapAmountCalculatorConstants.DECIMALS_PRECISION)
                .div(tokenPriceWithDecimals);
        uint256 part2 = uint256(1).mul(
            10 ** SwapAmountCalculatorConstants.DECIMALS_PRECISION
        );
        uint256 part3 = uint256(poolFee)
            .mul(10 ** SwapAmountCalculatorConstants.DECIMALS_PRECISION)
            .div(SwapAmountCalculatorConstants.POOL_FEE_DENOMINATOR);

        return part1.add(part2).add(part3);
    }

    function getTokenPriceWithDecimalsByLiquidityNft(
        uint256 liquidityNftId
    ) internal view returns (uint256 tokenPriceWithDecimals) {
        (address poolAddress, , , , ) = LiquidityNftHelper
            .getPoolInfoByLiquidityNft(
                liquidityNftId,
                Constants.UNISWAP_V3_FACTORY_ADDRESS,
                Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
            );
        tokenPriceWithDecimals = PoolHelper.getTokenPriceWithDecimalsByPool(
            poolAddress,
            SwapAmountCalculatorConstants.DECIMALS_PRECISION
        );
    }
}


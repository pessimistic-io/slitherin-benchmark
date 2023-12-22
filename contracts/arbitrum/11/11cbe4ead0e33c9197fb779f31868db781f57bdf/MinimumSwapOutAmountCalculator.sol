// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ISwapAmountCalculator.sol";
import "./IZap.sol";
import "./IStrategyInfo.sol";

/// @dev verified, public contract
contract MinimumSwapOutAmountCalculator {
    address public constant WBTC =
        address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    function getDepositMinimumSwapOutAmount(
        address strategyAddress,
        address inputToken,
        uint256 inputAmount
    ) public view returns (uint256 swapInAmount, uint256 minimumSwapOutAmount) {
        require(inputAmount > 0, "inputAmount invalid");

        address token0 = IStrategyInfo(strategyAddress).token0Address();
        address token1 = IStrategyInfo(strategyAddress).token1Address();

        require(
            inputToken == token0 || inputToken == token1,
            "inputToken invalid"
        );

        swapInAmount = ISwapAmountCalculator(
            IStrategyInfo(strategyAddress).getSwapAmountCalculatorAddress()
        ).calculateMaximumSwapAmountForSingleTokenLiquidityIncrease(
                IStrategyInfo(strategyAddress).liquidityNftId(),
                inputToken,
                inputAmount
            );

        if (swapInAmount == 0) {
            return (0, 0);
        } else {
            address outputToken = (inputToken == token0) ? token1 : token0;

            minimumSwapOutAmount = IZap(
                IStrategyInfo(strategyAddress).getZapAddress()
            ).getMinimumSwapOutAmount(inputToken, outputToken, swapInAmount);
        }
    }

    function getEarnMinimumSwapOutAmount(
        address strategyAddress
    )
        public
        view
        returns (
            uint256 minimumToken0SwapOutAmount,
            uint256 minimumToken1SwapOutAmount,
            uint256 minimumBuybackSwapOutAmount
        )
    {
        address token0 = IStrategyInfo(strategyAddress).token0Address();
        minimumToken0SwapOutAmount = getMinimumSwapOutWbtcAmount(
            strategyAddress,
            token0,
            IStrategyInfo(strategyAddress).rewardToken0Amount()
        );

        address token1 = IStrategyInfo(strategyAddress).token1Address();
        minimumToken1SwapOutAmount = getMinimumSwapOutWbtcAmount(
            strategyAddress,
            token1,
            IStrategyInfo(strategyAddress).rewardToken1Amount()
        );

        minimumBuybackSwapOutAmount = getMinimumBuybackAmount(
            strategyAddress,
            (minimumToken0SwapOutAmount + minimumToken1SwapOutAmount)
        );
    }

    function getMinimumSwapOutWbtcAmount(
        address strategyAddress,
        address inputToken,
        uint256 inputAmount
    ) internal view returns (uint256 minimumSwapOutAmount) {
        if (inputToken == WBTC) {
            minimumSwapOutAmount = inputAmount;
        } else if (inputAmount == 0) {
            minimumSwapOutAmount = 0;
        } else {
            minimumSwapOutAmount = IZap(
                IStrategyInfo(strategyAddress).getZapAddress()
            ).getMinimumSwapOutAmount(inputToken, WBTC, inputAmount);
        }
    }

    function getMinimumBuybackAmount(
        address strategyAddress,
        uint256 totalMinimumSwapOutWbtcAmount
    ) internal view returns (uint256 minimumBuybackAmount) {
        uint256 rewardWbtcAmount = IStrategyInfo(strategyAddress)
            .rewardWbtcAmount();

        uint24 buyBackNumerator = IStrategyInfo(strategyAddress)
            .buyBackNumerator();
        uint24 buyBackDenominator = IStrategyInfo(strategyAddress)
            .getBuyBackDenominator();

        uint256 buyBackWbtcAmount = ((rewardWbtcAmount +
            totalMinimumSwapOutWbtcAmount) * buyBackNumerator) /
            buyBackDenominator;

        if (buyBackNumerator == 0 || buyBackWbtcAmount == 0) {
            minimumBuybackAmount = 0;
        } else {
            address buyBackToken = IStrategyInfo(strategyAddress)
                .buyBackToken();

            minimumBuybackAmount = IZap(
                IStrategyInfo(strategyAddress).getZapAddress()
            ).getMinimumSwapOutAmount(WBTC, buyBackToken, buyBackWbtcAmount);
        }
    }
}


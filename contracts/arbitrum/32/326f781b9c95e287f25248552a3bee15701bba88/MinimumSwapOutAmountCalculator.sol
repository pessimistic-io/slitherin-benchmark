// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ISwapAmountCalculator.sol";
import "./IZap.sol";
import "./IStrategyInfo.sol";

/// @dev verified, public contract
contract MinimumSwapOutAmountCalculator {
    address public USDT = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

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
        minimumToken0SwapOutAmount = getMinimumSwapOutUsdtAmount(
            strategyAddress,
            token0,
            IStrategyInfo(strategyAddress).rewardToken0Amount()
        );

        address token1 = IStrategyInfo(strategyAddress).token1Address();
        minimumToken1SwapOutAmount = getMinimumSwapOutUsdtAmount(
            strategyAddress,
            token1,
            IStrategyInfo(strategyAddress).rewardToken1Amount()
        );

        minimumBuybackSwapOutAmount = getMinimumBuybackAmount(
            strategyAddress,
            (minimumToken0SwapOutAmount + minimumToken1SwapOutAmount)
        );
    }

    function getMinimumSwapOutUsdtAmount(
        address strategyAddress,
        address inputToken,
        uint256 inputAmount
    ) internal view returns (uint256 minimumSwapOutAmount) {
        if (inputToken == USDT) {
            minimumSwapOutAmount = inputAmount;
        } else if (inputAmount == 0) {
            minimumSwapOutAmount = 0;
        } else {
            minimumSwapOutAmount = IZap(
                IStrategyInfo(strategyAddress).getZapAddress()
            ).getMinimumSwapOutAmount(inputToken, USDT, inputAmount);
        }
    }

    function getMinimumBuybackAmount(
        address strategyAddress,
        uint256 totalMinimumSwapOutUsdtAmount
    ) internal view returns (uint256 minimumBuybackAmount) {
        uint256 rewardUsdtAmount = IStrategyInfo(strategyAddress)
            .rewardUsdtAmount();

        uint24 buyBackNumerator = IStrategyInfo(strategyAddress)
            .buyBackNumerator();
        uint24 buyBackDenominator = IStrategyInfo(strategyAddress)
            .getBuyBackDenominator();

        uint256 buyBackUsdtAmount = ((rewardUsdtAmount +
            totalMinimumSwapOutUsdtAmount) * buyBackNumerator) /
            buyBackDenominator;

        if (buyBackNumerator == 0 || buyBackUsdtAmount == 0) {
            minimumBuybackAmount = 0;
        } else {
            address buyBackToken = IStrategyInfo(strategyAddress)
                .buyBackToken();

            minimumBuybackAmount = IZap(
                IStrategyInfo(strategyAddress).getZapAddress()
            ).getMinimumSwapOutAmount(USDT, buyBackToken, buyBackUsdtAmount);
        }
    }
}


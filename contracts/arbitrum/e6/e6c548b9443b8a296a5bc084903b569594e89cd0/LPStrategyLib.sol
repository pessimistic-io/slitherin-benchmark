// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IUniswapV2Router01} from "./IUniswapV2Router01.sol";
import {IStableSwap} from "./IStableSwap.sol";
import {ISsovV3} from "./ISsovV3.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";
import {OneInchZapLib} from "./OneInchZapLib.sol";

library LPStrategyLib {
    // Represents 100%
    uint256 public constant basePercentage = 1e12;

    // Arbitrum sushi router
    IUniswapV2Router01 constant swapRouter = IUniswapV2Router01(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    // Arbitrum curve stable swap (2Crv)
    IStableSwap constant stableSwap = IStableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    I1inchAggregationRouterV4 constant oneInch =
        I1inchAggregationRouterV4(payable(0x1111111254fb6c44bAC0beD2854e76F90643097d));

    struct StrikePerformance {
        // Strike index
        uint256 index;
        // Strike price
        uint256 strike;
        // Distance to ITM
        uint256 delta;
        // `true` if in the money, `false` otherwise
        bool itm;
    }

    // To prevent Stack too deep error
    struct BuyOptionsInput {
        // Ssov contract
        ISsovV3 ssov;
        // Ssov epoch
        uint256 ssovEpoch;
        // Ssov epoch expiry
        uint256 ssovExpiry;
        // Amount of collateral available
        uint256 collateralBalance;
        // The % collateral to use to buy options
        uint256[] collateralPercentages;
        // The % limits of collateral that can be used
        uint256[] limits;
        // The % of puts bought so far
        uint256[] used;
        // The expected order of strikes
        uint256[] strikesOrderMatch;
        // If `true` it will ignore the strikes that are ITM
        bool ignoreITM;
    }

    // To prevent Stack too deep error
    struct SwapAndBuyOptionsInput {
        // Ssov contract
        ISsovV3 ssov;
        // The token that we want to sell to buy calls
        IERC20 tokenToSwap;
        // Ssov epoch
        uint256 ssovEpoch;
        // Ssov epoch expiry
        uint256 ssovExpiry;
        // Amount of collateral available
        uint256 collateralBalance;
        // The amount of tokens available to swap
        uint256 tokenToSwapBalance;
        // The % of tokens to sell per strikes. Strike order should follow `strikesOrderMatch`
        uint256[] collateralPercentages;
        // The % of `tokenToSwap` balance to swap. It applies to `tokenToSwapBalance`
        uint256 swapPercentage;
        // 1Inch swap configuration
        OneInchZapLib.SwapParams swapParams;
        // The % limits of swaps per strike per strike. Strike order should follow the SSOV strike order
        uint256[] limits;
        // The % of swapps so far per strike. Strike order should follow the SSOV strike order
        uint256[] used;
        // The expected order of strikes
        uint256[] strikesOrderMatch;
        // The % limit of swapped tokens
        uint256 swapLimit;
        // The % of tokens that have been used for swaps
        uint256 usedForSwaps;
        // If `true` it will ignore the strikes that are ITM
        bool ignoreITM;
    }

    /**
     * @notice Buys a % of puts according to strategy limits
     * @return The updated % of options bought
     */
    function buyOptions(BuyOptionsInput memory _input) public returns (uint256, uint256[] memory) {
        if (_input.collateralPercentages.length > _input.limits.length) {
            revert InvalidNumberOfPercentages();
        }

        // Nothing to do
        if (_input.collateralBalance == 0 || block.timestamp >= _input.ssovExpiry) {
            // Since we didn't buy anything we just return the current % of buys
            return (0, _input.used);
        }

        IERC20 collateral = _input.ssov.collateralToken();

        // Approve so we can use `2Crv` to buy options
        collateral.approve(address(_input.ssov), type(uint256).max);

        // Get the ssov epoch strikes
        StrikePerformance[] memory strikes = getSortedStrikes(_input.ssov, _input.ssovEpoch);

        if (strikes.length > _input.collateralPercentages.length) {
            revert InvalidNumberOfPercentages();
        }

        uint256 spent;
        uint256 percentageIndex;

        for (uint256 i; i < strikes.length; i++) {
            if (_input.ignoreITM == true && strikes[i].itm == true) {
                continue;
            }

            if (_input.collateralPercentages[percentageIndex] == 0) {
                percentageIndex++;
                continue;
            }

            uint256 strikeIndex = strikes[i].index;
            // Check that the order of strikes is the one expected by the caller
            if (_input.strikesOrderMatch[i] != strikeIndex) {
                revert InvalidStrikeOrder(_input.strikesOrderMatch[i], strikeIndex);
            }

            if (
                _input.used[percentageIndex] + _input.collateralPercentages[percentageIndex]
                    > _input.limits[percentageIndex]
            ) {
                percentageIndex++;
                continue;
            }

            uint256 availableCollateral =
                (_input.collateralBalance * _input.collateralPercentages[percentageIndex]) / basePercentage;

            // Estimate the amount of options we can buy with `availableCollateral`
            uint256 optionsToBuy =
                _estimateOptionsPerToken(_input.ssov, availableCollateral, strikes[i].strike, _input.ssovExpiry);

            // Purchase the options
            // NOTE: This will fail if there is not enough liquidity
            (uint256 premium, uint256 fee) = _input.ssov.purchase(strikeIndex, optionsToBuy, address(this));

            // Update buy percentages
            _input.used[percentageIndex] += _input.collateralPercentages[percentageIndex];
            spent = premium + fee;
            percentageIndex++;
        }

        // Reset approvals
        collateral.approve(address(_input.ssov), 0);

        // Return the updated % of options bought
        return (spent, _input.used);
    }

    /**
     * @notice Swaps a % of tokens to buy calls using strategy limits
     * @return The updated % of swapped tokens
     */
    function swapAndBuyOptions(SwapAndBuyOptionsInput memory _input)
        external
        returns (uint256, uint256, uint256[] memory)
    {
        uint256 collateralFromSwap;
        // Swap
        if (_input.swapParams.desc.amount > 0 && _input.swapPercentage + _input.usedForSwaps <= _input.swapLimit) {
            _input.tokenToSwap.approve(address(oneInch), _input.swapParams.desc.amount);
            (collateralFromSwap,) =
                oneInch.swap(_input.swapParams.caller, _input.swapParams.desc, _input.swapParams.data);

            _input.usedForSwaps += _input.swapPercentage;
        }

        // Buy options
        (uint256 spent, uint256[] memory used) = buyOptions(
            BuyOptionsInput(
                _input.ssov,
                _input.ssovEpoch,
                _input.ssovExpiry,
                _input.collateralBalance,
                _input.collateralPercentages,
                _input.limits,
                _input.used,
                _input.strikesOrderMatch,
                _input.ignoreITM
            )
        );

        return (spent, _input.usedForSwaps, used);
    }

    /**
     * @notice Rerturns the `_ssov` `_ssovEpoch` strikes ordered by their distance to the underlying
     * asset price
     * @param _ssov The SSOV contract
     * @param _ssovEpoch The epoch we want to get the strikes on `_ssov`
     */
    function getSortedStrikes(ISsovV3 _ssov, uint256 _ssovEpoch) public view returns (StrikePerformance[] memory) {
        uint256 currentPrice = _ssov.getUnderlyingPrice();
        uint256[] memory strikes = _ssov.getEpochData(_ssovEpoch).strikes;
        bool isPut = _ssov.isPut();

        uint256 delta;
        bool itm;

        StrikePerformance[] memory performances = new StrikePerformance[](
            strikes.length
        );

        for (uint256 i; i < strikes.length; i++) {
            delta = strikes[i] > currentPrice ? strikes[i] - currentPrice : currentPrice - strikes[i];
            itm = isPut ? strikes[i] > currentPrice : currentPrice > strikes[i];
            performances[i] = StrikePerformance(i, strikes[i], delta, itm);
        }

        _sortPerformances(performances, int256(0), int256(performances.length - 1));

        return performances;
    }

    /**
     * @notice Estimates the amount of options that can be buy with `_tokenAmount`
     * @param _ssov The ssov contract
     * @param _tokenAmount The amount of tokens
     * @param _strike The strike to calculate
     * @param _expiry The ssov epoch expiry
     */
    function _estimateOptionsPerToken(ISsovV3 _ssov, uint256 _tokenAmount, uint256 _strike, uint256 _expiry)
        private
        view
        returns (uint256)
    {
        // The amount of tokens used to buy an amount of options is
        // the premium + purchase fee.
        // We calculate those values using `precision` as the amount.
        // Knowing how many tokens that cost we can estimate how many
        // Options we can buy using `_tokenAmount`
        uint256 precision = 10000e18;

        uint256 premiumPerOption = _ssov.calculatePremium(_strike, precision, _expiry);
        uint256 feePerOption = _ssov.calculatePurchaseFees(_strike, precision);

        uint256 pricePerOption = premiumPerOption + feePerOption;

        return (_tokenAmount * precision) / pricePerOption;
    }

    /**
     * @notice Sorts `_strikes` using quick sort
     * @param _strikes The array of strikes to sort
     * @param _left The lower index of the `_strikes` array
     * @param _right The higher index of the `_strikes` array
     */
    function _sortPerformances(StrikePerformance[] memory _strikes, int256 _left, int256 _right) internal view {
        int256 i = _left;
        int256 j = _right;

        uint256 pivot = _strikes[uint256(_left + (_right - _left) / 2)].delta;

        while (i < j) {
            while (_strikes[uint256(i)].delta < pivot) {
                i++;
            }
            while (pivot < _strikes[uint256(j)].delta) {
                j--;
            }

            if (i <= j) {
                (_strikes[uint256(i)], _strikes[uint256(j)]) = (_strikes[uint256(j)], _strikes[uint256(i)]);
                i++;
                j--;
            }
        }

        if (_left < j) {
            _sortPerformances(_strikes, _left, j);
        }

        if (i < _right) {
            _sortPerformances(_strikes, i, _right);
        }
    }

    error InvalidAmountOfMinimumOutputs();
    error InvalidNumberOfPercentages();
    error InvalidStrikeOrder(uint256 expected, uint256 actual);
}


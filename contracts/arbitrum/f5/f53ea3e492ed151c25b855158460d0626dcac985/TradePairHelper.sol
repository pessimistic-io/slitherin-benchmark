// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./ITradePair.sol";
import "./ITradePairHelper.sol";

contract TradePairHelper is ITradePairHelper {
    /**
     * @notice Returns the current prices (min and max) of the given TradePairs
     * @param tradePairs_ The TradePairs to get the current prices of
     * @return prices PricePairy[] of min and max prices
     */
    function pricesOf(ITradePair[] calldata tradePairs_) external view override returns (PricePair[] memory prices) {
        prices = new PricePair[](tradePairs_.length);
        for (uint256 i; i < tradePairs_.length; ++i) {
            (int256 minPrice, int256 maxPrice) = tradePairs_[i].getCurrentPrices();

            prices[i] = PricePair(minPrice, maxPrice);
        }
    }

    function detailsOfPositions(address[] calldata tradePairs_, uint256[][] calldata positionIds_)
        external
        view
        returns (PositionDetails[][] memory positionDetails)
    {
        require(
            tradePairs_.length == positionIds_.length,
            "TradePairHelper::batchPositionDetails: TradePair and PositionId arrays must be of same length"
        );

        positionDetails = new PositionDetails[][](positionIds_.length);

        for (uint256 t; t < tradePairs_.length; ++t) {
            positionDetails[t] = new PositionDetails[](positionIds_[t].length);

            for (uint256 i; i < positionIds_[t].length; ++i) {
                positionDetails[t][i] = ITradePair(tradePairs_[t]).detailsOfPosition(positionIds_[t][i]);
            }
        }
    }
}


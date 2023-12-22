// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ILens {
    struct ProcessedPosition {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        uint256 hasRealisedProfit;
        uint256 realisedPnl;
        uint256 lastIncreasedTime;
        bool hasProfit;
        uint256 delta;
        address collateralToken;
        address indexToken;
        bool isLong;
    }

    function getAllPositionsProcessed(
        address account
    ) external view returns (ProcessedPosition[] memory result);
}


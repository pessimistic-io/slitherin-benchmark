// SPDX-License-Identifier: BSD-3-CLAUSE
pragma solidity 0.8.9;

import { IAmm } from "./IAmm.sol";

interface IClearingHouse {
    enum Side {
        BUY,
        SELL
    }

    /// @notice This struct records personal position information
    /// @param size denominated in amm.baseAsset
    /// @param margin isolated margin
    /// @param openNotional the quoteAsset value of position when opening position. the cost of the position
    /// @param lastUpdatedCumulativePremiumFraction for calculating funding payment, record at the moment every time when trader open/reduce/close position
    /// @param blockNumber the block number of the last position
    struct Position {
        int256 size;
        int256 margin;
        uint256 openNotional;
        int256 lastUpdatedCumulativePremiumFraction;
        uint256 blockNumber;
    }

    function addMargin(IAmm _amm, uint256 _addedMargin) external;

    function removeMargin(IAmm _amm, uint256 _removedMargin) external;

    function settlePosition(IAmm _amm) external;

    function openPosition(
        IAmm _amm,
        Side _side,
        uint256 _amount,
        uint256 _leverage,
        uint256 _oppositeAmountLimit,
        bool _isQuote
    ) external;

    function closePosition(IAmm _amm, uint256 _quoteAssetAmountLimit) external;

    function liquidate(IAmm _amm, address _trader) external;

    function payFunding(IAmm _amm) external;

    // VIEW FUNCTIONS
    function getMarginRatio(IAmm _amm, address _trader) external view returns (int256);

    function getPosition(IAmm _amm, address _trader) external view returns (Position memory);

    function getVaultFor(IAmm _amm) external view returns (uint256);
}


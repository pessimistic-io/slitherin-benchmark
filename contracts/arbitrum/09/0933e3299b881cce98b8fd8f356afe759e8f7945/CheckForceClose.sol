/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DeDeLend
 * Copyright (C) 2023 DeDeLend
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/
pragma solidity ^0.8.0;


import "./DecimalMath.sol";
import "./BlackScholes.sol";
import "./Ownable.sol";
import "./IERC721.sol";

interface IBaseExchangeAdapter {
    enum PriceType {
        MIN_PRICE, // minimise the spot based on logic in adapter - can revert
        MAX_PRICE, // maximise the spot based on logic in adapter
        REFERENCE,
        FORCE_MIN, // minimise the spot based on logic in adapter - shouldn't revert unless feeds are compromised
        FORCE_MAX
    }

    function getSpotPriceForMarket(address optionMarket,
        PriceType pricing
    ) external view returns (uint spotPrice);

    function rateAndCarry(address /*_optionMarket*/) external view returns (int);
}

interface ILiquidityPool {
    struct Liquidity {
        // Amount of liquidity available for option collateral and premiums
        uint freeLiquidity;
        // Amount of liquidity available for withdrawals - different to freeLiquidity
        uint burnableLiquidity;
        // Amount of liquidity reserved for long options sold to traders
        uint reservedCollatLiquidity;
        // Portion of liquidity reserved for delta hedging (quote outstanding)
        uint pendingDeltaLiquidity;
        // Current value of delta hedge
        uint usedDeltaLiquidity;
        // Net asset value, including everything and netOptionValue
        uint NAV;
        // longs scaled down by this factor in a contract adjustment event
        uint longScaleFactor;
    }
}

interface IOptionMarket {
    enum OptionType {
        LONG_CALL,
        LONG_PUT,
        SHORT_CALL_BASE,
        SHORT_CALL_QUOTE,
        SHORT_PUT_QUOTE
    }

    enum TradeDirection {
        OPEN,
        CLOSE,
        LIQUIDATE
    }

    struct Strike {
        // strike listing identifier
        uint id;
        // strike price
        uint strikePrice;
        // volatility component specific to the strike listing (boardIv * skew = vol of strike)
        uint skew;
        // total user long call exposure
        uint longCall;
        // total user short call (base collateral) exposure
        uint shortCallBase;
        // total user short call (quote collateral) exposure
        uint shortCallQuote;
        // total user long put exposure
        uint longPut;
        // total user short put (quote collateral) exposure
        uint shortPut;
        // id of board to which strike belongs
        uint boardId;
    }

    struct OptionBoard {
        // board identifier
        uint id;
        // expiry of all strikes belonging to board
        uint expiry;
        // volatility component specific to board (boardIv * skew = vol of strike)
        uint iv;
        // admin settable flag blocking all trading on this board
        bool frozen;
        // list of all strikes belonging to this board
        uint[] strikeIds;
    }

    struct TradeInputParameters {
        // id of strike
        uint strikeId;
        // OptionToken ERC721 id for position (set to 0 for new positions)
        uint positionId;
        // number of sub-orders to break order into (reduces slippage)
        uint iterations;
        // type of option to trade
        OptionType optionType;
        // number of contracts to trade
        uint amount;
        // final amount of collateral to leave in OptionToken position
        uint setCollateralTo;
        // revert trade if totalCost is below this value
        uint minTotalCost;
        // revert trade if totalCost is above this value
        uint maxTotalCost;
        // referrer emitted in Trade event, no on-chain interaction
        address referrer;
    }

    struct TradeParameters {
        bool isBuy;
        bool isForceClose;
        TradeDirection tradeDirection;
        OptionType optionType;
        uint amount;
        uint expiry;
        uint strikePrice;
        uint spotPrice;
        ILiquidityPool.Liquidity liquidity;
    }

    struct Result {
        uint positionId;
        uint totalCost;
        uint totalFee;
    }

    function getStrikeAndBoard(uint strikeId) external view returns (Strike memory, OptionBoard memory);
    function closePosition(TradeInputParameters memory params) external returns (Result memory result);
    function forceClosePosition(TradeInputParameters memory params) external returns (Result memory result);
    function quoteAsset() external view returns (address);
}

interface IOptionToken is IERC721 {
    enum PositionState {
        EMPTY,
        ACTIVE,
        CLOSED,
        LIQUIDATED,
        SETTLED,
        MERGED
    }

    struct OptionPosition {
        uint positionId;
        uint strikeId;
        IOptionMarket.OptionType optionType;
        uint amount;
        uint collateral;
        PositionState state;
    }
    function getOptionPosition(uint positionId) external view returns (OptionPosition memory);
}

interface IOptionMarketPricer {
    struct TradeLimitParameters {
        // Delta cutoff past which no options can be traded (optionD > minD && optionD < 1 - minD) - using call delta
        int minDelta;
        // Delta cutoff at which ForceClose can be called (optionD < minD || optionD > 1 - minD) - using call delta
        int minForceCloseDelta;
        // Time when trading closes. Only ForceClose can be called after this
        uint tradingCutoff;
        // Lowest baseIv for a board that can be traded for regular option opens/closes
        uint minBaseIV;
        // Maximal baseIv for a board that can be traded for regular option opens/closes
        uint maxBaseIV;
        // Lowest skew for a strike that can be traded for regular option opens/closes
        uint minSkew;
        // Maximal skew for a strike that can be traded for regular option opens/closes
        uint maxSkew;
        // Minimal vol traded for regular option opens/closes (baseIv * skew)
        uint minVol;
        // Maximal vol traded for regular option opens/closes (baseIv * skew)
        uint maxVol;
        // Absolute lowest skew that ForceClose can go to
        uint absMinSkew;
        // Absolute highest skew that ForceClose can go to
        uint absMaxSkew;
        // Cap the skew the abs max/min skews - only relevant to liquidations
        bool capSkewsToAbs;
    }

    function tradeLimitParams() external view returns(TradeLimitParameters memory);
    function ivImpactForTrade(
        IOptionMarket.TradeParameters memory trade,
        uint boardBaseIv,
        uint strikeSkew
    ) external view returns (uint newBaseIv, uint newSkew);
}

interface IOptionGreekCache {
    struct NetGreeks {
        int netDelta;
        int netStdVega;
        int netOptionValue;
    }

    struct StrikeGreeks {
        int callDelta;
        int putDelta;
        uint stdVega;
        uint callPrice;
        uint putPrice;
    }

    struct OptionBoardCache {
        uint id;
        uint[] strikes;
        uint expiry;
        uint iv;
        NetGreeks netGreeks;
        uint updatedAt;
        uint updatedAtPrice;
        uint maxSkewVariance;
        uint ivVariance;
    }

    struct StrikeCache {
        uint id;
        uint boardId;
        uint strikePrice;
        uint skew;
        StrikeGreeks greeks;
        int callExposure; // long - short
        int putExposure; // long - short
        uint skewVariance; // (GWAVSkew - skew)
    }

    function getStrikeCache(uint strikeId) external view returns (StrikeCache memory);
    function getOptionBoardCache(uint boardId) external view returns (OptionBoardCache memory);
}

// CheckForceClose contract definition
contract CheckForceClose is Ownable {
    using DecimalMath for uint;
    using BlackScholes for BlackScholes.BlackScholesInputs;

    // Contract instances for price feeds, exchange adapter, and Lyra options protocol
    IBaseExchangeAdapter public exchangeAdapter;
    IOptionToken public optionToken;
    IOptionMarket public optionMarket;
    IOptionMarketPricer public optionPricer;
    IOptionGreekCache public greekCache;

    // Constructor to initialize the contract with the required ERC721 contract and operational treasury addresses
    constructor(
        address _exchangeAdapter,
        address _optionToken,
        address _optionMarket,
        address _optionPricer,
        address _greekCache
    ) {
        exchangeAdapter = IBaseExchangeAdapter(_exchangeAdapter);
        optionToken = IOptionToken(_optionToken);
        optionMarket = IOptionMarket(_optionMarket);
        optionPricer = IOptionMarketPricer(_optionPricer);
        greekCache = IOptionGreekCache(_greekCache);
    }

    function setExchangeAdapter(address newExchangeAdapter) external onlyOwner {
        exchangeAdapter = IBaseExchangeAdapter(newExchangeAdapter);
    }

    // Function to check if a position should be force closed based on market conditions
    function checkForceClose(uint256 tokenId) public view returns (bool) {
        // Retrieve position info, strike, and board details
        PositionAndBoard memory posBoard = getPositionAndBoard(tokenId);

        // Obtain trading limits and check if the current time is past the trading cutoff
        IOptionMarketPricer.TradeLimitParameters memory limitParams = optionPricer.tradeLimitParams();
        bool isPostCutoff = block.timestamp + limitParams.tradingCutoff > posBoard.optBoard.expiry;

        // Define trade parameters and compute the new skew
        uint newSkew = calculateNewSkew(posBoard.positionInfo, posBoard.optBoard, posBoard.optStrike);

        // Check if the new skew is within acceptable limits
        if (newSkew <= limitParams.absMinSkew || newSkew >= limitParams.absMaxSkew) {
            return false;
        }

        // Determine the appropriate pricing for the position type
        IBaseExchangeAdapter.PriceType pricing = getPositionPricing(posBoard.positionInfo.optionType);

        // Calculate the time to maturity, volatility, spot price, strike price, and rate
        CalculationData memory calcData = getCalculationData(
            posBoard.strikeCache,
            posBoard.boardCache,
            pricing
        );

        // Calculate the Black-Scholes prices, delta, and vega
        BlackScholes.PricesDeltaStdVega memory pricesDeltaStdVega = BlackScholes
        .BlackScholesInputs({
            timeToExpirySec: calcData.timeToMaturitySec,
            volatilityDecimal: calcData.volatilityDecimal,
            spotDecimal: calcData.spotDecimal,
            strikePriceDecimal: calcData.strikePriceDecimal,
            rateDecimal: calcData.rateDecimal
        })
        .pricesDeltaStdVega();

        // Check if the position should be force closed based on delta and trading cutoff
        if (!isPostCutoff) {
            if (
                pricesDeltaStdVega.callDelta > limitParams.minForceCloseDelta &&
                pricesDeltaStdVega.callDelta < (int(DecimalMath.UNIT) - limitParams.minForceCloseDelta)
            ) {
                return false;
            }
        }
        return true;
    }

    struct PositionAndBoard {
        IOptionToken.OptionPosition positionInfo;
        IOptionMarket.Strike optStrike;
        IOptionMarket.OptionBoard optBoard;
        IOptionGreekCache.StrikeCache strikeCache;
        IOptionGreekCache.OptionBoardCache boardCache;
    }

    function getPositionAndBoard(uint256 tokenId) internal view returns (PositionAndBoard memory) {
        IOptionToken.OptionPosition memory positionInfo = optionToken.getOptionPosition(tokenId);
        (IOptionMarket.Strike memory optStrike, IOptionMarket.OptionBoard memory optBoard) = optionMarket.getStrikeAndBoard(positionInfo.strikeId);

        IOptionGreekCache.StrikeCache memory strikeCache = greekCache.getStrikeCache(optStrike.id);
        IOptionGreekCache.OptionBoardCache memory boardCache = greekCache.getOptionBoardCache(strikeCache.boardId);

        return PositionAndBoard({
            positionInfo: positionInfo,
            optStrike: optStrike,
            optBoard: optBoard,
            strikeCache: strikeCache,
            boardCache: boardCache
        });
    }

    function calculateNewSkew(
        IOptionToken.OptionPosition memory positionInfo,
        IOptionMarket.OptionBoard memory optBoard,
        IOptionMarket.Strike memory optStrike
    ) internal view returns (uint) {
        IOptionMarket.TradeParameters memory trade;
        trade.amount = positionInfo.amount;
        trade.isBuy = !_isLong(IOptionMarket.OptionType(uint256(positionInfo.optionType)));
        (, uint newSkew) = optionPricer.ivImpactForTrade(trade, optBoard.iv, optStrike.skew);
        return newSkew;
    }

    function getPositionPricing(IOptionMarket.OptionType optionType) internal pure returns (IBaseExchangeAdapter.PriceType) {
        if (optionType == IOptionMarket.OptionType.LONG_CALL || optionType == IOptionMarket.OptionType.SHORT_PUT_QUOTE) {
            return IBaseExchangeAdapter.PriceType.FORCE_MIN;
        } else {
            return IBaseExchangeAdapter.PriceType.FORCE_MAX;
        }
    }

    struct CalculationData {
        uint timeToMaturitySec;
        uint256 volatilityDecimal;
        uint256 spotDecimal;
        uint256 strikePriceDecimal;
        int256 rateDecimal;
    }

    function getCalculationData(
        IOptionGreekCache.StrikeCache memory strikeCache,
        IOptionGreekCache.OptionBoardCache memory boardCache,
        IBaseExchangeAdapter.PriceType pricing
    ) internal view returns (CalculationData memory) {
        uint timeToMaturitySec = _timeToMaturitySeconds(boardCache.expiry);
        uint256 volatilityDecimal = boardCache.iv.multiplyDecimal(strikeCache.skew);
        uint256 spotDecimal = exchangeAdapter.getSpotPriceForMarket(address(optionMarket), pricing);
        uint256 strikePriceDecimal = strikeCache.strikePrice;
        int256 rateDecimal = exchangeAdapter.rateAndCarry(address(optionMarket));
        return CalculationData({
            timeToMaturitySec: timeToMaturitySec,
            volatilityDecimal: volatilityDecimal,
            spotDecimal: spotDecimal,
            strikePriceDecimal: strikePriceDecimal,
            rateDecimal: rateDecimal
        });
    }

    // Function to determine if the option type is long
    function _isLong(IOptionMarket.OptionType optionType) internal pure returns (bool) {
        return (optionType == IOptionMarket.OptionType.LONG_CALL || optionType == IOptionMarket.OptionType.LONG_PUT);
    }

    // Function to calculate the time to maturity in seconds
    function _timeToMaturitySeconds(uint expiry) internal view returns (uint) {
        return _getSecondsTo(block.timestamp, expiry);
    }

    // Function to calculate the seconds between two timestamps
    function _getSecondsTo(uint fromTime, uint toTime) internal pure returns (uint) {
        if (toTime > fromTime) {
            return toTime - fromTime;
        }
        return 0;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./ISymbol.sol";
import "./SymbolStorage.sol";
import "./IOracleManager.sol";
import "./SafeMath.sol";
import "./DpmmLinearPricing.sol";
import "./NameVersion.sol";

contract SymbolImplementationFutures is SymbolStorage, NameVersion {

    using SafeMath for uint256;
    using SafeMath for int256;

    int256 constant ONE = 1e18;

    address public immutable manager;

    address public immutable oracleManager;

    bytes32 public immutable symbolId;

    bytes32 public immutable priceId; // used to get indexPrice from oracleManager

    int256  public immutable feeRatio;

    int256  public immutable alpha;

    int256  public immutable fundingPeriod; // in seconds

    int256  public immutable minTradeVolume;

    int256  public immutable initialMarginRatio;

    int256  public immutable maintenanceMarginRatio;

    int256  public immutable pricePercentThreshold; // max price percent change to force settlement

    uint256 public immutable timeThreshold; // max time delay in seconds to force settlement

    int256  public immutable startingPriceShiftLimit; // Max price shift in percentage allowed before trade/liquidation

    int256  public immutable jumpLimitRatio;

    int256  public immutable initialOpenVolume;

    int256  public immutable openInterestMultiplier;

    bool    public immutable isCloseOnly;

    modifier _onlyManager_() {
        require(msg.sender == manager, 'SymbolImplementationFutures: only manager');
        _;
    }

    constructor (
        address manager_,
        address oracleManager_,
        string[2] memory symbols_,
        int256[12] memory parameters_,
        bool isCloseOnly_
    ) NameVersion('SymbolImplementationFutures', '3.0.4')
    {
        manager = manager_;
        oracleManager = oracleManager_;
        symbol = symbols_[0];
        symbolId = keccak256(abi.encodePacked(symbols_[0]));
        priceId = keccak256(abi.encodePacked(symbols_[1]));

        feeRatio = parameters_[0];
        alpha = parameters_[1];
        fundingPeriod = parameters_[2];
        minTradeVolume = parameters_[3];
        initialMarginRatio = parameters_[4];
        maintenanceMarginRatio = parameters_[5];
        pricePercentThreshold = parameters_[6];
        timeThreshold = parameters_[7].itou();
        startingPriceShiftLimit = parameters_[8];
        jumpLimitRatio = parameters_[9];
        initialOpenVolume = parameters_[10];
        openInterestMultiplier = parameters_[11];
        isCloseOnly = isCloseOnly_;

        require(
            IOracleManager(oracleManager_).value(priceId) != 0,
            'SymbolImplementationFutures.constructor: no price oralce'
        );
    }

    function hasPosition(uint256 pTokenId) external view returns (bool) {
        return positions[pTokenId].volume != 0;
    }

    //================================================================================

    function settleOnAddLiquidity(int256 liquidity)
    external _onlyManager_ returns (ISymbol.SettlementOnAddLiquidity memory s)
    {
        Data memory data;

        if (_getNetVolumeAndCostWithSkip(data)) return s;
        if (_getTimestampAndPriceWithSkip(data)) return s;
        _getFunding(data, liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        s.settled = true;
        s.funding = data.funding;
        s.deltaTradersPnl = data.tradersPnl - tradersPnl;
        s.deltaInitialMarginRequired = data.initialMarginRequired - initialMarginRequired;

        indexPrice = data.curIndexPrice;
        fundingTimestamp = data.curTimestamp;
        cumulativeFundingPerVolume = data.cumulativeFundingPerVolume;
        tradersPnl = data.tradersPnl;
        initialMarginRequired = data.initialMarginRequired;
    }

    function settleOnRemoveLiquidity(int256 liquidity, int256 removedLiquidity)
    external _onlyManager_ returns (ISymbol.SettlementOnRemoveLiquidity memory s)
    {
        Data memory data;

        if (_getNetVolumeAndCostWithSkip(data)) return s;
        _getTimestampAndPrice(data);
        _getFunding(data, liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        s.settled = true;
        s.funding = data.funding;
        s.deltaTradersPnl = data.tradersPnl - tradersPnl;
        s.deltaInitialMarginRequired = data.initialMarginRequired - initialMarginRequired;
        s.removeLiquidityPenalty = _getRemoveLiquidityPenalty(data, liquidity - removedLiquidity);

        indexPrice = data.curIndexPrice;
        fundingTimestamp = data.curTimestamp;
        cumulativeFundingPerVolume = data.cumulativeFundingPerVolume;
        tradersPnl = data.tradersPnl;
        initialMarginRequired = data.initialMarginRequired;
    }

    function settleOnTraderWithPosition(uint256 pTokenId, int256 liquidity)
    external _onlyManager_ returns (ISymbol.SettlementOnTraderWithPosition memory s)
    {
        Data memory data;

        _getNetVolumeAndCost(data);
        _getTimestampAndPrice(data);
        _getFunding(data, liquidity);
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        Position memory p = positions[pTokenId];

        s.funding = data.funding;
        s.deltaTradersPnl = data.tradersPnl - tradersPnl;
        s.deltaInitialMarginRequired = data.initialMarginRequired - initialMarginRequired;

        int256 diff;
        unchecked { diff = data.cumulativeFundingPerVolume - p.cumulativeFundingPerVolume; }
        s.traderFunding = p.volume * diff / ONE;

        int256 notional = p.volume * data.curIndexPrice / ONE;
        s.traderPnl = notional - p.cost;
        s.traderInitialMarginRequired = notional.abs() * initialMarginRatio / ONE;

        indexPrice = data.curIndexPrice;
        fundingTimestamp = data.curTimestamp;
        cumulativeFundingPerVolume = data.cumulativeFundingPerVolume;
        tradersPnl = data.tradersPnl;
        initialMarginRequired = data.initialMarginRequired;

        positions[pTokenId].cumulativeFundingPerVolume = data.cumulativeFundingPerVolume;
    }

    // priceLimit: the average trade price cannot exceeds priceLimit
    // for long, averageTradePrice <= priceLimit; for short, averageTradePrice >= priceLimit
    function settleOnTrade(uint256 pTokenId, int256 tradeVolume, int256 liquidity, int256 priceLimit)
    external _onlyManager_ returns (ISymbol.SettlementOnTrade memory s)
    {
        _updateLastNetVolume();

        require(
            tradeVolume != 0 && tradeVolume % minTradeVolume == 0,
            'SymbolImplementationFutures.settleOnTrade: invalid tradeVolume'
        );

        Data memory data;
        _getNetVolumeAndCost(data);
        _getTimestampAndPrice(data);
        _getFunding(data, liquidity);

        Position memory p = positions[pTokenId];

        if (isCloseOnly) {
            require(
                (p.volume > 0 && tradeVolume < 0 && p.volume + tradeVolume >= 0) ||
                (p.volume < 0 && tradeVolume > 0 && p.volume + tradeVolume <= 0),
                'SymbolImplementationFutures.settleOnTrade: close only'
            );
        }

        int256 diff;
        unchecked { diff = data.cumulativeFundingPerVolume - p.cumulativeFundingPerVolume; }
        s.traderFunding = p.volume * diff / ONE;

        s.tradeCost = DpmmLinearPricing.calculateCost(
            _getAdjustedTheoreticalPrice(data, tradeVolume),
            data.K,
            data.netVolume,
            tradeVolume
        );
        s.tradeFee = s.tradeCost.abs() * feeRatio / ONE;

        // check slippage
        int256 averageTradePrice = s.tradeCost * ONE / tradeVolume;
        require(
            (tradeVolume > 0 && averageTradePrice <= priceLimit) ||
            (tradeVolume < 0 && averageTradePrice >= priceLimit),
            'SymbolImplementationFutures.settleOnTrade: slippage exceeds allowance'
        );

        if (!(p.volume >= 0 && tradeVolume >= 0) && !(p.volume <= 0 && tradeVolume <= 0)) {
            int256 absVolume = p.volume.abs();
            int256 absTradeVolume = tradeVolume.abs();
            if (absVolume <= absTradeVolume) {
                s.tradeRealizedCost = s.tradeCost * absVolume / absTradeVolume + p.cost;
            } else {
                s.tradeRealizedCost = p.cost * absTradeVolume / absVolume + s.tradeCost;
            }
        }

        data.netVolume += tradeVolume;
        data.netCost += s.tradeCost - s.tradeRealizedCost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        require(
            DpmmLinearPricing.calculateMarkPrice(data.curIndexPrice, data.K, data.netVolume) > 0,
            'SymbolImplementationFutures.settleOnTrade: exceed mark limit'
        );

        _updateOpenVolume(liquidity, data.curIndexPrice, p.volume, tradeVolume);

        p.volume += tradeVolume;
        p.cost += s.tradeCost - s.tradeRealizedCost;
        p.cumulativeFundingPerVolume = data.cumulativeFundingPerVolume;

        s.funding = data.funding;
        s.deltaTradersPnl = data.tradersPnl - tradersPnl;
        s.deltaInitialMarginRequired = data.initialMarginRequired - initialMarginRequired;
        s.indexPrice = data.curIndexPrice;

        int256 notional = p.volume * data.curIndexPrice / ONE;
        s.traderPnl = notional - p.cost;
        s.traderInitialMarginRequired = notional.abs() * initialMarginRatio / ONE;

        if (p.volume == 0) {
            s.positionChangeStatus = -1;
            nPositionHolders--;
        } else if (p.volume - tradeVolume == 0) {
            s.positionChangeStatus = 1;
            nPositionHolders++;
        }

        netVolume = data.netVolume;
        netCost = data.netCost;
        indexPrice = data.curIndexPrice;
        fundingTimestamp = data.curTimestamp;
        cumulativeFundingPerVolume = data.cumulativeFundingPerVolume;
        tradersPnl = data.tradersPnl;
        initialMarginRequired = data.initialMarginRequired;

        positions[pTokenId] = p;
    }

    function settleOnLiquidate(uint256 pTokenId, int256 liquidity)
    external _onlyManager_ returns (ISymbol.SettlementOnLiquidate memory s)
    {
        _updateLastNetVolume();

        Data memory data;

        _getNetVolumeAndCost(data);
        _getTimestampAndPrice(data);
        _getFunding(data, liquidity);

        Position memory p = positions[pTokenId];

        // check price shift
        int256 netVolumeShiftAllowance = startingPriceShiftLimit * ONE / data.K;
        require(
            (p.volume >= 0 && data.netVolume + netVolumeShiftAllowance >= lastNetVolume) ||
            (p.volume <= 0 && data.netVolume <= lastNetVolume + netVolumeShiftAllowance),
            'SymbolImplementationFutures.settleOnLiquidate: slippage exceeds allowance'
        );

        int256 diff;
        unchecked { diff = data.cumulativeFundingPerVolume - p.cumulativeFundingPerVolume; }
        s.traderFunding = p.volume * diff / ONE;

        s.tradeVolume = -p.volume;
        s.tradeCost = DpmmLinearPricing.calculateCost(
            _getAdjustedTheoreticalPrice(data, -p.volume),
            data.K,
            data.netVolume,
            -p.volume
        );
        s.tradeRealizedCost = s.tradeCost + p.cost;

        data.netVolume -= p.volume;
        data.netCost -= p.cost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        _updateOpenVolume(liquidity, data.curIndexPrice, p.volume, -p.volume);

        s.funding = data.funding;
        s.deltaTradersPnl = data.tradersPnl - tradersPnl;
        s.deltaInitialMarginRequired = data.initialMarginRequired - initialMarginRequired;
        s.indexPrice = data.curIndexPrice;

        int256 notional = p.volume * data.curIndexPrice / ONE;
        s.traderPnl = notional - p.cost;
        s.traderMaintenanceMarginRequired = notional.abs() * maintenanceMarginRatio / ONE;

        netVolume = data.netVolume;
        netCost = data.netCost;
        indexPrice = data.curIndexPrice;
        fundingTimestamp = data.curTimestamp;
        cumulativeFundingPerVolume = data.cumulativeFundingPerVolume;
        tradersPnl = data.tradersPnl;
        initialMarginRequired = data.initialMarginRequired;
        if (p.volume != 0) {
            nPositionHolders--;
        }

        delete positions[pTokenId];
    }

    //================================================================================

    struct Data {
        uint256 preTimestamp;
        uint256 curTimestamp;
        int256  preIndexPrice;
        int256  curIndexPrice;
        int256  priceJump;
        int256  netVolume;
        int256  netCost;
        int256  cumulativeFundingPerVolume;
        int256  K;
        int256  tradersPnl;
        int256  initialMarginRequired;
        int256  funding;
    }

    function _getNetVolumeAndCost(Data memory data) internal view {
        data.netVolume = netVolume;
        data.netCost = netCost;
    }

    function _getNetVolumeAndCostWithSkip(Data memory data) internal view returns (bool) {
        data.netVolume = netVolume;
        if (data.netVolume == 0) {
            return true;
        }
        data.netCost = netCost;
        return false;
    }

    function _getTimestampAndPrice(Data memory data) internal {
        data.preTimestamp = fundingTimestamp;
        data.curTimestamp = block.timestamp;
        (uint256 curPrice, int256 jump) = IOracleManager(oracleManager).getValueWithJump(priceId);
        data.curIndexPrice = curPrice.utoi();
        data.priceJump = jump;
    }

    function _getTimestampAndPriceWithSkip(Data memory data) internal returns (bool) {
        _getTimestampAndPrice(data);
        data.preIndexPrice = indexPrice;
        return (
            data.curTimestamp < data.preTimestamp + timeThreshold &&
            (data.curIndexPrice - data.preIndexPrice).abs() * ONE < data.preIndexPrice * pricePercentThreshold
        );
    }

    function _calculateK(int256 indexPrice, int256 liquidity) internal view returns (int256) {
        return indexPrice * alpha / liquidity;
    }

    function _getFunding(Data memory data, int256 liquidity) internal view {
        data.cumulativeFundingPerVolume = cumulativeFundingPerVolume;
        data.K = _calculateK(data.curIndexPrice, liquidity);

        int256 markPrice = DpmmLinearPricing.calculateMarkPrice(data.curIndexPrice, data.K, data.netVolume);
        int256 diff = (markPrice - data.curIndexPrice) * (data.curTimestamp - data.preTimestamp).utoi() / fundingPeriod;
        data.funding = data.netVolume * diff / ONE;
        unchecked { data.cumulativeFundingPerVolume += diff; }
    }

    function _getTradersPnl(Data memory data) internal pure {
        data.tradersPnl = -DpmmLinearPricing.calculateCost(data.curIndexPrice, data.K, data.netVolume, -data.netVolume) - data.netCost;
    }

    function _getInitialMarginRequired(Data memory data) internal view {
        data.initialMarginRequired = data.netVolume.abs() * data.curIndexPrice / ONE * initialMarginRatio / ONE;
    }

    function _getRemoveLiquidityPenalty(Data memory data, int256 newLiquidity)
    internal view returns (int256)
    {
        int256 newK = _calculateK(data.curIndexPrice, newLiquidity);
        int256 newPnl = -DpmmLinearPricing.calculateCost(data.curIndexPrice, newK, data.netVolume, -data.netVolume) - data.netCost;
        return newPnl - data.tradersPnl;
    }

    function _getAdjustedTheoreticalPrice(Data memory data, int256 tradeVolume)
    internal view returns (int256 adjustedTheoreticalPrice)
    {
        adjustedTheoreticalPrice = data.curIndexPrice;
        int256 jump;

        if (
            data.priceJump > 0 && tradeVolume < 0 ||
            data.priceJump < 0 && tradeVolume > 0
        ) {
            jump += data.priceJump.abs();
        }

        if (jump != 0) {
            int256 jumpLimit = data.curIndexPrice * jumpLimitRatio / ONE;
            if (jump > jumpLimit * 2) {
                if (tradeVolume > 0) {
                    adjustedTheoreticalPrice += jump - jumpLimit;
                } else {
                    adjustedTheoreticalPrice -= jump - jumpLimit;
                }
            }
        }
    }

    // update lastNetVolume if this is the first transaction in current block
    function _updateLastNetVolume() internal {
        if (block.number > lastNetVolumeBlock) {
            lastNetVolume = netVolume;
            lastNetVolumeBlock = block.number;
        }
    }

    // update open volume
    function _updateOpenVolume(int256 liquidity, int256 curIndexPrice, int256 curVolume, int256 tradeVolume) internal {
        int256 curOpenVolume;
        if (openVolumeInitialized) {
            curOpenVolume = openVolume;
        } else {
            curOpenVolume = initialOpenVolume;
            openVolumeInitialized = true;
        }

        int256 deltaOpenVolume = (curVolume + tradeVolume).abs() - curVolume.abs();
        curOpenVolume += deltaOpenVolume;
        require(curOpenVolume >= 0, 'SymbolImplementationFutures._updateOpenVolume: Negative open volume');
        openVolume = curOpenVolume;

        if (deltaOpenVolume > 0) {
            require(
                initialMarginRatio * openInterestMultiplier / alpha >= curIndexPrice * curOpenVolume / liquidity,
                'SymbolImplementationFutures._updateOpenVolume: exceed max open interest'
            );
        }
    }

}


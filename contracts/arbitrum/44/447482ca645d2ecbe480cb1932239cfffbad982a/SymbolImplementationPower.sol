// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./ISymbol.sol";
import "./SymbolStorage.sol";
import "./IOracleManager.sol";
import "./SafeMath.sol";
import "./DpmmLinearPricing.sol";
import "./NameVersion.sol";

contract SymbolImplementationPower is SymbolStorage, NameVersion {

    using SafeMath for uint256;
    using SafeMath for int256;

    int256 constant ONE = 1e18;

    uint256 public constant power = 2;

    address public immutable manager;

    address public immutable oracleManager;

    bytes32 public immutable symbolId;

    bytes32 public immutable priceId; // used to get indexPrice from oracleManager

    bytes32 public immutable volatilityId; // used to get volatility from oracleManager

    int256 public immutable feeRatio;

    int256 public immutable alpha;

    int256 public immutable fundingPeriod; // in seconds (without 1e18 base)

    int256 public immutable minTradeVolume;

    int256 public immutable initialMarginRatio;

    int256 public immutable maintenanceMarginRatio;

    int256 public immutable pricePercentThreshold; // max price percent change to force settlement

    uint256 public immutable timeThreshold; // max time delay in seconds (without 1e18 base) to force settlement

    int256 public immutable startingPriceShiftLimit; // Max price shift in percentage allowed before trade/liquidation

    bool   public immutable isCloseOnly;

    modifier _onlyManager_() {
        require(msg.sender == manager, 'SymbolImplementationPower: only manager');
        _;
    }

    constructor (
        address manager_,
        address oracleManager_,
        string[3] memory symbols_,
        int256[9] memory parameters_,
        bool isCloseOnly_
    ) NameVersion('SymbolImplementationPower', '3.0.2')
    {
        manager = manager_;
        oracleManager = oracleManager_;

        symbol = symbols_[0];
        symbolId = keccak256(abi.encodePacked(symbols_[0]));
        priceId = keccak256(abi.encodePacked(symbols_[1]));
        volatilityId = keccak256(abi.encodePacked(symbols_[2]));

        feeRatio = parameters_[0];
        alpha = parameters_[1];
        fundingPeriod = parameters_[2];
        minTradeVolume = parameters_[3];
        initialMarginRatio = parameters_[4];
        maintenanceMarginRatio = parameters_[5];
        pricePercentThreshold = parameters_[6];
        timeThreshold = parameters_[7].itou();
        startingPriceShiftLimit = parameters_[8];

        isCloseOnly = isCloseOnly_;

        require(
            IOracleManager(oracleManager).value(priceId) != 0,
            'SymbolImplementationPower.constructor: no price oracle'
        );
        require(
            IOracleManager(oracleManager).value(volatilityId) != 0,
            'SymbolImplementationPower.constructor: no volatility oracle'
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

        s.traderPnl = p.volume * data.theoreticalPrice / ONE - p.cost;
        s.traderInitialMarginRequired = p.volume.abs() * data.initialMarginPerVolume / ONE;

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
            'SymbolImplementationPower.settleOnTrade: invalid tradeVolume'
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
                'SymbolImplementationPower.settleOnTrade: close only'
            );
        }

        int256 diff;
        unchecked { diff = data.cumulativeFundingPerVolume - p.cumulativeFundingPerVolume; }
        s.traderFunding = p.volume * diff / ONE;

        s.tradeCost = DpmmLinearPricing.calculateCost(
            data.theoreticalPrice,
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
            'SymbolImplementationPower.settleOnTrade: slippage exceeds allowance'
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

        p.volume += tradeVolume;
        p.cost += s.tradeCost - s.tradeRealizedCost;
        p.cumulativeFundingPerVolume = data.cumulativeFundingPerVolume;

        s.funding = data.funding;
        s.deltaTradersPnl = data.tradersPnl - tradersPnl;
        s.deltaInitialMarginRequired = data.initialMarginRequired - initialMarginRequired;
        s.indexPrice = data.curIndexPrice;

        s.traderPnl = p.volume * data.theoreticalPrice / ONE - p.cost;
        s.traderInitialMarginRequired = p.volume.abs() * data.initialMarginPerVolume / ONE;

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
            'SymbolImplementationPower.settleOnLiquidate: slippage exceeds allowance'
        );

        int256 diff;
        unchecked { diff = data.cumulativeFundingPerVolume - p.cumulativeFundingPerVolume; }
        s.traderFunding = p.volume * diff / ONE;

        s.tradeVolume = -p.volume;
        s.tradeCost = DpmmLinearPricing.calculateCost(
            data.theoreticalPrice,
            data.K,
            data.netVolume,
            -p.volume
        );
        s.tradeRealizedCost = s.tradeCost + p.cost;

        data.netVolume -= p.volume;
        data.netCost -= p.cost;
        _getTradersPnl(data);
        _getInitialMarginRequired(data);

        s.funding = data.funding;
        s.deltaTradersPnl = data.tradersPnl - tradersPnl;
        s.deltaInitialMarginRequired = data.initialMarginRequired - initialMarginRequired;
        s.indexPrice = data.curIndexPrice;

        s.traderPnl = p.volume * data.theoreticalPrice / ONE - p.cost;
        s.traderMaintenanceMarginRequired = p.volume.abs() * data.maintenanceMarginPerVolume / ONE;

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
        int256 preIndexPrice;
        int256 curIndexPrice;
        int256 netVolume;
        int256 netCost;
        int256 cumulativeFundingPerVolume;
        int256 K;
        int256 tradersPnl;
        int256 initialMarginRequired;
        int256 funding;

        int256 powerPrice; // S**p
        int256 theoreticalPrice; // S**p / (1 - hT)
        int256 initialMarginPerVolume;
        int256 maintenanceMarginPerVolume;
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

    function _getTimestampAndPrice(Data memory data) internal view {
        data.preTimestamp = fundingTimestamp;
        data.curTimestamp = block.timestamp;
        data.curIndexPrice = IOracleManager(oracleManager).getValue(priceId).utoi();
    }

    function _getTimestampAndPriceWithSkip(Data memory data) internal view returns (bool) {
        _getTimestampAndPrice(data);
        data.preIndexPrice = indexPrice;
        return (
            data.curTimestamp < data.preTimestamp + timeThreshold &&
            (data.curIndexPrice - data.preIndexPrice).abs() * ONE < data.preIndexPrice * pricePercentThreshold
        );
    }

    function _calculateK(int256 theoreticalPrice, int256 liquidity) internal view returns (int256) {
        return int256(power) * theoreticalPrice * alpha / liquidity;
    }

    function _getFunding(Data memory data, int256 liquidity) internal view {
        data.cumulativeFundingPerVolume = cumulativeFundingPerVolume;

        int256 volatility = IOracleManager(oracleManager).getValue(volatilityId).utoi();
        int256 oneHT = ONE - volatility ** 2 / ONE * fundingPeriod / 31536000; // 1 - hT

        data.powerPrice = data.curIndexPrice ** 2 / ONE;
        data.theoreticalPrice = data.powerPrice * ONE / oneHT;

        data.K = _calculateK(data.theoreticalPrice, liquidity);

        int256 markPrice = DpmmLinearPricing.calculateMarkPrice(
            data.theoreticalPrice, data.K, data.netVolume
        );
        int256 diff = (markPrice - data.powerPrice) * (data.curTimestamp - data.preTimestamp).utoi() / fundingPeriod;

        data.funding = data.netVolume * diff / ONE;
        unchecked { data.cumulativeFundingPerVolume += diff; }
    }

    function _getTradersPnl(Data memory data) internal pure {
        data.tradersPnl = -DpmmLinearPricing.calculateCost(data.theoreticalPrice, data.K, data.netVolume, -data.netVolume) - data.netCost;
    }

    function _getInitialMarginRequired(Data memory data) internal view {
        data.maintenanceMarginPerVolume = data.theoreticalPrice * maintenanceMarginRatio / ONE;
        data.initialMarginPerVolume = data.maintenanceMarginPerVolume * initialMarginRatio / maintenanceMarginRatio;
        data.initialMarginRequired = data.netVolume.abs() * data.initialMarginPerVolume / ONE;
    }

    function _getRemoveLiquidityPenalty(Data memory data, int256 newLiquidity)
    internal view returns (int256)
    {
        int256 newK = _calculateK(data.theoreticalPrice, newLiquidity);
        int256 newPnl = -DpmmLinearPricing.calculateCost(data.theoreticalPrice, newK, data.netVolume, -data.netVolume) - data.netCost;
        return newPnl - data.tradersPnl;
    }

    // update lastNetVolume if this is the first transaction in current block
    function _updateLastNetVolume() internal {
        if (block.number > lastNetVolumeBlock) {
            lastNetVolume = netVolume;
            lastNetVolumeBlock = block.number;
        }
    }

}


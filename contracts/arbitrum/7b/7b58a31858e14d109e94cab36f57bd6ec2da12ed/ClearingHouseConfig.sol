// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { SafeOwnable } from "./SafeOwnable.sol";
import { ClearingHouseConfigStorageV2 } from "./ClearingHouseConfigStorage.sol";
import { IClearingHouseConfig } from "./IClearingHouseConfig.sol";

// never inherit any new stateful contract. never change the orders of parent stateful contracts
contract ClearingHouseConfig is IClearingHouseConfig, SafeOwnable, ClearingHouseConfigStorageV2 {
    //
    // EVENT
    //
    event ImRatioChanged(uint24 imRatio);
    event TwapIntervalChanged(uint256 twapInterval);
    event LiquidationPenaltyRatioChanged(uint24 liquidationPenaltyRatio);
    event PartialCloseRatioChanged(uint24 partialCloseRatio);
    event MaxMarketsPerAccountChanged(uint8 maxMarketsPerAccount);
    event SettlementTokenBalanceCapChanged(uint256 cap);
    event MaxFundingRateChanged(uint24 rate);
    event BackstopLiquidityProviderChanged(address indexed account, bool indexed isProvider);
    event DurationRepegOverPriceSpreadChanged(uint256 duration);

    //
    // MODIFIER
    //

    modifier checkRatio(uint24 ratio) {
        // CHC_RO: ratio overflow
        require(ratio <= 1e6, "CHC_RO");
        _;
    }

    //
    // EXTERNAL NON-VIEW
    //

    function initialize() external initializer {
        __SafeOwnable_init();

        _maxMarketsPerAccount = type(uint8).max;
        _imRatio = 0.2e6; // initial-margin ratio, 20% in decimal 6
        _mmRatio = 0.0625e6; // minimum-margin ratio, 6.25% in decimal 6
        _liquidationPenaltyRatio = 0.025e6; // initial penalty ratio, 2.5% in decimal 6
        _partialCloseRatio = 0.25e6; // partial close ratio, 25% in decimal 6
        _maxFundingRate = 0.1e6; // max funding rate, 10% in decimal 6
        // _twapInterval = 15 minutes;
        _twapInterval = 0;
        _settlementTokenBalanceCap = type(uint256).max;
        _durationRepegOverPriceSpread = 8 hours;
    }

    function setImRatio(uint24 imRatioArg) external checkRatio(imRatioArg) onlyOwner {
        _imRatio = imRatioArg;
        emit ImRatioChanged(imRatioArg);
    }

    function setLiquidationPenaltyRatio(
        uint24 liquidationPenaltyRatioArg
    ) external checkRatio(liquidationPenaltyRatioArg) onlyOwner {
        _liquidationPenaltyRatio = liquidationPenaltyRatioArg;
        emit LiquidationPenaltyRatioChanged(liquidationPenaltyRatioArg);
    }

    function setPartialCloseRatio(uint24 partialCloseRatioArg) external checkRatio(partialCloseRatioArg) onlyOwner {
        // CHC_IPCR: invalid partialCloseRatio
        require(partialCloseRatioArg > 0, "CHC_IPCR");

        _partialCloseRatio = partialCloseRatioArg;
        emit PartialCloseRatioChanged(partialCloseRatioArg);
    }

    function setTwapInterval(uint32 twapIntervalArg) external onlyOwner {
        // CHC_ITI: invalid twapInterval
        require(twapIntervalArg != 0, "CHC_ITI");

        _twapInterval = twapIntervalArg;
        emit TwapIntervalChanged(twapIntervalArg);
    }

    function setMaxMarketsPerAccount(uint8 maxMarketsPerAccountArg) external onlyOwner {
        _maxMarketsPerAccount = maxMarketsPerAccountArg;
        emit MaxMarketsPerAccountChanged(maxMarketsPerAccountArg);
    }

    function setSettlementTokenBalanceCap(uint256 cap) external onlyOwner {
        _settlementTokenBalanceCap = cap;
        emit SettlementTokenBalanceCapChanged(cap);
    }

    function setMaxFundingRate(uint24 rate) external onlyOwner {
        _maxFundingRate = rate;
        emit MaxFundingRateChanged(rate);
    }

    function setBackstopLiquidityProvider(address account, bool isProvider) external onlyOwner {
        _backstopLiquidityProviderMap[account] = isProvider;
        emit BackstopLiquidityProviderChanged(account, isProvider);
    }

    function setDurationRepegOverPriceSpread(uint24 durationRepegOverPriceSpreadArg) external onlyOwner {
        _durationRepegOverPriceSpread = durationRepegOverPriceSpreadArg;
        emit DurationRepegOverPriceSpreadChanged(_durationRepegOverPriceSpread);
    }

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IClearingHouseConfig
    function getMaxMarketsPerAccount() external view override returns (uint8) {
        return _maxMarketsPerAccount;
    }

    /// @inheritdoc IClearingHouseConfig
    function getImRatio() external view override returns (uint24) {
        return _imRatio;
    }

    /// @inheritdoc IClearingHouseConfig
    function getMmRatio() external view override returns (uint24) {
        return _mmRatio;
    }

    /// @inheritdoc IClearingHouseConfig
    function getLiquidationPenaltyRatio() external view override returns (uint24) {
        return _liquidationPenaltyRatio;
    }

    /// @inheritdoc IClearingHouseConfig
    function getPartialCloseRatio() external view override returns (uint24) {
        return _partialCloseRatio;
    }

    /// @inheritdoc IClearingHouseConfig
    function getTwapInterval() external view override returns (uint32) {
        return _twapInterval;
    }

    /// @inheritdoc IClearingHouseConfig
    function getSettlementTokenBalanceCap() external view override returns (uint256) {
        return _settlementTokenBalanceCap;
    }

    /// @inheritdoc IClearingHouseConfig
    function getMaxFundingRate() external view override returns (uint24) {
        return _maxFundingRate;
    }

    /// @inheritdoc IClearingHouseConfig
    function isBackstopLiquidityProvider(address account) external view override returns (bool) {
        return _backstopLiquidityProviderMap[account];
    }

    function getDurationRepegOverPriceSpread() external view override returns (uint256 duration) {
        return _durationRepegOverPriceSpread;
    }
}


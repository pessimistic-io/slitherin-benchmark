// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IConfig.sol";
import "./Ownable.sol";

contract Config is IConfig, Ownable {
    address public override priceOracle;

    uint8 public override beta = 70; // 50-200，50 means 0.5
    uint256 public override maxCPFBoost = 10; // default 10
    uint256 public override rebasePriceGap = 5; //0-100 , if 5 means 5%
    uint256 public override rebaseInterval = 3600; // in seconds
    uint256 public override tradingSlippage = 5; //0-100, if 5 means 5%
    uint256 public override initMarginRatio = 800; //if 1000, means margin ratio >= 10%
    uint256 public override liquidateThreshold = 10000; //if 10000, means debt ratio < 100%
    uint256 public override liquidateFeeRatio = 100; //if 100, means liquidator bot get 1% as fee
    uint256 public override feeParameter = 11; // 100 * (1/fee-1)

    mapping(address => bool) public override routerMap;

    constructor() {
        owner = msg.sender;
    }

    function setMaxCPFBoost(uint256 newMaxCPFBoost) external override onlyOwner {
        emit SetMaxCPFBoost(maxCPFBoost, newMaxCPFBoost);
        maxCPFBoost = newMaxCPFBoost;
    }

    function setPriceOracle(address newOracle) external override onlyOwner {
        require(newOracle != address(0), "Config: ZERO_ADDRESS");
        emit PriceOracleChanged(priceOracle, newOracle);
        priceOracle = newOracle;
    }

    function setRebasePriceGap(uint256 newGap) external override onlyOwner {
        require(newGap > 0 && newGap < 100, "Config: ZERO_GAP");
        emit RebasePriceGapChanged(rebasePriceGap, newGap);
        rebasePriceGap = newGap;
    }

    function setRebaseInterval(uint256 interval) external override onlyOwner {
        emit RebaseIntervalChanged(rebaseInterval, interval);
        rebaseInterval = interval;
    }

    function setTradingSlippage(uint256 newTradingSlippage) external override onlyOwner {
        require(newTradingSlippage > 0 && newTradingSlippage < 100, "Config: TRADING_SLIPPAGE_RANGE_ERROR");
        emit TradingSlippageChanged(tradingSlippage, newTradingSlippage);
        tradingSlippage = newTradingSlippage;
    }

    function setInitMarginRatio(uint256 marginRatio) external override onlyOwner {
        require(marginRatio >= 100, "Config: INVALID_MARGIN_RATIO");
        emit SetInitMarginRatio(initMarginRatio, marginRatio);
        initMarginRatio = marginRatio;
    }

    function setLiquidateThreshold(uint256 threshold) external override onlyOwner {
        require(threshold > 9000 && threshold <= 10000, "Config: INVALID_LIQUIDATE_THRESHOLD");
        emit SetLiquidateThreshold(liquidateThreshold, threshold);
        liquidateThreshold = threshold;
    }

    function setLiquidateFeeRatio(uint256 feeRatio) external override onlyOwner {
        require(feeRatio > 0 && feeRatio <= 2000, "Config: INVALID_LIQUIDATE_FEE_RATIO");
        emit SetLiquidateFeeRatio(liquidateFeeRatio, feeRatio);
        liquidateFeeRatio = feeRatio;
    }

    function setFeeParameter(uint256 newFeeParameter) external override onlyOwner {
        emit SetFeeParameter(feeParameter, newFeeParameter);
        feeParameter = newFeeParameter;
    }

    function setBeta(uint8 newBeta) external override onlyOwner {
        require(newBeta >= 50 && newBeta <= 200, "Config: INVALID_BETA");
        emit SetBeta(beta, newBeta);
        beta = newBeta;
    }

    //must be careful, expose all traders's position
    function registerRouter(address router) external override onlyOwner {
        require(router != address(0), "Config: ZERO_ADDRESS");
        require(!routerMap[router], "Config: REGISTERED");
        routerMap[router] = true;

        emit RouterRegistered(router);
    }

    function unregisterRouter(address router) external override onlyOwner {
        require(router != address(0), "Config: ZERO_ADDRESS");
        require(routerMap[router], "Config: UNREGISTERED");
        delete routerMap[router];

        emit RouterUnregistered(router);
    }
}


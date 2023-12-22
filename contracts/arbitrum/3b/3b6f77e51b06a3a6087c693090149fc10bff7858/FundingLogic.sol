// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import "./SafeMath.sol";
import "./SafeCast.sol";
import "./SignedSafeMath.sol";
import "./IFundingLogic.sol";
import "./IManager.sol";
import "./IMarket.sol";
import "./IPool.sol";
import "./IMarketPriceFeed.sol";

contract FundingLogic is IFundingLogic {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SignedSafeMath for int8;
    using SafeCast for int256;
    using SafeCast for uint256;

    int256 public constant RATE_PRECISION = 1e6;//rate decimal 1e6
    int256 public constant FUNDING_RATE_PRECISION = 1e18;//rate decimal 1e6
    int256 public constant SECONDS_PER_HOUR = 1 hours;//seconds per hour
    int256 public constant PRICE_PRECISION = 1e10;//price decimal 1e10
    uint256 public constant AMOUNT_PRECISION = 1e20;
    int256 internal constant Q96 = 0x1000000000000000000000000; // 2**96
    address public manager;//manager address
    int256 public maxFundingRate; // funding rate max limit,scaled 1e18
    address public marketPriceFeed;//marketPriceFeed address

    event UpdateMaxFundingRate(int256 rate);
    event UpdateMarketPriceFeed(address priceFeed);

    constructor(address _manager, int256 _maxFundingRate){
        require(_manager != address(0), "FundingLogic: invalid manager");
        manager = _manager;
        maxFundingRate = _maxFundingRate;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "FundingLogic: Must be controller");
        _;
    }

    /// @notice update max funding rate, only controller can call
    /// @param _maxFundingRate max funding rate
    function updateMaxFundingRate(int256 _maxFundingRate) external onlyController {
        maxFundingRate = _maxFundingRate;
        emit UpdateMaxFundingRate(_maxFundingRate);
    }

    /// @notice update market price feed, only controller can call
    /// @param _marketPriceFeed market price feed address
    function updateMarketPriceFeed(address _marketPriceFeed) external onlyController {
        marketPriceFeed = _marketPriceFeed;
        emit UpdateMarketPriceFeed(_marketPriceFeed);
    }

    struct FundingInternalParams {
        address pool;
        //address marketPriceFeed;
        string token;
        uint256 price;
        uint256 lastFrX96Ts;//last update timestamp
        uint256 longValue;//long amount
        uint256 shortValue;//short amount
        uint256 marketBorrowMax;//market borrow max
        uint8 marketType;//market type
        int256 deltaX96;//delta funding rate by deltaTime
        uint256 deltaTs;//delta time
    }

    /// @notice calculation data to update the funding
    /// @param market market address
    /// @return fundingGrowthGlobalX96 current funding rate
    function getFunding(address market) public view override returns (int256 fundingGrowthGlobalX96) {
        FundingInternalParams memory params;
        params.pool = IMarket(market).pool();
        params.token = IMarket(market).token();
        params.price = IMarketPriceFeed(marketPriceFeed).priceForIndex(params.token, false);

        params.lastFrX96Ts = IMarket(market).lastFrX96Ts();
        (params.longValue, params.shortValue, params.marketBorrowMax) = IPool(params.pool).getMarketAmount(market);
        params.marketType = IMarket(market).marketType();
        //get last funding rate
        fundingGrowthGlobalX96 = IMarket(market).fundingGrowthGlobalX96();
        //if funding paused, return last funding rate
        if (IManager(manager).isFundingPaused()) return fundingGrowthGlobalX96;

        params.deltaTs = block.timestamp - params.lastFrX96Ts;
        if (block.timestamp != params.lastFrX96Ts && params.lastFrX96Ts != 0) {
            if (params.longValue.add(params.shortValue) != 0 && params.marketBorrowMax != 0) {
                //(longValue - shortValue) / marketBorrowMax * fundingRateMax
                int256 longShortDeltaValue = params.longValue.toInt256().sub(params.shortValue.toInt256());
                int256 deltaFundingRate = longShortDeltaValue .mul(maxFundingRate).div(params.marketBorrowMax.toInt256());
                //if funding rate > fundingRateMax, set funding rate = fundingRateMax, if funding rate < -fundingRateMax, set funding rate = -fundingRateMax
                if (deltaFundingRate > maxFundingRate) deltaFundingRate = maxFundingRate;
                if (deltaFundingRate < maxFundingRate.neg256()) deltaFundingRate = maxFundingRate.neg256();

                //deltaPerSecondFundingRate = scale Q96 / maxFundingRate decimals/ SECONDS_PER_HOUR
                //precision calc :18 + 28 - 18 -4 = 24
                deltaFundingRate = deltaFundingRate.mul(Q96).div(FUNDING_RATE_PRECISION).div(SECONDS_PER_HOUR);

                if (params.marketType == 0 || params.marketType == 2) {
                    //precision calc : 24 + 10 + 10 -10 = 34
                    params.deltaX96 = deltaFundingRate.mul(params.price.mul(params.deltaTs).toInt256()).div(PRICE_PRECISION);
                } else {
                    params.deltaX96 = deltaFundingRate.mul(params.deltaTs.toInt256().mul(PRICE_PRECISION)).div(params.price.toInt256());
                }
            } else {
                params.deltaX96 = 0;
            }
            fundingGrowthGlobalX96 = fundingGrowthGlobalX96.add(params.deltaX96);
        }
    }

    /// @notice calculate funding payment
    /// @param market market address
    /// @param positionId position id
    /// @return fundingPayment funding payment
    function getFundingPayment(address market, uint256 positionId, int256 fundingGrowthGlobalX96) external view override returns (int256 fundingPayment){
        MarketDataStructure.Position memory position = IMarket(market).getPosition(positionId);
        MarketDataStructure.MarketConfig memory marketConfig = IMarket(market).getMarketConfig();
        uint8 marketType = IMarket(market).marketType();
        //precision calc : 20 + 34
        fundingPayment = position.amount.toInt256().mul(fundingGrowthGlobalX96.sub(position.frLastX96)).mul(position.direction).div(Q96);

        if (marketType == 2) {
            fundingPayment = fundingPayment.mul(position.multiplier.toInt256()).div(RATE_PRECISION);
        }
        fundingPayment = fundingPayment.mul(marketConfig.marketAssetPrecision.toInt256()).div(AMOUNT_PRECISION.toInt256());
    }
}


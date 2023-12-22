// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./IMarketDashboard.sol";
import "./IGRVDistributor.sol";
import "./IMarketView.sol";
import "./IGToken.sol";
import "./ICore.sol";
import "./IBEP20.sol";
import "./IPriceCalculator.sol";
import "./ILendPoolLoan.sol";

contract MarketDashboard is IMarketDashboard, OwnableUpgradeable {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    IGRVDistributor public grvDistributor;
    IMarketView public marketView;
    ICore public core;
    IPriceCalculator public priceCalculator;
    ILendPoolLoan public lendPoolLoan;

    /* ========== INITIALIZER ========== */

    function initialize(address _core, address _grvDistributor, address _marketView, address _priceCalculator) external initializer {
        require(_grvDistributor != address(0), "MarketDashboard: grvDistributor address can't be zero");
        require(_marketView != address(0), "MarketDashboard: MarketView address can't be zero");
        require(_core != address(0), "MarketDashboard: core address can't be zero");
        require(_priceCalculator != address(0), "MarketDashboard: priceCalculator address can't be zero");

        __Ownable_init();

        core = ICore(_core);
        grvDistributor = IGRVDistributor(_grvDistributor);
        marketView = IMarketView(_marketView);
        priceCalculator = IPriceCalculator(_priceCalculator);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setDistributor(address _grvDistributor) external onlyOwner {
        require(_grvDistributor != address(0), "MarketDashboard: invalid grvDistributor address");
        grvDistributor = IGRVDistributor(_grvDistributor);
    }

    function setMarketView(address _marketView) external onlyOwner {
        require(_marketView != address(0), "MarketDashboard: invalid MarketView address");
        marketView = IMarketView(_marketView);
    }

    function setPriceCalculator(address _priceCalculator) external onlyOwner {
        require(_priceCalculator != address(0), "MarketDashboard: invalid priceCalculator address");
        priceCalculator = IPriceCalculator(_priceCalculator);
    }

    function setLendPoolLoan(address _lendPoolLoan) external onlyOwner {
        require(_lendPoolLoan != address(0), "MarketDashboard: invalid lendPoolLoan address");
        lendPoolLoan = ILendPoolLoan(_lendPoolLoan);
    }

    /* ========== VIEWS ========== */

    function marketDataOf(address market) external view override returns (MarketData memory) {
        MarketData memory marketData;
        Constant.DistributionAPY memory apyDistribution = grvDistributor.apyDistributionOf(market, address(0));
        Constant.DistributionInfo memory distributionInfo = grvDistributor.distributionInfoOf(market);
        IGToken gToken = IGToken(market);

        marketData.gToken = market;

        marketData.apySupply = marketView.supplyRatePerSec(market).mul(365 days);
        marketData.apyBorrow = marketView.borrowRatePerSec(market).mul(365 days);
        marketData.apySupplyGRV = apyDistribution.apySupplyGRV;
        marketData.apyBorrowGRV = apyDistribution.apyBorrowGRV;

        marketData.totalSupply = gToken.totalSupply().mul(gToken.exchangeRate()).div(1e18);
        marketData.totalBorrows = gToken.totalBorrow();
        marketData.totalBoostedSupply = distributionInfo.totalBoostedSupply;
        marketData.totalBoostedBorrow = distributionInfo.totalBoostedBorrow;

        marketData.cash = gToken.getCash();
        marketData.reserve = gToken.totalReserve();
        marketData.reserveFactor = gToken.reserveFactor();
        marketData.collateralFactor = core.marketInfoOf(market).collateralFactor;
        marketData.exchangeRate = gToken.exchangeRate();
        marketData.borrowCap = core.marketInfoOf(market).borrowCap;
        marketData.accInterestIndex = gToken.getAccInterestIndex();
        return marketData;
    }

    function usersMonthlyProfit(address account) external view override returns (uint256 supplyBaseProfits, uint256 supplyRewardProfits, uint256 borrowBaseProfits, uint256 borrowRewardProfits) {
        address[] memory markets = core.allMarkets();
        uint[] memory prices = priceCalculator.getUnderlyingPrices(markets);
        supplyBaseProfits = 0;
        supplyRewardProfits = 0;
        borrowBaseProfits = 0;
        borrowRewardProfits = 0;

        for (uint256 i = 0; i < markets.length; i++) {
            Constant.DistributionAPY memory apyDistribution = grvDistributor.apyDistributionOf(markets[i], account);
            uint256 decimals = _getDecimals(markets[i]);
            {
                uint256 supplyBalance = IGToken(markets[i]).underlyingBalanceOf(account);
                uint256 supplyAPY = marketView.supplyRatePerSec(markets[i]).mul(365 days);
                uint256 supplyInUSD = supplyBalance.mul(10 ** (18-decimals)).mul(prices[i]).div(1e18);
                uint256 supplyMonthlyProfit = supplyInUSD.mul(supplyAPY).div(12).div(1e18);
                uint256 supplyGRVMonthlyProfit = supplyInUSD.mul(apyDistribution.apyAccountSupplyGRV).div(12).div(1e18);

                supplyBaseProfits = supplyBaseProfits.add(supplyMonthlyProfit);
                supplyRewardProfits = supplyRewardProfits.add(supplyGRVMonthlyProfit);
            }
            {
                uint256 borrowBalance = IGToken(markets[i]).borrowBalanceOf(account);
                if (IGToken(markets[i]).underlying() == address(0)) {
                    borrowBalance = borrowBalance.add(lendPoolLoan.userBorrowBalance(account));
                }
                uint256 borrowAPY = marketView.borrowRatePerSec(markets[i]).mul(365 days);
                uint256 borrowInUSD = borrowBalance.mul(10 ** (18-decimals)).mul(prices[i]).div(1e18);
                uint256 borrowMonthlyProfit = borrowInUSD.mul(borrowAPY).div(12).div(1e18);
                uint256 borrowGRVMonthlyProfit = borrowInUSD.mul(apyDistribution.apyAccountBorrowGRV).div(12).div(1e18);

                borrowBaseProfits = borrowBaseProfits.add(borrowMonthlyProfit);
                borrowRewardProfits = borrowRewardProfits.add(borrowGRVMonthlyProfit);
            }
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _getDecimals(address gToken) internal view returns (uint256 decimals) {
        address underlying = IGToken(gToken).underlying();
        if (underlying == address(0)) {
            decimals = 18; // ETH
        }
        else {
            decimals = IBEP20(underlying).decimals();
        }
    }
}


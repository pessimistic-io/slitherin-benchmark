// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IPoolFactory.sol";
import "./IPoolMaster.sol";
import "./IClearpoolLens.sol";
import "./IERC20MetadataUpgradeable.sol";

contract ClearpoolLens is IClearpoolLens {
  /// @notice PooLFactory contract
  IPoolFactory public factory;

  /// @notice Number of seconds per year
  uint256 public constant SECONDS_PER_YEAR = 31536000;

  /// @notice Contract constructor
  /// @param factory_ Address of the PoolFactory contract
  constructor(IPoolFactory factory_) {
    factory = factory_;
  }

  /// @notice Function that calculates poolsize-weighted indexes of pool supply APRs
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return rates Supply rates (APR) index by market
  function getSupplyRatesIndexesByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory rates) {
    rates = new MarketData[](markets.length);
    for (uint256 i = 0; i < markets.length; i++) {
      address market = markets[i];

      uint256 rate;
      uint256 totalPoolSize;

      address[] memory pools = factory.getPoolsByMarket(market);
      uint256 poolCount = pools.length;
      for (uint256 j = 0; j < poolCount; j++) {
        IPoolMaster pool = IPoolMaster(pools[j]);
        uint256 poolSize = pool.poolSize();

        totalPoolSize += poolSize;
        rate += pool.getSupplyRate() * poolSize;
      }
      rate /= totalPoolSize;
      rates[i] = MarketData(market, rate);
    }
  }

  /// @notice Function that calculates poolsize-weighted indexes of pool borrow APRs
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return rates Borrow rates (APR) index by market
  function getBorrowRatesIndexesByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory rates) {
    rates = new MarketData[](markets.length);

    for (uint256 i = 0; i < markets.length; i++) {
      address market = markets[i];

      uint256 rate;
      uint256 totalPoolSize;

      address[] memory pools = factory.getPoolsByMarket(market);
      uint256 poolCount = pools.length;
      for (uint256 j = 0; j < poolCount; j++) {
        IPoolMaster pool = IPoolMaster(pools[j]);

        uint256 poolSize = pool.poolSize();

        totalPoolSize += poolSize;
        rate += pool.getBorrowRate() * poolSize;
      }
      rate /= totalPoolSize;

      rates[i] = MarketData(market, rate);
    }
  }

  /// @notice Function that calculates total amounts of liquidity in all active pools of a given markets
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return liquidity Total liquidity by market
  function getTotalLiquidityByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory liquidity) {
    liquidity = new MarketData[](markets.length);
    for (uint256 i = 0; i < markets.length; i++) {
      address market = markets[i];

      uint256 poolsLiquidity;

      address[] memory pools = factory.getPoolsByMarket(market);
      uint256 poolCount = pools.length;
      for (uint256 j = 0; j < poolCount; j++) {
        IPoolMaster pool = IPoolMaster(pools[j]);
        poolsLiquidity += pool.cash() + pool.borrows() - pool.insurance() - pool.reserves();
      }
      liquidity[i] = MarketData(market, poolsLiquidity);
    }
  }

  /// @notice Function that calculates total amount of liquidity in all active pools of a given markets
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return interests Total interest accrued by market
  function getTotalInterestsByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory interests) {
    interests = new MarketData[](markets.length);
    for (uint256 i = 0; i < markets.length; i++) {
      address market = markets[i];

      uint256 poolsInterests;

      address[] memory pools = factory.getPoolsByMarket(market);
      uint256 poolCount = pools.length;
      for (uint256 j = 0; j < poolCount; j++) {
        IPoolMaster pool = IPoolMaster(pools[j]);

        poolsInterests += pool.interest();
      }
      interests[i] = MarketData(markets[i], poolsInterests);
    }
  }

  /// @notice Function that calculates total amount of liquidity in all active pools of a given markets
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return borrows Total borrows by market
  function getTotalBorrowsByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory borrows) {
    borrows = new MarketData[](markets.length);
    for (uint256 i = 0; i < markets.length; i++) {
      address market = markets[i];

      uint256 poolsBorrows;

      address[] memory pools = factory.getPoolsByMarket(market);
      uint256 poolCount = pools.length;
      for (uint256 j = 0; j < poolCount; j++) {
        IPoolMaster pool = IPoolMaster(pools[j]);

        poolsBorrows += pool.borrows();
      }
      borrows[i] = MarketData(markets[i], poolsBorrows);
    }
  }

  /// @notice Function that calculates total amount of principal in all active pools
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return principals Total principal by market
  function getTotalPrincipalsByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory principals) {
    principals = new MarketData[](markets.length);
    for (uint256 i = 0; i < markets.length; i++) {
      address market = markets[i];

      uint256 poolsPrincipals;

      address[] memory pools = factory.getPoolsByMarket(market);
      uint256 poolCount = pools.length;
      for (uint256 j = 0; j < poolCount; j++) {
        IPoolMaster pool = IPoolMaster(pools[j]);

        poolsPrincipals += pool.principal();
      }
      principals[i] = MarketData(markets[i], poolsPrincipals);
    }
  }

  /// @notice Function that calculates total amount of reserves in all active pools
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return reserves Total reserves by market
  function getTotalReservesByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory reserves) {
    reserves = new MarketData[](markets.length);
    for (uint256 i = 0; i < markets.length; i++) {
      address market = markets[i];

      uint256 poolsReserves;

      address[] memory pools = factory.getPoolsByMarket(market);
      uint256 poolCount = pools.length;
      for (uint256 j = 0; j < poolCount; j++) {
        IPoolMaster pool = IPoolMaster(pools[j]);

        poolsReserves += pool.reserves();
      }
      reserves[i] = MarketData(markets[i], poolsReserves);
    }
  }

  /// @notice Function that converts value to wei
  function _toWei(uint256 value, uint256 decimals) internal pure returns (uint256) {
    return value * 10 ** (18 - decimals);
  }

  /// @notice Function that calculates CPOOL APR for one pool
  /// @param poolAddress Address of the pool
  /// @param cpoolPrice Price of CPOOL in USD
  /// @return apr Pool's CPOOL APR
  function getPoolCpoolApr(
    address poolAddress,
    uint256 cpoolPrice
  ) public view returns (uint256 apr) {
    IPoolMaster pool = IPoolMaster(poolAddress);

    uint256 poolDecimals = IERC20MetadataUpgradeable(pool.currency()).decimals();

    uint256 totalSupply = _toWei(pool.totalSupply(), poolDecimals);
    if (totalSupply == 0) {
      return 0; // prevent division by 0
    }

    uint256 exchangeRate = pool.getCurrentExchangeRate();
    uint256 rewardPerSecond = pool.rewardPerSecond();
    uint256 poolSupply = totalSupply * exchangeRate;
    uint256 usdRewardPerYear = rewardPerSecond * SECONDS_PER_YEAR * cpoolPrice;

    return (usdRewardPerYear * 1e18) / poolSupply;
  }

  /// @notice Function that calculates weighted average of 2 arrays
  /// @param nums array of numbers
  /// @param weights array of weight numbers
  /// @return average and cpoolApr Pools APRs
  function _getWeightedAverage(
    uint256[] memory nums,
    uint256[] memory weights
  ) internal pure returns (uint256 average) {
    uint256 sum = 0;
    uint256 weightSum = 0;

    for (uint256 i = 0; i < weights.length; i++) {
      sum += nums[i] * weights[i];
      weightSum += weights[i];
    }

    if (weightSum == 0) {
      return 0;
    }

    return sum / weightSum;
  }

  /// @notice Function that calculates weighted average of pools APRs
  /// @param markets Array of market addresses, for which the data is calculated
  /// @param cpoolPrice Price of CPOOL in USD
  /// @return currencyAprs and cpoolApr Pools APRs
  /// @return cpoolAprs and cpoolApr Pools APRs
  function getAprIndexByMarket(
    address[] calldata markets,
    uint256 cpoolPrice
  ) external view returns (MarketData[] memory currencyAprs, MarketData[] memory cpoolAprs) {
    currencyAprs = new MarketData[](markets.length);
    cpoolAprs = new MarketData[](markets.length);

    for (uint256 i = 0; i < markets.length; i++) {
      address market = markets[i];
      address[] memory pools = factory.getPoolsByMarket(market);

      uint256 size = pools.length;

      uint256[] memory marketCurrencyAprs = new uint256[](size);
      uint256[] memory marketCpoolAprs = new uint256[](size);
      uint256[] memory poolSizes = new uint256[](size);

      for (uint256 j = 0; j < size; j++) {
        IPoolMaster pool = IPoolMaster(pools[j]);

        uint256 poolDecimals = IERC20MetadataUpgradeable(pool.currency()).decimals();

        poolSizes[j] = _toWei(pool.poolSize(), poolDecimals);
        marketCurrencyAprs[j] = pool.getSupplyRate() * SECONDS_PER_YEAR;
        marketCpoolAprs[j] = getPoolCpoolApr(pools[j], cpoolPrice);
      }

      uint256 currencyApr = _getWeightedAverage(marketCurrencyAprs, poolSizes);
      uint256 cpoolApr = _getWeightedAverage(marketCpoolAprs, poolSizes);

      currencyAprs[i] = MarketData(markets[i], currencyApr);
      cpoolAprs[i] = MarketData(markets[i], cpoolApr);
    }
  }
}


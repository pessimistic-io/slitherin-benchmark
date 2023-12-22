// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IClearpoolLens {
  /// @notice Returns data by token address
  struct MarketData {
    address tokenAddress;
    uint256 value;
  }

  /// @notice Function that calculates poolsize-weighted indexes of pool supply APRs
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return rates Supply rates (APR) index by market
  function getSupplyRatesIndexesByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory rates);

  /// @notice Function that calculates poolsize-weighted indexes of pool borrow APRs
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return rates Borrow rates (APR) index by market
  function getBorrowRatesIndexesByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory rates);

  /// @notice Function that calculates total amounts of liquidity in all active pools of a given markets
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return liquidity Total liquidity by market
  function getTotalLiquidityByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory liquidity);

  /// @notice Function that calculates total amount of liquidity in all active pools of a given markets
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return interests Total interest accrued by market
  function getTotalInterestsByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory interests);

  /// @notice Function that calculates total amount of liquidity in all active pools of a given markets
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return borrows Total borrows by market
  function getTotalBorrowsByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory borrows);

  /// @notice Function that calculates total amount of principal in all active pools
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return principals Total principal by market
  function getTotalPrincipalsByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory principals);

  /// @notice Function that calculates total amount of reserves in all active pools
  /// @param markets Array of market addresses, for which the data is calculated
  /// @return reserves Total reserves by market
  function getTotalReservesByMarkets(
    address[] calldata markets
  ) external view returns (MarketData[] memory reserves);

  /// @notice Function that calculates CPOOL APR for one pool
  /// @param poolAddress Address of the pool
  /// @param cpoolPrice Price of CPOOL in USD
  /// @return apr Pool's CPOOL APR
  function getPoolCpoolApr(
    address poolAddress,
    uint256 cpoolPrice
  ) external view returns (uint256 apr);

  /// @notice Function that calculates weighted average of pools APRs
  /// @param cpoolPrice Price of CPOOL in USD
  /// @return currencyApr and cpoolApr Pools APRs
  function getAprIndexByMarket(
    address[] calldata markets,
    uint256 cpoolPrice
  ) external view returns (MarketData[] memory currencyApr, MarketData[] memory cpoolApr);
}


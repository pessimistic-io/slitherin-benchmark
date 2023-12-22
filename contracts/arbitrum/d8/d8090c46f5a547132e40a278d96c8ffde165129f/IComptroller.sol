// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

interface IComptroller {
  function isComptroller() external view returns (bool);
  function oracle() external view returns (address);
  function markets(address)
    external
    view
    returns (
      bool isListed,
      uint256 collateralFactorMantissa,
      uint256 liquidationThresholdMantissa,
      uint256 collateralFactorMantissaVip,
      uint256 liquidationThresholdMantissaVip,
      bool isComped,
      bool isPrivate,
      bool onlyWhitelistedBorrow
    );
  function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
  function exitMarket(address cToken) external returns (uint256);
  function addToMarketExternal(address cToken, address borrower) external;
  function mintAllowed(address cToken, address minter, uint256 mintAmount) external returns (uint256);
  function mintVerify(address cToken, address minter, uint256 mintAmount, uint256 mintTokens) external;
  function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens) external returns (uint256);
  function redeemVerify(address cToken, address redeemer, uint256 redeemAmount, uint256 redeemTokens) external;
  function borrowAllowed(address cToken, address borrower, uint256 borrowAmount) external returns (uint256);
  function borrowVerify(address cToken, address borrower, uint256 borrowAmount) external;
  function getIsAccountVip(address account) external view returns (bool);
  function getAllMarkets() external view returns (address[] memory);
  function getAccountLiquidity(address account, bool isLiquidationCheck)
    external
    view
    returns (uint256, uint256, uint256);
  function getHypotheticalAccountLiquidity(
    address account,
    address cTokenModify,
    uint256 redeemTokens,
    uint256 borrowAmount,
    bool isLiquidationCheck
  ) external view returns (uint256, uint256, uint256);
  function _setPriceOracle(address oracle_) external;
  function _supportMarket(address delegator, bool isComped, bool isPrivate, bool onlyWhitelistedBorrow) external;
  function _setFactorsAndThresholds(
    address delegator,
    uint256 collateralFactor,
    uint256 collateralVIP,
    uint256 threshold,
    uint256 thresholdVIP
  ) external;

  /// @notice Indicator that this is a Comptroller contract (for inspection)
  function repayBorrowAllowed(address cToken, address payer, address borrower, uint256 repayAmount)
    external
    returns (uint256);

  function repayBorrowVerify(
    address cToken,
    address payer,
    address borrower,
    uint256 repayAmount,
    uint256 borrowerIndex
  ) external;

  function liquidateBorrowAllowed(
    address cTokenBorrowed,
    address cTokenCollateral,
    address liquidator,
    address borrower,
    uint256 repayAmount
  ) external returns (uint256);
  function liquidateBorrowVerify(
    address cTokenBorrowed,
    address cTokenCollateral,
    address liquidator,
    address borrower,
    uint256 repayAmount,
    uint256 seizeTokens
  ) external;

  function seizeAllowed(
    address cTokenCollateral,
    address cTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external returns (uint256);

  function seizeVerify(
    address cTokenCollateral,
    address cTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external;
  function transferAllowed(address cToken, address src, address dst, uint256 transferTokens) external returns (uint256);

  function transferVerify(address cToken, address src, address dst, uint256 transferTokens) external;

  /**
   * Liquidity/Liquidation Calculations **
   */
  function liquidateCalculateSeizeTokens(address cTokenBorrowed, address cTokenCollateral, uint256 repayAmount)
    external
    view
    returns (uint256, uint256);
}


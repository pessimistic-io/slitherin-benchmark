//SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4;

import "./HTokenI.sol";
import "./PermissionlessOracleI.sol";

/**
 * @title   Interface of Controller
 * @author  Honey Labs Inc.
 * @custom:coauthor     m4rio
 * @custom:contributor  BowTiedPickle
 */
interface ControllerI {
  /**
   * @notice returns the oracle per market
   */
  function oracle(HTokenI _hToken) external view returns (PermissionlessOracleI);

  /**
   * @notice Add assets to be included in account liquidity calculation
   * @param _hTokens The list of addresses of the hToken markets to be enabled
   */
  function enterMarkets(HTokenI[] calldata _hTokens) external;

  /**
   * @notice Removes asset from sender's account liquidity calculation
   * @dev Sender must not have an outstanding borrow balance in the asset,
   *  or be providing necessary collateral for an outstanding borrow.
   * @param _hToken The address of the asset to be removed
   */
  function exitMarket(HTokenI _hToken) external;

  /**
   * @notice Checks if the account should be allowed to deposit underlying in the market
   * @param _hToken The market to verify the redeem against
   * @param _depositor The account which that wants to deposit
   * @param _amount The number of underlying it wants to deposit
   */
  function depositUnderlyingAllowed(
    HTokenI _hToken,
    address _depositor,
    uint256 _amount
  ) external;

  /**
   * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
   * @param _hToken The market to verify the borrow against
   * @param _borrower The account which would borrow the asset
   * @param _collateralId collateral Id, aka the NFT token Id
   * @param _borrowAmount The amount of underlying the account would borrow
   */
  function borrowAllowed(
    HTokenI _hToken,
    address _borrower,
    uint256 _collateralId,
    uint256 _borrowAmount
  ) external;

  /**
   * @notice Checks if the account should be allowed to deposit a collateral
   * @param _hToken The market to verify the deposit of the collateral
   * @param _depositor The account which deposits the collateral
   * @param _collateralId The collateral token id
   */
  function depositCollateralAllowed(
    HTokenI _hToken,
    address _depositor,
    uint256 _collateralId
  ) external;

  /**
   * @notice Checks if the account should be allowed to redeem tokens in the given market
   * @param _hToken The market to verify the redeem against
   * @param _redeemer The account which would redeem the tokens
   * @param _redeemTokens The number of hTokens to exchange for the underlying asset in the market
   */
  function redeemAllowed(
    HTokenI _hToken,
    address _redeemer,
    uint256 _redeemTokens
  ) external view;

  /**
   * @notice Checks if the collateral is at risk of being liquidated
   * @param _hToken The market to verify the liquidation
   * @param _collateralId collateral Id, aka the NFT token Id
   */
  function liquidationAllowed(HTokenI _hToken, uint256 _collateralId) external view;

  /**
   * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
   * @param _hToken The market to hypothetically redeem/borrow in
   * @param _account The account to determine liquidity for
   * @param _redeemTokens The number of tokens to hypothetically redeem
   * @param _borrowAmount The amount of underlying to hypothetically borrow
   * @param _collateralId collateral Id, aka the NFT token Id
   * @return liquidity - hypothetical account liquidity in excess of collateral requirements
   * @return shortfall - hypothetical account shortfall below collateral requirements
   * @return ltvShortfall - Loan to value shortfall, this is the max a user can borrow
   */
  function getHypotheticalAccountLiquidity(
    HTokenI _hToken,
    address _account,
    uint256 _collateralId,
    uint256 _redeemTokens,
    uint256 _borrowAmount
  )
    external
    view
    returns (
      uint256 liquidity,
      uint256 shortfall,
      uint256 ltvShortfall
    );

  /**
   * @notice Returns whether the given account is entered in the given asset
   * @param _hToken The hToken to check
   * @param _account The address of the account to check
   * @return True if the account is in the asset, otherwise false.
   */
  function checkMembership(HTokenI _hToken, address _account) external view returns (bool);

  /**
   * @notice Checks if the account should be allowed to transfer tokens in the given market
   * @param _hToken The market to verify the transfer against
   */
  function transferAllowed(HTokenI _hToken) external;

  /**
   * @notice Checks if the account should be allowed to repay a borrow in the given market
   * @param _hToken The market to verify the repay against
   * @param _repayAmount The amount of the underlying asset the account would repay
   * @param _collateralId collateral Id, aka the NFT token Id
   */
  function repayBorrowAllowed(
    HTokenI _hToken,
    uint256 _repayAmount,
    uint256 _collateralId
  ) external view;

  /**
   * @notice checks if withdrawal are allowed for this token id
   * @param _hToken The market to verify the withdrawal from
   * @param _collateralId what to pay for
   */
  function withdrawCollateralAllowed(HTokenI _hToken, uint256 _collateralId) external view;

  /**
   * @notice checks if a market exists and it's listed
   * @param _hToken the market we check to see if it exists
   * @return bool true or false
   */
  function marketExists(HTokenI _hToken) external view returns (bool);

  /**
   * @notice Returns market data for a specific market
   * @param _hToken the market we want to retrieved Controller data
   * @return bool If the market is listed
   * @return uint256 MAX Factor Mantissa
   * @return uint256 Collateral Factor Mantissa
   */
  function getMarketData(HTokenI _hToken)
    external
    view
    returns (
      bool,
      uint256,
      uint256
    );

  /**
   * @notice checks if an underlying exists in the market
   * @param _underlying the underlying to check if exists
   * @return bool true or false
   */
  function underlyingExistsInMarkets(address _underlying) external view returns (bool);

  /**
   * @notice checks if a collateral exists in the market
   * @param _collateral the collateral to check if exists
   * @return bool true or false
   */
  function collateralExistsInMarkets(address _collateral) external view returns (bool);

  /**
   * @notice  Checks if a certain action is paused within a market
   * @param   _hToken   The market we want to check if an action is paused
   * @param   _target   The action we want to check if it's paused
   * @return  bool true or false
   */
  function isActionPaused(HTokenI _hToken, uint256 _target) external view returns (bool);

  /**
   * @notice returns the borrow fee per market, accounts for referral
   * @param _hToken the market we want the borrow fee for
   * @param _referral referral code for Referral program of Honey Labs
   * @param _signature signed message provided by Honey Labs
   */
  function getBorrowFeePerMarket(
    HTokenI _hToken,
    string calldata _referral,
    bytes calldata _signature
  ) external view returns (uint256, bool);

  /**
   * @notice returns the borrow fee per market if provided a referral code, accounts for referral
   * @param _hToken the market we want the borrow fee for
   */
  function getReferralBorrowFeePerMarket(HTokenI _hToken) external view returns (uint256);

  // ---------- Permissioned Functions ----------

  function _supportMarket(HTokenI _hToken) external;

  function _setPriceOracle(HTokenI _hToken, PermissionlessOracleI _newOracle) external;

  function _setFactors(
    HTokenI _hToken,
    uint256 _newMaxLTVFactorMantissa,
    uint256 _newCollateralFactorMantissa
  ) external;

  function _setBorrowFeePerMarket(
    HTokenI _market,
    uint256 _fee,
    uint256 _referralFee
  ) external;

  function _pauseComponent(
    HTokenI _hToken,
    bool _state,
    uint256 _target
  ) external;
}


//SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4;

import "./HTokenI.sol";
import "./PriceOracleI.sol";
import "./ControllerI.sol";

/**
 * @title   Interface for HTokenLens
 * @author  Honey Labs Inc.
 * @custom:coauthor     m4rio
 * @custom:contributor  BowTiedPickle
 */
interface HTokenLensI {
  /**
   * @notice  Get underlying balance that is available for withdrawal or borrow
   * @return  The quantity of underlying not tied up
   */
  function getAvailableUnderlying(HTokenI _hToken) external view returns (uint256);

  /**
   * @notice  Get underlying balance for an account
   * @param   _account the account to check the balance for
   * @return  The quantity of underlying asset owned by this account
   */
  function getAvailableUnderlyingForUser(HTokenI _hToken, address _account) external view returns (uint256);

  /**
   * @notice  returns different assets per a hToken, helper method to reduce frontend calls
   * @param   _hToken the hToken to get the assets for
   * @return  total borrows
   * @return  total reserves
   * @return  total underlying balance
   * @return  active coupons
   */
  function getAssets(HTokenI _hToken) external view returns (uint256, uint256, uint256, HTokenI.Coupon[] memory);

  /**
   * @notice  Get all a user's coupons
   * @param   _hToken The HToken we want to get the user's coupons from
   * @param   _user   The user to search for
   * @return  Array of all coupons belonging to the user
   */
  function getUserCoupons(HTokenI _hToken, address _user) external view returns (HTokenI.Coupon[] memory);

  /**
   * @notice  Get the number of coupons deposited aka active
   * @param   _hToken The HToken we want to get the active User Coupons
   * @param   _hasDebt if the coupon has debt or not
   * @return  Array of all active coupons
   */
  function getActiveCoupons(HTokenI _hToken, bool _hasDebt) external view returns (HTokenI.Coupon[] memory);

  /**
   * @notice  Get tokenIds of all a user's coupons
   * @param   _hToken The HToken we want to get the User Coupon Indices
   * @param   _user The user to search for
   * @return  Array of indices of all coupons belonging to the user
   */
  function getUserCouponIndices(HTokenI _hToken, address _user) external view returns (uint256[] memory);

  /**
   * @notice  returns prices of floor and underlying for a market to reduce frontend calls
   * @param   _hToken the hToken to get the prices for
   * @return  collection floor price in underlying value
   * @return  underlying price in usd
   */
  function getMarketOraclePrices(HTokenI _hToken) external view returns (uint256, uint256);

  /**
   * @notice  Returns the borrow fee for a market, it can also return the discounted fee for referred borrow
   * @param   _hToken The market we want to get the borrow fee for
   * @param   _referred Flag that needs to be true in case we want to get the referred borrow fee
   * @return  fee - The borrow fee mantissa denominated in 1e18
   */
  function getMarketBorrowFee(HTokenI _hToken, bool _referred) external view returns (uint256 fee);

  /**
   * @notice  returns the collection price floor in usd
   * @param   _hToken the hToken to get the price for
   * @return  collection floor price in usd
   */
  function getFloorPriceInUSD(HTokenI _hToken) external view returns (uint256);

  /**
   * @notice  returns the collection price floor in underlying value
   * @param   _hToken the hToken to get the price for
   * @return  collection floor price in underlying
   */
  function getFloorPriceInUnderlying(HTokenI _hToken) external view returns (uint256);

  /**
   * @notice  get the underlying price in usd for a hToken
   * @param   _hToken the hToken to get the price for
   * @return  underlying price in usd
   */
  function getUnderlyingPriceInUSD(HTokenI _hToken) external view returns (uint256);

  /**
   * @notice  get the max borrowable amount for a market
   * @notice  it computes the floor price in usd and take the % of collateral factor that can be max borrowed
   *          then it divides it by the underlying price in usd.
   * @param   _hToken the hToken to get the price for
   * @param   _controller the controller used to get the collateral factor
   * @return  underlying price in underlying
   */
  function getMaxBorrowableAmountInUnderlying(HTokenI _hToken, ControllerI _controller) external view returns (uint256);

  /**
   * @notice  get the max borrowable amount for a market
   * @notice  it computes the floor price in usd and take the % of collateral factor that can be max borrowed
   * @param   _hToken the hToken to get the price for
   * @param   _controller the controller used to get the collateral factor
   * @return  underlying price in usd
   */
  function getMaxBorrowableAmountInUSD(HTokenI _hToken, ControllerI _controller) external view returns (uint256);

  /**
   * @notice  get's all the coupons that have deposited collateral
   * @param   _hToken market to get the collateral from
   * @param   _startTokenId start token id of the collateral collection, as we don't know how big the collection will be we have
   *          to do pagination
   * @param   _endTokenId end of token id we want to get.
   * @return  coupons list of coupons that are active
   */
  function getAllCollateralPerHToken(
    HTokenI _hToken,
    uint256 _startTokenId,
    uint256 _endTokenId
  ) external view returns (HTokenI.Coupon[] memory coupons);

  /**
   * @notice  Gets data about a market for frontend display
   * @dev     There may be minute variations to actual values depending on how long it has been since the market was updated
   * @param   _hToken the market we want the data for
   * @return  supply rate per block
   * @return  borrow rate per block
   * @return  supply APR (in 1e18 precision)
   * @return  borrow APR (in 1e18 precision)
   * @return  total underlying supplied in a market
   * @return  total underlying available to be borrowed
   */
  function getFrontendMarketData(
    HTokenI _hToken
  ) external view returns (uint256, uint256, uint256, uint256, uint256, uint256);

  /**
   * @notice  Gets data about a coupon for frontend display
   * @param   _hToken   The market we want the coupon for
   * @param   _couponId The coupon id we want to get the data for
   * @return  debt of this coupon
   * @return  allowance - how much liquidity can borrow till hitting LTV
   * @return  nft floor price
   */
  function getFrontendCouponData(HTokenI _hToken, uint256 _couponId) external view returns (uint256, uint256, uint256);

  /**
   * @notice  Gets Liquidation data for a market, for frontend purposes
   * @param   _hToken the market we want the data for
   * @return  Liquidation threshold of a market (collateral factor)
   * @return  Total debt of the market
   * @return  TVL is an approximate value of the NFTs deposited within a market, we only count the NFTs that have debt
   */
  function getFrontendLiquidationData(HTokenI _hToken) external view returns (uint256, uint256, uint256);
}


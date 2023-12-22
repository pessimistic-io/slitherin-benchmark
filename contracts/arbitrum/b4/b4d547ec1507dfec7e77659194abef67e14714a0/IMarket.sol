// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./IAccessControlEnumerable.sol";
import "./IERC20BurnableMinter.sol";
import "./IStakePool.sol";

interface IMarket is IAccessControlEnumerable {
  function totalVolume() external view returns (uint256);

  function paused() external view returns (bool);

  function Lab() external view returns (IERC20BurnableMinter);

  function prLab() external view returns (IERC20BurnableMinter);

  function pool() external view returns (IStakePool);

  // target funding ratio (target/10000)
  function target() external view returns (uint32);

  // target adjusted funding ratio (targetAdjusted/10000)
  function targetAdjusted() external view returns (uint32);

  // minimum value of target
  function minTarget() external view returns (uint32);

  // maximum value of the targetAdjusted
  function maxTargetAdjusted() external view returns (uint32);

  // step value of each raise
  function raiseStep() external view returns (uint32);

  // step value of each lower
  function lowerStep() external view returns (uint32);

  // interval of each lower
  function lowerInterval() external view returns (uint32);

  // the time when ratio was last modified
  function latestUpdateTimestamp() external view returns (uint256);

  // developer address
  function dev() external view returns (address);

  // fee for buying Lab
  function buyFee() external view returns (uint32);

  // fee for selling Lab
  function sellFee() external view returns (uint32);

  // the slope of the price function (1/(k * 1e18))
  function k() external view returns (uint256);

  // current Lab price
  function c() external view returns (uint256);

  // floor Lab price
  function f() external view returns (uint256);

  // floor supply
  function p() external view returns (uint256);

  // total worth
  function w() external view returns (uint256);

  // stablecoins decimals
  function stablecoinsDecimals(address token) external view returns (uint8);

  /**
   * @dev Startup market.
   *      The caller must be owner.
   * @param _token - Initial stablecoin address
   * @param _w - Initial stablecoin worth
   * @param _t - Initial Lab total supply
   */
  function startup(
    address _token,
    uint256 _w,
    uint256 _t
  ) external;

  /**
   * @dev Get the number of stablecoins that can buy Lab.
   */
  function stablecoinsCanBuyLength() external view returns (uint256);

  /**
   * @dev Get the address of the stablecoin that can buy Lab according to the index.
   * @param index - Stablecoin index
   */
  function stablecoinsCanBuyAt(uint256 index) external view returns (address);

  /**
   * @dev Get whether the token can be used to buy Lab.
   * @param token - Token address
   */
  function stablecoinsCanBuyContains(address token)
    external
    view
    returns (bool);

  /**
   * @dev Get the number of stablecoins that can be exchanged with Lab.
   */
  function stablecoinsCanSellLength() external view returns (uint256);

  /**
   * @dev Get the address of the stablecoin that can be exchanged with Lab,
   *      according to the index.
   * @param index - Stablecoin index
   */
  function stablecoinsCanSellAt(uint256 index) external view returns (address);

  /**
   * @dev Get whether the token can be exchanged with Lab.
   * @param token - Token address
   */
  function stablecoinsCanSellContains(address token)
    external
    view
    returns (bool);

  /**
   * @dev Calculate current funding ratio.
   */
  function currentFundingRatio()
    external
    view
    returns (uint256 numerator, uint256 denominator);

  /**
   * @dev Estimate adjust result.
   * @param _k - Slope
   * @param _tar - Target funding ratio
   * @param _w - Total worth
   * @param _t - Total supply
   * @return success - Whether the calculation was successful
   * @return _c - Current price
   * @return _f - Floor price
   * @return _p - Point of intersection
   */
  function estimateAdjust(
    uint256 _k,
    uint256 _tar,
    uint256 _w,
    uint256 _t
  )
    external
    pure
    returns (
      bool success,
      uint256 _c,
      uint256 _f,
      uint256 _p
    );

  /**
   * @dev Estimate next raise price.
   * @return success - Whether the calculation was successful
   * @return _t - The total supply when the funding ratio reaches targetAdjusted
   * @return _c - The price when the funding ratio reaches targetAdjusted
   * @return _w - The total worth when the funding ratio reaches targetAdjusted
   * @return raisedFloorPrice - The floor price after market adjusted
   */
  function estimateRaisePrice()
    external
    view
    returns (
      bool success,
      uint256 _t,
      uint256 _c,
      uint256 _w,
      uint256 raisedFloorPrice
    );

  /**
   * @dev Estimate raise price by input value.
   * @param _f - Floor price
   * @param _k - Slope
   * @param _p - Floor supply
   * @param _tar - Target funding ratio
   * @param _tarAdjusted - Target adjusted funding ratio
   * @return success - Whether the calculation was successful
   * @return _t - The total supply when the funding ratio reaches _tar
   * @return _c - The price when the funding ratio reaches _tar
   * @return _w - The total worth when the funding ratio reaches _tar
   * @return raisedFloorPrice - The floor price after market adjusted
   */
  function estimateRaisePrice(
    uint256 _f,
    uint256 _k,
    uint256 _p,
    uint256 _tar,
    uint256 _tarAdjusted
  )
    external
    pure
    returns (
      bool success,
      uint256 _t,
      uint256 _c,
      uint256 _w,
      uint256 raisedFloorPrice
    );

  /**
   * @dev Lower target and targetAdjusted with lowerStep.
   */
  function lowerAndAdjust() external;

  /**
   * @dev Set market options.
   *      The caller must has MANAGER_ROLE.
   *      This function can only be called before the market is started.
   * @param _k - Slope
   * @param _target - Target funding ratio
   * @param _targetAdjusted - Target adjusted funding ratio
   */
  function setMarketOptions(
    uint256 _k,
    uint32 _target,
    uint32 _targetAdjusted
  ) external;

  /**
   * @dev Set adjust options.
   *      The caller must be owner.
   * @param _minTarget - Minimum value of target
   * @param _maxTargetAdjusted - Maximum value of the targetAdjusted
   * @param _raiseStep - Step value of each raise
   * @param _lowerStep - Step value of each lower
   * @param _lowerInterval - Interval of each lower
   */
  function setAdjustOptions(
    uint32 _minTarget,
    uint32 _maxTargetAdjusted,
    uint32 _raiseStep,
    uint32 _lowerStep,
    uint32 _lowerInterval
  ) external;

  /**
   * @dev Set fee options.
   *      The caller must be owner.
   * @param _dev - Dev address
   * @param _buyFee - Fee for buying Lab
   * @param _sellFee - Fee for selling Lab
   */
  function setFeeOptions(
    address _dev,
    uint32 _buyFee,
    uint32 _sellFee
  ) external;

  /**
   * @dev Manage stablecoins.
   *      Add/Delete token to/from stablecoinsCanBuy/stablecoinsCanSell.
   *      The caller must be owner.
   * @param token - Token address
   * @param buyOrSell - Buy or sell token
   * @param addOrDelete - Add or delete token
   */
  function manageStablecoins(
    address token,
    bool buyOrSell,
    bool addOrDelete
  ) external;

  /**
   * @dev Estimate how much Lab user can buy.
   * @param token - Stablecoin address
   * @param tokenWorth - Number of stablecoins
   * @return amount - Number of Lab
   * @return fee - Dev fee
   * @return worth1e18 - The amount of stablecoins being exchanged(1e18)
   * @return newPrice - New Lab price
   */
  function estimateBuy(address token, uint256 tokenWorth)
    external
    view
    returns (
      uint256 amount,
      uint256 fee,
      uint256 worth1e18,
      uint256 newPrice
    );

  /**
   * @dev Estimate how many stablecoins will be needed to realize prLab.
   * @param amount - Number of prLab user want to realize
   * @param token - Stablecoin address
   * @return worth1e18 - The amount of stablecoins being exchanged(1e18)
   * @return worth - The amount of stablecoins being exchanged
   */
  function estimateRealize(uint256 amount, address token)
    external
    view
    returns (uint256 worth1e18, uint256 worth);

  /**
   * @dev Estimate how much stablecoins user can sell.
   * @param amount - Number of Lab user want to sell
   * @param token - Stablecoin address
   * @return fee - Dev fee
   * @return worth1e18 - The amount of stablecoins being exchanged(1e18)
   * @return worth - The amount of stablecoins being exchanged
   * @return newPrice - New Lab price
   */
  function estimateSell(uint256 amount, address token)
    external
    view
    returns (
      uint256 fee,
      uint256 worth1e18,
      uint256 worth,
      uint256 newPrice
    );

  /**
   * @dev Buy Lab.
   * @param token - Address of stablecoin used to buy Lab
   * @param tokenWorth - Number of stablecoins
   * @param desired - Minimum amount of Lab user want to buy
   * @return amount - Number of Lab
   * @return fee - Dev fee(Lab)
   */
  function buy(
    address token,
    uint256 tokenWorth,
    uint256 desired
  ) external returns (uint256, uint256);

  /**
   * @dev Buy Lab for user.
   * @param token - Address of stablecoin used to buy Lab
   * @param tokenWorth - Number of stablecoins
   * @param desired - Minimum amount of Lab user want to buy
   * @param user - User address
   * @return amount - Number of Lab
   * @return fee - Dev fee(Lab)
   */
  function buyFor(
    address token,
    uint256 tokenWorth,
    uint256 desired,
    address user
  ) external returns (uint256, uint256);

  /**
   * @dev Realize Lab with floor price and equal amount of prLab.
   * @param amount - Amount of prLab user want to realize
   * @param token - Address of stablecoin used to realize prLab
   * @param desired - Maximum amount of stablecoin users are willing to pay
   * @return worth - The amount of stablecoins being exchanged
   */
  function realize(
    uint256 amount,
    address token,
    uint256 desired
  ) external returns (uint256);

  /**
   * @dev Realize Lab with floor price and equal amount of prLab for user.
   * @param amount - Amount of prLab user want to realize
   * @param token - Address of stablecoin used to realize prLab
   * @param desired - Maximum amount of stablecoin users are willing to pay
   * @param user - User address
   * @return worth - The amount of stablecoins being exchanged
   */
  function realizeFor(
    uint256 amount,
    address token,
    uint256 desired,
    address user
  ) external returns (uint256);

  /**
   * @dev Sell Lab.
   * @param amount - Amount of Lab user want to sell
   * @param token - Address of stablecoin used to buy Lab
   * @param desired - Minimum amount of stablecoins user want to get
   * @return fee - Dev fee(Lab)
   * @return worth - The amount of stablecoins being exchanged
   */
  function sell(
    uint256 amount,
    address token,
    uint256 desired
  ) external returns (uint256, uint256);

  /**
   * @dev Sell Lab for user.
   * @param amount - Amount of Lab user want to sell
   * @param token - Address of stablecoin used to buy Lab
   * @param desired - Minimum amount of stablecoins user want to get
   * @param user - User address
   * @return fee - Dev fee(Lab)
   * @return worth - The amount of stablecoins being exchanged
   */
  function sellFor(
    uint256 amount,
    address token,
    uint256 desired,
    address user
  ) external returns (uint256, uint256);

  /**
   * @dev Burn Lab.
   *      It will preferentially transfer the excess value after burning to PSL.
   * @param amount - The amount of Lab the user wants to burn
   */
  function burn(uint256 amount) external;

  /**
   * @dev Burn Lab for user.
   *      It will preferentially transfer the excess value after burning to PSL.
   * @param amount - The amount of Lab the user wants to burn
   * @param user - User address
   */
  function burnFor(uint256 amount, address user) external;

  /**
   * @dev Triggers stopped state.
   *      The caller must be owner.
   */
  function pause() external;

  /**
   * @dev Returns to normal state.
   *      The caller must be owner.
   */
  function unpause() external;
}


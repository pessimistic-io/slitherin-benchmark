// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./IMarket.sol";
struct Bond {
  // start timestamp
  uint256 startAt;
  // end timestamp
  uint256 endAt;
  // the price of Lab borne by the treasury
  uint256 deductedPrice;
  // the total amount of Lab issued by bonds
  uint256 maxAmount;
  // the reserve amount of Lab issued by bonds
  uint256 reserveAmount;
  // the duration for the linear release of the of this bond's reward
  uint256 releaseDuration;
}

struct BUserInfo {
  // Lab balance
  uint256 amount;
  // locked reward
  uint256 lockedReward;
  // released reward
  uint256 releasedReward;
  // timestamp of last update
  uint256 timestamp;
  // the duration for the linear release of the reward
  uint256 releaseDuration;
}

interface IBonds {
  // Lab token address
  function Lab() external view returns (IERC20);

  // market contract address
  function market() external view returns (IMarket);

  // bond helper contract address
  function helper() external view returns (address);

  // auto increment bond id
  function bondsLength() external view returns (uint256);

  // bond info
  function bonds(uint256 id)
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    );

  // user info
  function userInfo(address user)
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    );

  /**
   * @dev Constructor.
   * NOTE This function can only called through delegatecall.
   * @param _Lab - Lab token address
   * @param _market - Market contract address
   * @param _helper - Helper contract address
   * @param _owner - Owner address
   */
  function constructor1(
    IERC20 _Lab,
    IMarket _market,
    address _helper,
    address _owner
  ) external;

  /**
   * @dev Estimate user pending reward
   * @param userAddress - User address
   * @return released - Pending reward from the last settlement until now
   * @return lockedReward - Pending locked reward
   * @return releasedReward - Pending released reward
   * @return amount - User Lab balance
   */
  function estimatePendingReward(address userAddress)
    external
    view
    returns (
      uint256 released,
      uint256 lockedReward,
      uint256 releasedReward,
      uint256 amount
    );

  /**
   * @dev Estimate how much stablecoin users need to pay
   *      in addition to the part burdened by the treasury
   * @param id - Bond id
   * @param token - Stablecoin address
   * @param amount - The amount of Lab
   * @return fee - The fee charged by the developer(Lab)
   * @return worth - The amount of stablecoins that users should pay
   * @return worth1e18 - The amount of stablecoins that users should pay(1e18)
   * @return newDebt1e18 - Newly incurred treasury debt(1e18)
   * @return newPrice - New price
   */
  function estimateBuy(
    uint256 id,
    address token,
    uint256 amount
  )
    external
    view
    returns (
      uint256 fee,
      uint256 worth,
      uint256 worth1e18,
      uint256 newDebt1e18,
      uint256 newPrice
    );

  /**
   * @dev Buy Lab
   * @param id - Bond id
   * @param token - Stablecoin address
   * @param maxAmount - The max number of Lab the user wants to buy
   * @param desired - The max amount of stablecoins that users are willing to pay
   * @return worth - The amount of stablecoins actually paid by user
   * @return amount - The number of Lab actually purchased by the user
   * @return newDebt1e18 - Newly incurred treasury debt(1e18)
   * @return fee - The fee charged by the developer(Lab)
   */
  function buy(
    uint256 id,
    address token,
    uint256 maxAmount,
    uint256 desired
  )
    external
    returns (
      uint256 worth,
      uint256 amount,
      uint256 newDebt1e18,
      uint256 fee
    );

  /**
   * @dev Estimate how much stablecoin it will cost to claim Lab
   * @param user - User address
   * @param amount - Claim amount
   * @param token - Stablecoin address
   * @return repayDebt - Debt the user needs to pay
   */
  function estimateClaim(
    address user,
    uint256 amount,
    address token
  ) external view returns (uint256 repayDebt);

  /**
   * @dev Claim Lab
   * @param amount - Claim amount
   * @param token - Stablecoin address
   * @return repayDebt -  Debt the user needs to pay
   */
  function claim(uint256 amount, address token)
    external
    returns (uint256 repayDebt);

  /**
   * @dev Claim Lab for user
   * @param userAddress - User address
   * @param amount - Claim amount
   * @param token - Stablecoin address
   * @return repayDebt -  Debt the user needs to pay
   */
  function claimFor(
    address userAddress,
    uint256 amount,
    address token
  ) external returns (uint256 repayDebt);

  /**
   * @dev Add a new bond.
   *      The caller must be the owner.
   * @param startAt - Start timestamp
   * @param endAt - End timestamp
   * @param deductedPrice - The price of Lab borne by the treasury
   * @param maxAmount -  The total amount of Lab issued by bonds
   * @param releaseDuration - The duration for the linear release of the reward
   * @return id - New bond id
   */
  function add(
    uint256 startAt,
    uint256 endAt,
    uint256 deductedPrice,
    uint256 maxAmount,
    uint256 releaseDuration
  ) external returns (uint256);

  /**
   * @dev Stop a bond.
   *      The caller must be the owner.
   * @param id - Bond id
   */
  function stop(uint256 id) external;
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./IMarket.sol";
import "./IBank.sol";
import "./IStakePool.sol";

interface IHelper {
  // Lab token address.
  function Lab() external view returns (IERC20);

  // prLab token address.
  function prLab() external view returns (IERC20);

  // DSD token address.
  function DSD() external view returns (IERC20);

  // DSD token address.
  function market() external view returns (IMarket);

  // Market contract address.
  function bank() external view returns (IBank);

  // Bank contract address.
  function pool() external view returns (IStakePool);

  /**
   * @dev Invest stablecoin to ONC.
   *      1. buy Lab with stablecoin
   *      2. stake Lab to pool
   *      3. borrow DSD(if needed)
   *      4. buy Lab with DSD(if needed)
   *      5. stake Lab to pool(if needed)
   * @param token - Stablecoin address
   * @param tokenWorth - Amount of stablecoin
   * @param desired - Minimum amount of Lab user want to buy
   * @param borrow - Whether to borrow DSD
   */
  function invest(
    address token,
    uint256 tokenWorth,
    uint256 desired,
    bool borrow
  ) external;

  /**
   * @dev Reinvest stablecoin to ONC.
   *      1. claim reward
   *      2. realize prLab with stablecoin
   *      3. stake Lab to pool
   * @param token - Stablecoin address
   * @param amount - prLab amount
   * @param desired -  Maximum amount of stablecoin users are willing to pay(used to realize prLab)
   */
  function reinvest(
    address token,
    uint256 amount,
    uint256 desired
  ) external;

  /**
   * @dev Borrow DSD and invest to ONC.
   *      1. borrow DSD
   *      2. buy Lab with DSD
   *      3. stake Lab to pool
   * @param amount - Amount of DSD
   */
  function borrowAndInvest(uint256 amount) external;
}


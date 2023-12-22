// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Context.sol";
import "./IMarket.sol";
import "./IBank.sol";
import "./IStakePool.sol";
import "./IHelper.sol";

contract Helper is Context {
  using SafeERC20 for IERC20;

  // Lab token address.
  IERC20 public Lab;
  // prLab token address.
  IERC20 public prLab;
  // DSD token address.
  IERC20 public DSD;
  // Market contract address.
  IMarket public market;
  // Bank contract address.
  IBank public bank;
  // Pool contract address.
  IStakePool public pool;

  constructor(
    IERC20 _Lab,
    IERC20 _prLab,
    IERC20 _DSD,
    IMarket _market,
    IBank _bank,
    IStakePool _pool
  ) {
    Lab = _Lab;
    prLab = _prLab;
    DSD = _DSD;
    market = _market;
    bank = _bank;
    pool = _pool;
  }

  /**
   * @dev Invest stablecoin to ONC.
   *      1. buy Lab with stablecoin
   *      2. stake Lab to pool
   *      3. borrow DSD(if needed)
   *      4. buy Lab with DSD(if needed)
   *      5. stake Lab to pool(if needed)
   *      6. Loop it (if needed)
   * @param token - Stablecoin address
   * @param tokenWorth - Amount of stablecoin
   * @param desired - Minimum amount of Lab user want to buy
   * @param borrow - Whether to borrow DSD
   */
  function invest(
    address token,
    uint256 tokenWorth,
    uint256 desired,
    bool borrow,
    bool loop
  ) public {
    IERC20(token).safeTransferFrom(_msgSender(), address(this), tokenWorth);
    IERC20(token).approve(address(market), tokenWorth);
    (uint256 lab, ) = market.buyFor(token, tokenWorth, desired, _msgSender());
    Lab.approve(address(pool), lab);
    pool.depositFor(0, lab, _msgSender());
    uint256 rest;
    if (borrow || loop) {
      rest = borrowAndInvest((lab * market.f()) / 1e18);
    }
    if (loop) {
      while (rest > 1e18) rest = borrowAndInvest((rest * market.f()) / 1e18);
    }
  }

  /**
   * @dev Reinvest stablecoin to ONC.
   *      1. realize prLab with stablecoin
   *      2. stake Lab to pool
   * @param token - Stablecoin address
   * @param amount - prLab amount
   * @param desired -  Maximum amount of stablecoin users are willing to pay(used to realize prLab)
   */
  function reinvest(
    address token,
    uint256 amount,
    uint256 desired
  ) external {
    prLab.transferFrom(_msgSender(), address(this), amount);
    (, uint256 worth) = market.estimateRealize(amount, token);
    IERC20(token).safeTransferFrom(_msgSender(), address(this), worth);
    IERC20(token).approve(address(market), worth);
    prLab.approve(address(market), amount);
    market.realizeFor(amount, token, desired, _msgSender());
    Lab.approve(address(pool), amount);
    pool.depositFor(0, amount, _msgSender());
  }

  /**
   * @dev Borrow DSD and invest to ONC.
   *      1. borrow DSD
   *      2. buy Lab with DSD
   *      3. stake Lab to pool
   * @param amount - Amount of DSD
   */
  function borrowAndInvest(uint256 amount) public returns (uint256) {
    (uint256 borrowed, ) = bank.borrowFrom(_msgSender(), amount);
    DSD.approve(address(market), borrowed);
    (uint256 lab, ) = market.buyFor(address(DSD), borrowed, 0, _msgSender());
    Lab.approve(address(pool), lab);
    pool.depositFor(0, lab, _msgSender());
    return (lab);
  }
}


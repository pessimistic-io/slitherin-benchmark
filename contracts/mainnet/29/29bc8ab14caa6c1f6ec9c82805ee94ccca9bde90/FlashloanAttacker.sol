// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {SafeMath} from "./SafeMath.sol";
import {IERC20} from "./IERC20.sol";
import {GPv2SafeERC20} from "./GPv2SafeERC20.sol";
import {SafeMath} from "./SafeMath.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {FlashLoanSimpleReceiverBase} from "./FlashLoanSimpleReceiverBase.sol";
import {MintableERC20} from "./MintableERC20.sol";
import {IL1Pool} from "./IL1Pool.sol";
import {DataTypes} from "./DataTypes.sol";

contract FlashloanAttacker is FlashLoanSimpleReceiverBase {
  using GPv2SafeERC20 for IERC20;
  using SafeMath for uint256;

  IPoolAddressesProvider internal _provider;
  IL1Pool internal _pool;

  constructor(IPoolAddressesProvider provider) FlashLoanSimpleReceiverBase(provider) {
    _pool = IL1Pool(provider.getPool());
  }

  function supplyAsset(address asset, uint256 amount) public {
    MintableERC20 token = MintableERC20(asset);
    token.mint(amount);
    token.approve(address(_pool), type(uint256).max);
    _pool.supply(asset, amount, address(this), 0);
  }

  function _innerBorrow(address asset) internal {
    DataTypes.ReserveData memory config = _pool.getReserveData(asset);
    IERC20 token = IERC20(asset);
    uint256 avail = token.balanceOf(config.aTokenAddress);
    _pool.borrow(asset, avail, 2, 0, address(this));
  }

  function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address, // initiator
    bytes memory // params
  ) public override returns (bool) {
    MintableERC20 token = MintableERC20(asset);
    uint256 amountToReturn = amount.add(premium);

    // Also do a normal borrow here in the middle
    _innerBorrow(asset);

    token.mint(premium);
    IERC20(asset).approve(address(POOL), amountToReturn);

    return true;
  }
}


// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./BaseDelegator.sol";

import "./IOvernightExchange.sol";

contract OvernightAggregator is BaseDelegator {
  /* solhint-disable no-empty-blocks */

  constructor(
    address asset,
    address exchangeContract
  ) BaseDelegator(asset, exchangeContract) {}

  function delegatorName()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "overnight";
  }

  function delegatorType()
    external
    pure
    virtual
    override
    returns (string memory)
  {
    return "Aggregator";
  }

  function deposit(uint256 amount) external virtual override onlyLinkedVault {
    SafeERC20.safeTransferFrom(
      IERC20(asset()),
      linkedVault(),
      address(this),
      amount
    );

    MintParams memory params;

    params.asset = asset();
    params.amount = amount;
    params.referral = "";

    IOvernightExchange(underlyingContract()).mint(params);

    emit Deposit(amount);
  }

  function withdraw(uint256 amount) external virtual override onlyLinkedVault {
    IOvernightExchange(underlyingContract()).redeem(asset(), amount);

    SafeERC20.safeTransfer(
      IERC20(IOvernightExchange(underlyingContract()).usdPlus()),
      linkedVault(),
      amount
    );

    emit Withdraw(amount);
  }

  function totalAssets() public view virtual override returns (uint256) {
    return
      IERC20(IOvernightExchange(underlyingContract()).usdPlus()).balanceOf(
        address(this)
      );
  }
}


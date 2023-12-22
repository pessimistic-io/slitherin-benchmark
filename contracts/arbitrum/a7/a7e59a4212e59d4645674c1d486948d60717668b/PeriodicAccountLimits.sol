// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IPeriodicAccountLimits} from "./IPeriodicAccountLimits.sol";

contract PeriodicAccountLimits is IPeriodicAccountLimits {
  uint256 private _accountLimitResetPeriod;
  uint256 private _accountLimitPerPeriod;
  mapping(address => uint256) private _accountToLastPeriodReset;
  mapping(address => uint256) private _accountToAmountThisPeriod;

  function exceedsAccountLimit(address account, uint256 amount)
    public
    view
    returns (bool)
  {
    if (
      _accountToLastPeriodReset[account] + _accountLimitResetPeriod <
      block.timestamp
    ) {
      return amount > _accountLimitPerPeriod;
    }
    return
      _accountToAmountThisPeriod[account] + amount > _accountLimitPerPeriod;
  }

  function setAccountLimitResetPeriod(uint256 accountLimitResetPeriod)
    public
    virtual
    override
  {
    _accountLimitResetPeriod = accountLimitResetPeriod;
    emit AccountLimitResetPeriodChange(accountLimitResetPeriod);
  }

  function setAccountLimitPerPeriod(uint256 accountLimitPerPeriod)
    public
    virtual
    override
  {
    _accountLimitPerPeriod = accountLimitPerPeriod;
    emit AccountLimitPerPeriodChange(accountLimitPerPeriod);
  }

  function getAccountLimitResetPeriod()
    external
    view
    override
    returns (uint256)
  {
    return _accountLimitResetPeriod;
  }

  function getAccountLimitPerPeriod()
    external
    view
    override
    returns (uint256)
  {
    return _accountLimitPerPeriod;
  }

  function getLastPeriodReset(address account)
    external
    view
    override
    returns (uint256)
  {
    return _accountToLastPeriodReset[account];
  }

  function getAmountThisPeriod(address account)
    external
    view
    override
    returns (uint256)
  {
    return _accountToAmountThisPeriod[account];
  }

  function _addAmount(address account, uint256 amount) internal {
    if (
      _accountToLastPeriodReset[account] + _accountLimitResetPeriod <
      block.timestamp
    ) {
      _accountToLastPeriodReset[account] = block.timestamp;
      _accountToAmountThisPeriod[account] = 0;
    }
    _accountToAmountThisPeriod[account] =
      _accountToAmountThisPeriod[account] +
      amount;
  }
}


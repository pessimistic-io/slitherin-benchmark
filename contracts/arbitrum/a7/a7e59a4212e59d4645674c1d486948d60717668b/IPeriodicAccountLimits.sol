// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

interface IPeriodicAccountLimits {
  event AccountLimitPerPeriodChange(uint256 limit);
  event AccountLimitResetPeriodChange(uint256 period);

  error AccountLimitExceeded(address account, uint256 amount);

  function setAccountLimitResetPeriod(uint256 accountLimitResetPeriod)
    external;

  function setAccountLimitPerPeriod(uint256 accountLimitPerPeriod) external;

  function getAccountLimitResetPeriod() external view returns (uint256);

  function getAccountLimitPerPeriod() external view returns (uint256);

  function getLastPeriodReset(address account) external view returns (uint256);

  function getAmountThisPeriod(address account)
    external
    view
    returns (uint256);
}


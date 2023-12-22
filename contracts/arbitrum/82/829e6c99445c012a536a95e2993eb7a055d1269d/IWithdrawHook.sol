// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IHook.sol";

interface IWithdrawHook is IHook {
  event GlobalPeriodLengthChange(uint256 period);

  event GlobalWithdrawLimitPerPeriodChange(uint256 limit);

  function setGlobalPeriodLength(uint256 globalPeriodLength) external;

  function setGlobalWithdrawLimitPerPeriod(
    uint256 globalWithdrawLimitPerPeriod
  ) external;

  function getGlobalPeriodLength() external view returns (uint256);

  function getGlobalWithdrawLimitPerPeriod() external view returns (uint256);

  function getLastGlobalPeriodReset() external view returns (uint256);

  function getGlobalAmountWithdrawnThisPeriod()
    external
    view
    returns (uint256);

  function MAX_GLOBAL_PERIOD_LENGTH() external pure returns (uint256);
}


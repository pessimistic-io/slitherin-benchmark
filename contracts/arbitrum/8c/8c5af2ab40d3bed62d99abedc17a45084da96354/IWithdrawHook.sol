// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IHook} from "./IHook.sol";

interface IWithdrawHook is IHook {
  event GlobalPeriodLengthChange(uint256 period);
  event GlobalWithdrawLimitPerPeriodChange(uint256 limit);

  error GlobalPeriodTooLong();
  error GlobalWithdrawLimitExceeded();
  error GlobalWithdrawLimitTooLow();

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

  function getEffectiveGlobalWithdrawLimitPerPeriod()
    external
    view
    returns (uint256);

  function MIN_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD()
    external
    view
    returns (uint256);

  function SET_ACCOUNT_LIST_ROLE() external view returns (bytes32);

  function SET_COLLATERAL_ROLE() external view returns (bytes32);

  function SET_DEPOSIT_RECORD_ROLE() external view returns (bytes32);

  function SET_GLOBAL_PERIOD_LENGTH_ROLE() external view returns (bytes32);

  function SET_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD_ROLE()
    external
    view
    returns (bytes32);

  function SET_TREASURY_ROLE() external view returns (bytes32);

  function SET_AMOUNT_MULTIPLIER_ROLE() external view returns (bytes32);

  function SET_TOKEN_SENDER_ROLE() external view returns (bytes32);

  function MAX_GLOBAL_PERIOD_LENGTH() external pure returns (uint256);

  function MIN_GLOBAL_WITHDRAW_LIMIT_PERCENT_PER_PERIOD()
    external
    pure
    returns (uint256);
}


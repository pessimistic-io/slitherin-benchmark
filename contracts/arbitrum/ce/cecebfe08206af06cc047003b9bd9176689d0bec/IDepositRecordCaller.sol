// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IDepositRecord} from "./IDepositRecord.sol";

interface IDepositRecordCaller {
  event DepositRecordChange(IDepositRecord depositRecord);

  function setDepositRecord(IDepositRecord depositRecord) external;

  function getDepositRecord() external view returns (IDepositRecord);
}


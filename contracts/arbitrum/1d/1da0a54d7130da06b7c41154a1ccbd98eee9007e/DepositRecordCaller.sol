// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IDepositRecordCaller.sol";

contract DepositRecordCaller is IDepositRecordCaller {
  IDepositRecord internal _depositRecord;

  function setDepositRecord(IDepositRecord depositRecord)
    public
    virtual
    override
  {
    _depositRecord = depositRecord;
    emit DepositRecordChange(depositRecord);
  }

  function getDepositRecord() external view override returns (IDepositRecord) {
    return _depositRecord;
  }
}


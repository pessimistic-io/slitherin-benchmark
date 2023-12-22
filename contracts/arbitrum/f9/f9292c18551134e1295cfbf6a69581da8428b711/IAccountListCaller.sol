// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IAccountList} from "./IAccountList.sol";

interface IAccountListCaller {
  event AccountListChange(IAccountList accountList);

  function setAccountList(IAccountList accountList) external;

  function getAccountList() external view returns (IAccountList);
}


// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IAccountList} from "./IAccountList.sol";

interface IAllowedMsgSenders {
  event AllowedMsgSendersChange(IAccountList allowedMsgSenders);
  error MsgSenderNotAllowed();

  function setAllowedMsgSenders(IAccountList allowedMsgSenders) external;

  function getAllowedMsgSenders() external view returns (IAccountList);
}


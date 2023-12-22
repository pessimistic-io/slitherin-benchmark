// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./ITokenSender.sol";

interface ITokenSenderCaller {
  event TokenSenderChange(address sender);

  function setTokenSender(ITokenSender tokenSender) external;

  function getTokenSender() external returns (ITokenSender);
}


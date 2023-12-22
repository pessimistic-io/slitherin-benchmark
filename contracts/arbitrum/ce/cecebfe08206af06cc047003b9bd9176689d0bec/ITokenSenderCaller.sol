// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {ITokenSender} from "./ITokenSender.sol";

interface ITokenSenderCaller {
  event AmountMultiplierChange(address account, uint256 multiplier);
  event TokenSenderChange(address sender);

  error InvalidAccount();

  function setTokenSender(ITokenSender tokenSender) external;

  function setAmountMultiplier(address account, uint256 amountMultiplier)
    external;

  function getTokenSender() external view returns (ITokenSender);

  function getAmountMultiplier(address account)
    external
    view
    returns (uint256);

  function PERCENT_UNIT() external view returns (uint256);
}


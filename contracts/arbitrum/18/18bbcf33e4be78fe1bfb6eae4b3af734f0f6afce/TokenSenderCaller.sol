// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {ITokenSender, ITokenSenderCaller} from "./ITokenSenderCaller.sol";

contract TokenSenderCaller is ITokenSenderCaller {
  mapping(address => uint256) internal _accountToAmountMultiplier;
  ITokenSender internal _tokenSender;

  uint256 public constant override PERCENT_UNIT = 1000000;

  function setAmountMultiplier(address account, uint256 amountMultiplier)
    public
    virtual
    override
  {
    _accountToAmountMultiplier[account] = amountMultiplier;
    emit AmountMultiplierChange(account, amountMultiplier);
  }

  function setTokenSender(ITokenSender tokenSender) public virtual override {
    _tokenSender = tokenSender;
    emit TokenSenderChange(address(tokenSender));
  }

  function getAmountMultiplier(address account)
    external
    view
    override
    returns (uint256)
  {
    return _accountToAmountMultiplier[account];
  }

  function getTokenSender() external view override returns (ITokenSender) {
    return _tokenSender;
  }
}


// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./ITokenSenderCaller.sol";
import "./ITokenSender.sol";

contract TokenSenderCaller is ITokenSenderCaller {
  ITokenSender internal _tokenSender;

  function setTokenSender(ITokenSender tokenSender) public virtual override {
    _tokenSender = tokenSender;
    emit TokenSenderChange(address(tokenSender));
  }

  function getTokenSender() external view override returns (ITokenSender) {
    return _tokenSender;
  }
}


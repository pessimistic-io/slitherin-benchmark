// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import {GelatoRelayContext} from "./GelatoRelayContext.sol";

import {Address} from "./Address.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {NATIVE_TOKEN} from "./constants_Tokens.sol";

contract HedgerRelayer is GelatoRelayContext {
  using Address for address payable;
  using SafeERC20 for IERC20;

  function sendToFriend(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyGelatoRelay {
    // Payment to Gelato
    _transferRelayFee();

    if (_token == NATIVE_TOKEN) {
      payable(_to).sendValue(_amount);
    } else {
      IERC20(_token).safeTransfer(_to, _amount);
    }
  }
}


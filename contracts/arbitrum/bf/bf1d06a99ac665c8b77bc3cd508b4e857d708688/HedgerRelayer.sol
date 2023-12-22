// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import {GelatoRelayContext} from "./GelatoRelayContext.sol";

import {Address} from "./Address.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";
import {NATIVE_TOKEN} from "./constants_Tokens.sol";

contract HedgerRelayer is GelatoRelayContext, Ownable {
  using Address for address payable;
  using SafeERC20 for IERC20;

  receive() external payable {}

  modifier onlyOwnerOrGelato() {
    require(msg.sender == owner() || _isGelatoRelay(msg.sender), "Only owner or Gelato");
    _;
  }

  function sendToFriend(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyOwnerOrGelato {
    // Payment to Gelato
    _transferRelayFee();

    if (_token == NATIVE_TOKEN) {
      (bool sent, ) = payable(_to).call{value: _amount}("");
      require(sent, "Failed to send Ether");
    } else {
      IERC20(_token).safeTransfer(_to, _amount);
    }
  }

  function withdrawETH() external onlyOwner {
    uint256 balance = address(this).balance;
    (bool sent, ) = payable(owner()).call{value: balance}("");
    require(sent, "Failed to send Ether");
  }
}


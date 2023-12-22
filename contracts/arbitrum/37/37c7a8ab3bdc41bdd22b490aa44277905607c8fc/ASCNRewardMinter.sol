// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Ownable.sol";
import "./IRewardMinter.sol";
import "./ASCNToken.sol";

contract ASCNRewardMinter is IRewardMinter, Ownable {
  ASCNToken public token;

  constructor(ASCNToken _token) {
    token = _token;
  }

  function safeMint(uint256 _amount) override external onlyOwner {
    try token.mint(address(this), _amount) {}
    catch {}
  }

  function safeRewardTransfer(address _to, uint256 _amount) override external onlyOwner {
    if (_amount > 0) {
      uint256 balance = token.balanceOf(address(this));
      if (_amount > balance) {
        _amount = balance;
      }
      token.transfer(_to, _amount);
    }
  }
}


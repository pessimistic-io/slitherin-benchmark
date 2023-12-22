// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";

contract FeeCollector is Ownable {
  constructor(address _gov) {
    transferOwnership(_gov);
  }

  function collect(IERC20 _token) external onlyOwner {
    if (address(this).balance != 0) {
      payable(owner()).transfer(address(this).balance);
      emit FeeCollected(address(0), address(this).balance);
    }

    uint256 _amt = _token.balanceOf(address(this));
    _token.transfer(owner(), _amt);
    emit FeeCollected(address(_token), _amt);
  }

  event FeeCollected(address _token, uint256 _amt);
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";

interface IFeeStrategy {
  function run() external view returns (bool);
}

contract FeeCollectorV2 is Ownable {
  address private feeStrategy;

  function collect(IERC20 _token) external onlyOwner {
    if (address(this).balance != 0) {
      payable(owner()).transfer(address(this).balance);
    }

    uint256 _amt = _token.balanceOf(address(this));
    _token.transfer(owner(), _amt);
  }

  function setFeeStrategy(address _newFeeStrategy) external onlyOwner {
    feeStrategy = _newFeeStrategy;
  }

  function runStrategy() external view onlyOwner {
    bool success = IFeeStrategy(feeStrategy).run();
    if (!success) revert FAILED();
  }

  function approve(address _token, address _spender) external onlyOwner {
    IERC20(_token).approve(_spender, type(uint256).max);
  }

  error FAILED();
}


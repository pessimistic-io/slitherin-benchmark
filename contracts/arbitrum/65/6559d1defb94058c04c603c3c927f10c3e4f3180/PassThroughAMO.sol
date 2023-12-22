// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./Ownable2StepUpgradeable.sol";

import "./TokenUtils.sol";
import "./IERC20TokenReceiver.sol";

contract PassThroughAMO is IERC20TokenReceiver, Ownable2StepUpgradeable  {
  address public recipient;
  event Withdrawn(address token, address recipient, uint256 amount);

  constructor() {
    _disableInitializers();
  }

  function initialize(address recipient_) public initializer {
    recipient = recipient_;
    __Ownable2Step_init();
  }

  function setRecipient(address recipient_) external onlyOwner {
    recipient = recipient_;
  }
  
  function withdraw(address token, uint256 amount) external onlyOwner {
    TokenUtils.safeTransfer(token, recipient, amount);
  }

  function withdrawAll(address token) external onlyOwner {
    TokenUtils.safeTransfer(token, recipient, TokenUtils.safeBalanceOf(token, address(this)));
  }

  function onERC20Received(address token, uint256 amount) external override {
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

// Imports
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract Airdropper is Ownable {
  using SafeERC20 for IERC20;

  IERC20 private token;

  constructor() {
    address tokenAddr = 0xbc797d6f6698EcD5a8F3CE78C78849F2F6535cf9;
    token = IERC20(tokenAddr);
  }

  modifier whenDropIsActive() {
    assert(isActive());
    _;
  }

  function multiTransfer(address[] memory recipients, uint256[] memory amounts) whenDropIsActive onlyOwner public {
    require(recipients.length <= 200, "Too many recipients.");

    for(uint256 i = 0; i < recipients.length; i++) {
      token.safeTransfer(recipients[i], amounts[i]);
    }
  }

  function multiTransferSingleValue(address[] memory recipients, uint256 amount) whenDropIsActive onlyOwner public {
    require(recipients.length <= 200, "Too many recipients.");

    for(uint256 i = 0; i < recipients.length; i++) {
      token.safeTransfer(recipients[i], amount);
    }
  }

  function isActive() public view returns (bool) {
    return (tokensAvailable() > 0);
  }

  function tokensAvailable() public view returns (uint256) {
    return token.balanceOf(address(this));
  }
}


// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./IERC4626.sol";
import "./ReentrancyGuard.sol";

import "./IWeth.sol";

contract WithdrawAssist is ReentrancyGuard {
  address public immutable weth;
  address public immutable vault;

  constructor(address vault_) {
    weth = IERC4626(vault_).asset();
    vault = vault_;
  }

  function withdraw(uint256 amount) external nonReentrant returns (uint256) {
    uint256 shares = IERC4626(vault).withdraw(
      amount,
      address(this),
      msg.sender
    );

    IWeth(weth).withdrawTo(msg.sender, amount);

    return shares;
  }
}


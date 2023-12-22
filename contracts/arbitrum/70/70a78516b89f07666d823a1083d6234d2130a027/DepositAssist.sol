// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./IERC20.sol";
import "./IERC4626.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";

import "./IWeth.sol";

contract DepositAssist is ReentrancyGuard {
  address public immutable weth;
  address public immutable vault;

  constructor(address vault_) {
    weth = IERC4626(vault_).asset();
    vault = vault_;

    // Allow vault to use tokens in the contract
    SafeERC20.safeIncreaseAllowance(IERC20(weth), vault, type(uint256).max);
  }

  function deposit() external payable nonReentrant returns (uint256) {
    IWeth(weth).deposit{value: msg.value}();

    uint256 shares = IERC4626(vault).deposit(msg.value, msg.sender);

    return shares;
  }
}


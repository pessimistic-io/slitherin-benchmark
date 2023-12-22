// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IWithdrawERC20} from "./IWithdrawERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";

contract WithdrawERC20 is IWithdrawERC20, ReentrancyGuard {
  using SafeERC20 for IERC20;

  function withdrawERC20(
    address[] calldata erc20Tokens,
    uint256[] calldata amounts
  ) public virtual override nonReentrant {
    if (erc20Tokens.length != amounts.length) revert ArrayLengthMismatch();
    uint256 arrayLength = erc20Tokens.length;
    for (uint256 i; i < arrayLength; ) {
      IERC20(erc20Tokens[i]).safeTransfer(msg.sender, amounts[i]);
      unchecked {
        ++i;
      }
    }
  }

  function withdrawERC20(address[] calldata erc20Tokens)
    public
    virtual
    override
    nonReentrant
  {
    uint256 arrayLength = erc20Tokens.length;
    for (uint256 i; i < arrayLength; ) {
      IERC20(erc20Tokens[i]).safeTransfer(
        msg.sender,
        IERC20(erc20Tokens[i]).balanceOf(address(this))
      );
      unchecked {
        ++i;
      }
    }
  }
}


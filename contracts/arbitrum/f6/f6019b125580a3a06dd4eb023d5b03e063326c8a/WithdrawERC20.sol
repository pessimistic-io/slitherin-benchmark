// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IWithdrawERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract WithdrawERC20 is IWithdrawERC20, ReentrancyGuard {
  using SafeERC20 for IERC20;

  function withdrawERC20(
    address[] calldata erc20Tokens,
    uint256[] calldata amounts
  ) public virtual override nonReentrant {
    require(erc20Tokens.length == amounts.length, "Array length mismatch");
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


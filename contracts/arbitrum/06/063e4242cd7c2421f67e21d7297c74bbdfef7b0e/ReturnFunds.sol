// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.15;

import { Executable } from "./Executable.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { ReturnFundsData } from "./types_Common.sol";
import { IDSProxy } from "./IDSProxy.sol";
import { ETH } from "./types_Common.sol";

/**
 * @title ReturnFunds Action contract
 * @notice Returns funds sitting on a user's proxy to a user's EOA
 */
contract ReturnFunds is Executable {
  using SafeERC20 for IERC20;

  /**
   * @param data Encoded calldata that conforms to the ReturnFundsData struct
   */
  function execute(bytes calldata data, uint8[] memory) external payable override {
    ReturnFundsData memory returnData = abi.decode(data, (ReturnFundsData));
    address owner = IDSProxy(payable(address(this))).owner();
    uint256 amount;

    if (returnData.asset == ETH) {
      amount = address(this).balance;
      payable(owner).transfer(amount);
    } else {
      amount = IERC20(returnData.asset).balanceOf(address(this));
      IERC20(returnData.asset).safeTransfer(owner, amount);
    }
  }
}


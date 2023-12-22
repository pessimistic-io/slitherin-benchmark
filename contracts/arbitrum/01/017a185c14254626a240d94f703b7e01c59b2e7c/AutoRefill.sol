// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IKeeperRegistry} from "./IKeeperRegistry.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

library AutoRefill {
  using SafeERC20 for IERC20;

  function addFundsIfNeeded(
    IKeeperRegistry keeperRegistry,
    ISwapRouter router,
    IERC20 weth,
    IERC20 link,
    uint256 keeperId,
    address sof,
    uint256 ethAmount,
    uint256 minBalanceMargin
  ) internal returns (uint256 linkReceived) {
    // If keeperId is not set then do nothing
    if (keeperId == 0) return 0;

    uint256 min =
      (keeperRegistry.getMinBalanceForUpkeep(keeperId)) + minBalanceMargin;
    (,,, uint96 keeperBalance,,,,,) = keeperRegistry.getUpkeep(keeperId);

    // If keeper balance is above min then do nothing
    if (keeperBalance > min) return 0;

    // If below then topup
    // Take WETH from treasury, swap to LINK, and add to registry
    weth.safeTransferFrom(sof, address(this), ethAmount);
    linkReceived = router.exactInputSingle(
      ISwapRouter.ExactInputSingleParams(
        address(weth),
        address(link),
        3000,
        address(this),
        block.timestamp,
        ethAmount,
        0,
        0
      )
    );
    keeperRegistry.addFunds(keeperId, uint96(linkReceived));
  }
}


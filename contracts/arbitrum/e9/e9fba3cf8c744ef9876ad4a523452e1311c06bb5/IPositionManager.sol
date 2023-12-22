// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenExposure,NetTokenExposure} from "./TokenExposure.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {RebalanceAction} from "./RebalanceAction.sol";

abstract contract IPositionManager {
  function positionWorth() virtual external view returns (uint256);
  function costBasis() virtual external view returns (uint256);
  function pnl() virtual external view returns (int256);
  function exposures() virtual external view returns (TokenExposure[] memory);
  function allocation() virtual external view returns (TokenAllocation[] memory );
  function buy(uint256) virtual external returns (uint256);
  function sell(uint256) virtual external returns (uint256);
  function price() virtual external view returns (uint256);
  function canRebalance() virtual external view returns (bool);
  function rebalance(uint256 usdcAmountToHave) virtual external returns (bool) {
    RebalanceAction rebalanceAction = this.getRebalanceAction(usdcAmountToHave);
    uint256 worth = this.positionWorth();
    if (rebalanceAction == RebalanceAction.Buy) {
      this.buy(usdcAmountToHave - worth);
    } else if (rebalanceAction == RebalanceAction.Sell) {
      this.sell(worth - usdcAmountToHave);
    }

    return true;
  }

  function allocationByToken(address tokenAddress) external view returns (TokenAllocation memory) {
    TokenAllocation[] memory tokenAllocations = this.allocation();
    for (uint256 i = 0; i < tokenAllocations.length; i++) {
        if (tokenAllocations[i].tokenAddress == tokenAddress) {
          return tokenAllocations[i];
        }
    } 

    revert("Token not found");
  }

  function getRebalanceAction(uint256 usdcAmountToHave) external view returns (RebalanceAction) {
    uint256 worth = this.positionWorth();
    if (usdcAmountToHave > worth) return RebalanceAction.Buy;
    if (usdcAmountToHave < worth) return RebalanceAction.Sell;
    return RebalanceAction.Nothing; 
  }
}

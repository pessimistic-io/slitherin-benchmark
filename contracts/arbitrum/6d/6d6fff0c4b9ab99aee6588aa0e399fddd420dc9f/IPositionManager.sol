// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {TokenExposure,NetTokenExposure} from "./TokenExposure.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {RebalanceAction} from "./RebalanceAction.sol";
import {PositionManagerStats} from "./PositionManagerStats.sol";

abstract contract IPositionManager {
  uint256 public id;
  function name() virtual external view returns (string memory);
  function positionWorth() virtual external view returns (uint256);
  function costBasis() virtual external view returns (uint256);
  function pnl() virtual external view returns (int256);
  function exposures() virtual external view returns (TokenExposure[] memory);
  function allocations() virtual external view returns (TokenAllocation[] memory );
  function buy(uint256) virtual external returns (uint256);
  function sell(uint256) virtual external returns (uint256);
  function price() virtual external view returns (uint256);
  function canRebalance(uint256) virtual external view returns (bool, string memory);
  function compound() virtual external;
  function rebalance(uint256 usdcAmountToHave) virtual external returns (bool) {
    (RebalanceAction rebalanceAction, uint256 amountToBuyOrSell) = this.rebalanceInfo(usdcAmountToHave);

    if (rebalanceAction == RebalanceAction.Buy) {
      this.buy(amountToBuyOrSell);
    } else if (rebalanceAction == RebalanceAction.Sell) {
      this.sell(amountToBuyOrSell);
    }

    return true;
  }

  function rebalanceInfo(uint256 usdcAmountToHave) virtual public view returns (RebalanceAction, uint256 amountToBuyOrSell) {
    RebalanceAction rebalanceAction = this.getRebalanceAction(usdcAmountToHave);
    uint256 worth = this.positionWorth();
    uint256 usdcAmountToBuyOrSell = rebalanceAction == RebalanceAction.Buy
      ? usdcAmountToHave - worth
      : worth - usdcAmountToHave;

    return (rebalanceAction, usdcAmountToBuyOrSell);
  }

  function allocationByToken(address tokenAddress) external view returns (TokenAllocation memory) {
    TokenAllocation[] memory tokenAllocations = this.allocations();
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

  function stats() virtual external view returns (PositionManagerStats memory) {
    return PositionManagerStats({
      positionManagerAddress: address(this),
      name: this.name(),
      positionWorth: this.positionWorth(),
      costBasis: this.costBasis(),
      pnl: this.pnl(),
      tokenExposures: this.exposures(),
      tokenAllocations: this.allocations(),
      price: this.price(),
      collateralRatio: this.collateralRatio(),
      loanWorth: 0,
      liquidationLevel: 0,
      collateral: 0 
    });
  }

  function collateralRatio() virtual external view returns (uint256);
}


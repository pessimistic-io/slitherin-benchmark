// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPoolCommitter,UserCommitment} from "./IPoolCommitter.sol";
import {ERC20} from "./ERC20.sol";
import {PriceUtils} from "./PriceUtils.sol";

contract PerpPoolUtils {
  IPoolCommitter private poolCommitter;
  PriceUtils private priceUtils;
  ERC20 private poolToken;

  constructor(address _poolCommitterAddress, address _poolTokenAddress, address _priceUtilsAddress) {
    poolCommitter = IPoolCommitter(_poolCommitterAddress);
    poolToken = ERC20(_poolTokenAddress);
  }

  function getCommittedWorth(address poolPositionPurchaserAddress) external view returns (uint256) {
    uint256 totalCommitments = 0;
    uint256 currentIndex = 0;

    while (true) {
      try poolCommitter.unAggregatedCommitments(poolPositionPurchaserAddress,currentIndex) returns (uint256 intervalId) {
        UserCommitment memory userCommitment = poolCommitter.userCommitments(poolPositionPurchaserAddress, intervalId);
        totalCommitments += userCommitment.shortMintSettlement;
        currentIndex += 1;
      } catch {
        break;
      }
    }

    return currentIndex;
  }

  function getClaimedWorth(address poolPositionPurchaserAddress, address leveragedPoolAddress) external view returns (uint256) {
    uint256 balance = poolToken.balanceOf(poolPositionPurchaserAddress);
    uint256 claimedAmount =  balance * priceUtils.getShortTracerTokenPriceForPool(leveragedPoolAddress);
  }
}


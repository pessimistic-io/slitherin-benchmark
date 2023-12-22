// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPositionManager} from "./IPositionManager.sol";
import {IPurchaser,Purchase} from "./IPurchaser.sol";
import {ERC20} from "./ERC20.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {PriceUtils} from "./PriceUtils.sol";
import {ILeveragedPool} from "./ILeveragedPool.sol";
import {IPoolCommitter} from "./IPoolCommitter.sol";

contract MyceliumPoolPositionManager is IPositionManager {
  IPurchaser private poolPositionPurchaser;
  ERC20 private poolToken;
  PriceUtils private priceUtils;
  ILeveragedPool private leveragedPool;
  IPoolCommitter private poolCommitter;
  ERC20 private usdcToken; 
  
  uint256 private costBasis;
  address private trackingTokenAddress;
  uint256 private lastIntervalId;

	constructor(address _poolPositionPurchaser,  address _poolTokenAddress, address _priceUtilsAddress, address _leveragedPoolAddress, address _trackingTokenAddress, address _poolCommitterAddress, address _usdcAddress) {
    poolPositionPurchaser = IPurchaser(_poolPositionPurchaser);
    poolToken = ERC20(_poolTokenAddress);
    priceUtils = PriceUtils(_priceUtilsAddress);
    leveragedPool = ILeveragedPool(_leveragedPoolAddress);
    trackingTokenAddress = _trackingTokenAddress;
    poolCommitter = IPoolCommitter(_poolCommitterAddress);
    usdcToken = ERC20(_usdcAddress);
  }

  function PositionWorth() public view returns (uint256) {
    // uint256 balance = poolToken.balanceOf(address(poolPositionPurchaser));
    // uint256 claimedAmount =  balance * priceUtils.getShortTracerTokenPriceForPool();
    uint256 currentIndex = 0;

    while (true) {
      try poolCommitter.unAggregatedCommitments(address(this),currentIndex) returns (uint256 intervalId) {
        currentIndex += 1;
      } catch {
        break;
      }
    }

    return currentIndex;
  }

  function CostBasis() public view returns (uint256) {
    return costBasis; 
  }
  function Pnl() external view returns (int256) {
    return int256(PositionWorth()) - int256(CostBasis());
  }

  function BuyPosition(uint256 usdcAmount) external returns (uint256) {
    usdcToken.approve(address(poolPositionPurchaser), usdcAmount);
    Purchase memory purchase = poolPositionPurchaser.Purchase(usdcAmount);
    costBasis += purchase.usdcAmount;
    return purchase.tokenAmount;
  }

  function Exposures() external view returns (TokenExposure[] memory) {
    TokenExposure[] memory tokenExposures = new TokenExposure[](1);
    tokenExposures[0] = TokenExposure({
      amount: PositionWorth() * 3,
      token: trackingTokenAddress      
    });
  }
}


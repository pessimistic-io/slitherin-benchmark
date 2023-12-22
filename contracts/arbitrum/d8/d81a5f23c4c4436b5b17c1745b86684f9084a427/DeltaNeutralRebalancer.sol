// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "./Test.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {NetTokenExposure} from "./TokenExposure.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {ERC20} from "./ERC20.sol";
import {IPriceUtils} from "./IPriceUtils.sol";
import {RebalanceAction} from "./RebalanceAction.sol";

uint256 constant FACTOR_ONE_MULTIPLIER = 1*10**6;
uint256 constant FACTOR_TWO_MULTIPLIER = 1*10**12;
uint256 constant FACTOR_THREE_MULTIPLIER = 1*10**18;

struct Trade {
  uint256 usdcAmount;
  IPositionManager positionManager; 
}

struct RebalanceData {
  TokenAllocation glpBtcAllocation;
  TokenAllocation glpEthAllocation;
  TokenAllocation btcPerpAllocation;
  TokenAllocation ethPerpAllocation;
  uint256 Pglp;
  uint256 Pbtcperp;
  uint256 Pethperp;
  uint256 totalLiquidity;
  uint256 glpMultiplier;
  uint256 btcPerpMultiplier;
}

struct RebalanceQueueData {
  IPositionManager positionManager;
  uint256 usdcAmountToHave;
}

struct RebalanceQueue {
  RebalanceQueueData[] rebalanceQueueData;
  uint256 buyIndex;
  uint256 sellIndex;
}

contract DeltaNeutralRebalancer is Test {
  IPositionManager private glpPositionManager;
  IPositionManager private btcPerpPoolPositionManager;
  IPositionManager private ethPerpPoolPositionManager;
  address private btcAddress;
  address private ethAddress;
  ERC20 private usdcToken;

  constructor(
    address _btcAddress,
    address _ethAddress,
    address _usdcAddress
  ) {
    btcAddress = _btcAddress;
    ethAddress = _ethAddress; 
    usdcToken = ERC20(_usdcAddress); 
  }

  function rebalance(RebalanceQueueData[] memory rebalanceQueueData) external {
    for (uint8 i = 0; i < rebalanceQueueData.length; i++) {
      if (!rebalanceQueueData[i].positionManager.canRebalance()) {
        revert("Position manager cannot rebalance");
      }
      rebalanceQueueData[i].positionManager.rebalance(rebalanceQueueData[i].usdcAmountToHave);
    }
  }

  function getRebalanceQueue(uint256 amountOfGlpToHave, uint256 amountOfPerpPoolBtcToHave, uint256 amountOfPerpPoolEthToHave) external view returns (RebalanceQueue memory) {
    RebalanceQueue memory rebalanceQueue = RebalanceQueue({
      rebalanceQueueData: new RebalanceQueueData[](3),
      sellIndex: 0,
      buyIndex: 2
    });

    RebalanceQueue memory rebalanceQueue1 = this.addPositionManagerToRebalanceQueue(glpPositionManager, amountOfGlpToHave, rebalanceQueue);
    RebalanceQueue memory rebalanceQueue2 = this.addPositionManagerToRebalanceQueue(btcPerpPoolPositionManager, amountOfPerpPoolBtcToHave, rebalanceQueue1);
    RebalanceQueue memory rebalanceQueue3 = this.addPositionManagerToRebalanceQueue(ethPerpPoolPositionManager, amountOfPerpPoolEthToHave, rebalanceQueue2);
    return rebalanceQueue3;
  }

  function addPositionManagerToRebalanceQueue(IPositionManager positionManager, uint256 amountOfPositionToHave, RebalanceQueue memory rebalanceQueue) external view returns (RebalanceQueue memory) {
    uint256 usdcAmountToHave = amountOfPositionToHave * positionManager.price() / FACTOR_ONE_MULTIPLIER;
    RebalanceAction action = positionManager.getRebalanceAction(usdcAmountToHave);
    if (action == RebalanceAction.Buy) {
      rebalanceQueue.rebalanceQueueData[rebalanceQueue.buyIndex] = RebalanceQueueData({
        positionManager: positionManager,
        usdcAmountToHave: usdcAmountToHave 
      });
      if (rebalanceQueue.buyIndex > 0) {
        rebalanceQueue.buyIndex -= 1;
      }
    } else if (action == RebalanceAction.Sell) {
      rebalanceQueue.rebalanceQueueData[rebalanceQueue.sellIndex] = RebalanceQueueData({
        positionManager: positionManager,
        usdcAmountToHave: usdcAmountToHave  
      });
      rebalanceQueue.sellIndex += 1;
    } else {
      rebalanceQueue.rebalanceQueueData[rebalanceQueue.buyIndex] = RebalanceQueueData({
        positionManager: positionManager,
        usdcAmountToHave: usdcAmountToHave 
      });

      if (rebalanceQueue.buyIndex > 0) {
        rebalanceQueue.buyIndex -= 1;
      }
    }

    return rebalanceQueue;
  }

  function helloworld() external {
    TokenAllocation memory glpBtcAllocation = glpPositionManager.allocationByToken(btcAddress);
    TokenAllocation memory glpEthAllocation = glpPositionManager.allocationByToken(ethAddress);
    TokenAllocation memory btcPerpAllocation = btcPerpPoolPositionManager.allocationByToken(btcAddress);
    TokenAllocation memory ethPerpAllocation = ethPerpPoolPositionManager.allocationByToken(ethAddress);
  }
  function getRebalancedAllocation() external view returns (uint256, uint256, uint256) {
    uint256 totalLiquidity = this.getTotalLiquidity();
    // Get allocation information of assets inside positions
    TokenAllocation memory glpBtcAllocation = glpPositionManager.allocationByToken(btcAddress);
    TokenAllocation memory glpEthAllocation = glpPositionManager.allocationByToken(ethAddress);
    TokenAllocation memory btcPerpAllocation = btcPerpPoolPositionManager.allocationByToken(btcAddress);
    TokenAllocation memory ethPerpAllocation = ethPerpPoolPositionManager.allocationByToken(ethAddress);

    uint256 Pglp = glpPositionManager.price();
    uint256 Pbtcperp = btcPerpPoolPositionManager.price(); 
    uint256 Pethperp = ethPerpPoolPositionManager.price(); 

    RebalanceData memory rebalanceData = RebalanceData({
        glpBtcAllocation: glpBtcAllocation,
        glpEthAllocation: glpEthAllocation,
        btcPerpAllocation: btcPerpAllocation,
        ethPerpAllocation: ethPerpAllocation,
        Pglp: Pglp,
        Pbtcperp: Pbtcperp,
        Pethperp: Pethperp,
        totalLiquidity: totalLiquidity,
        glpMultiplier: 0,
        btcPerpMultiplier: 0
    });
    
    return this.calculateRebalancedPositions(rebalanceData);
  }

  function calculateRebalancedPositions(
    RebalanceData memory d
  )
  external view returns (uint256, uint256, uint256) {
    (uint256 glpMultiplier, uint256 btcPerpMultiplier) = this.calculateMultipliers(d);
    d.glpMultiplier = glpMultiplier;
    d.btcPerpMultiplier = btcPerpMultiplier;
    return this.calculatePositionsToHave(d);
  }

  function calculateMultipliers(RebalanceData memory d) external pure returns (uint256, uint256) {
    uint256 glpMultiplier = d.Pbtcperp*d.btcPerpAllocation.leverage*d.btcPerpAllocation.percentage*FACTOR_ONE_MULTIPLIER/(d.Pglp*d.glpBtcAllocation.leverage*d.glpBtcAllocation.percentage);
    uint256 btcPerpMultiplier = FACTOR_TWO_MULTIPLIER * d.Pethperp * d.ethPerpAllocation.leverage * d.ethPerpAllocation.percentage / (d.Pglp * glpMultiplier * d.glpEthAllocation.leverage * d.glpEthAllocation.percentage);
    
    return (glpMultiplier, btcPerpMultiplier);
  }

  function calculatePositionsToHave(RebalanceData memory d) external view returns (uint256, uint256, uint256) {
    uint256 amountOfPerpEthToHave = this.calculateAmountOfEthToHave(d);
    uint256 amountOfPerpBtcToHave = this.calculateAmountOfPerpBtcToHave(d, amountOfPerpEthToHave);
    uint256 amountOfGlpToHave = this.calculateAmountOfGlpToHave(d, amountOfPerpBtcToHave);

    return (amountOfGlpToHave, amountOfPerpBtcToHave, amountOfPerpEthToHave);
  }

  function calculateAmountOfEthToHave(RebalanceData memory d) external pure returns (uint256) {
    return d.totalLiquidity * FACTOR_THREE_MULTIPLIER / (d.Pglp*d.glpMultiplier*d.btcPerpMultiplier + d.Pbtcperp*d.btcPerpMultiplier*FACTOR_ONE_MULTIPLIER + (d.Pethperp*FACTOR_TWO_MULTIPLIER));
  }

  function calculateAmountOfPerpBtcToHave(RebalanceData memory d, uint256 amountOfPerpEthToHave) external pure returns (uint256) {
    return FACTOR_ONE_MULTIPLIER * d.Pethperp * amountOfPerpEthToHave * d.ethPerpAllocation.leverage * d.ethPerpAllocation.percentage / (d.Pglp * d.glpMultiplier * d.glpEthAllocation.leverage * d.glpEthAllocation.percentage);
  }

  function calculateAmountOfGlpToHave(RebalanceData memory d, uint256 amountOfPerpBtcToHave) external pure returns (uint256) {
    return d.Pbtcperp*amountOfPerpBtcToHave*d.btcPerpAllocation.leverage*d.btcPerpAllocation.percentage/(d.Pglp*d.glpBtcAllocation.leverage*d.glpBtcAllocation.percentage);
  }

  function setGlpPositionManager(address glpPositionManagerAddress) external {
    glpPositionManager = IPositionManager(glpPositionManagerAddress);
    usdcToken.approve(address(glpPositionManager), 2**256 - 1);
  }

  function setBtcPerpPoolManager(address btcPerpPoolPositionManagerAddress) external {
    btcPerpPoolPositionManager = IPositionManager(btcPerpPoolPositionManagerAddress);
    usdcToken.approve(address(btcPerpPoolPositionManager), 2**256 - 1);
  }

  function setEthPerpPoolManager(address ethPerpPoolPositionManagerAddress) external {
    ethPerpPoolPositionManager = IPositionManager(ethPerpPoolPositionManagerAddress);
    usdcToken.approve(address(ethPerpPoolPositionManager), 2**256 - 1);
  }

  function getTotalLiquidity() external view returns (uint256) {
    uint256 availableLiquidity = 0;
    availableLiquidity += usdcToken.balanceOf(address(this));
    availableLiquidity += glpPositionManager.positionWorth();
    availableLiquidity += btcPerpPoolPositionManager.positionWorth();
    availableLiquidity += ethPerpPoolPositionManager.positionWorth();
    
    return availableLiquidity;
  }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGlpManager} from "./IGlpManager.sol";
import {IGlp} from "./IGlp.sol";
import {IPriceUtils} from "./IPriceUtils.sol";
import {IVault} from "./IVault.sol";
import {IPoolStateHelper} from "./IPoolStateHelper.sol";
import {ILeveragedPool} from "./ILeveragedPool.sol";
import {ExpectedPoolState, ILeveragedPool2} from "./IPoolStateHelper.sol";
import {PositionType} from "./PositionType.sol";

contract PriceUtils is IPriceUtils {
  IGlpManager private glpManager;
  IGlp private glp;
  IVault private vault;
  IPoolStateHelper private poolStateHelper;
  uint32 private constant USDC_MULTIPLIER = 1*10**6;
  uint32 private constant PERCENT_DIVISOR = 1000;

  constructor(address _glpManager, address _glp, address _vaultAddress, address _poolStateHelperAddress) {
    glpManager = IGlpManager(_glpManager);
    glp = IGlp(_glp);
    vault = IVault(_vaultAddress);
    poolStateHelper = IPoolStateHelper(_poolStateHelperAddress);
  }

  function glpPrice() public view returns (uint256) {
    uint256 aum = glpManager.getAumInUsdg(true);
    uint256 totalSupply = glp.totalSupply();
    
    return aum * USDC_MULTIPLIER / totalSupply;
  }

  function perpPoolTokenPrice(address leveragedPoolAddress, PositionType positionType) public view returns (uint256) {
      ExpectedPoolState memory poolState = poolStateHelper.getExpectedState(ILeveragedPool2(leveragedPoolAddress), 1);
  
      if (positionType == PositionType.Long) {
        return poolState.longBalance * USDC_MULTIPLIER / (poolState.longSupply + poolState.remainingPendingLongBurnTokens);
      }

      return poolState.shortBalance * USDC_MULTIPLIER / (poolState.shortSupply + poolState.remainingPendingShortBurnTokens);
  }
} 

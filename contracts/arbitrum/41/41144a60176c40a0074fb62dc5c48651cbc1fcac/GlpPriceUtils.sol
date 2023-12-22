// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGlpManager} from "./IGlpManager.sol";
import {IGlp} from "./IGlp.sol";
import {IGlpPriceUtils} from "./IGlpPriceUtils.sol";
import {IVault} from "./IVault.sol";

contract GlpPriceUtils is IGlpPriceUtils {
  IGlpManager private glpManager;
  IGlp private glp;
  IVault private vault;
  uint32 private constant USDC_MULTIPLIER = 1*10**6;
  uint32 private constant PERCENT_DIVISOR = 1000;

  constructor(address _glpManager, address _glp, address _vaultAddress) {
    glpManager = IGlpManager(_glpManager);
    glp = IGlp(_glp);
    vault = IVault(_vaultAddress);
  }

  function glpPrice() public view returns (uint256) {
    uint256 aum = glpManager.getAumInUsdg(true);
    uint256 totalSupply = glp.totalSupply();
    
    return aum * USDC_MULTIPLIER / totalSupply;
  }
} 

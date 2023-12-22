// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPositionManager} from "./IPositionManager.sol";
import {IPurchaser, Purchase} from "./IPurchaser.sol";
import {IPriceUtils} from "./IPriceUtils.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {IVaultReader} from "./IVaultReader.sol";
import {IGlpUtils} from "./IGlpUtils.sol";
import {Ownable} from "./Ownable.sol";

contract GlpPositionManager is IPositionManager, Ownable {
  uint256 private constant USDC_MULTIPLIER = 1*10**6;
  uint256 private constant GLP_MULTIPLIER = 1*10**18;

  uint256 private costBasis;
  uint256 private tokenAmount;

  IPurchaser private glpPurchaser;
  IPriceUtils private priceUtils;
  IGlpUtils private glpUtils;
  address[] private glpTokens;

  constructor(address _glpPurchaserAddress, address _priceUtilsAddress, address _glpUtilsAddress) {
    glpPurchaser = IPurchaser(_glpPurchaserAddress);
    priceUtils = IPriceUtils(_priceUtilsAddress);
    glpUtils = IGlpUtils(_glpUtilsAddress);
  }

  function PositionWorth() public view returns (uint256) {
    uint256 glpPrice = priceUtils.glpPrice();
    return tokenAmount * glpPrice / GLP_MULTIPLIER;
  }

  function CostBasis() public view returns (uint256) {
    return costBasis;
  }

  function BuyPosition(uint256 usdcAmount) external returns (uint256) {
    Purchase memory purchase = glpPurchaser.Purchase(usdcAmount);
    costBasis += purchase.usdcAmount;
    tokenAmount += purchase.tokenAmount;  
    return purchase.tokenAmount;
  }

  function Pnl() external view returns (int256) {
    return int256(PositionWorth()) - int256(CostBasis());
  }

  function Exposures() external view returns (TokenExposure[] memory) {
    return glpUtils.getGlpTokenExposure(PositionWorth(), glpTokens);
  }

  function setGlpTokens(address[] memory _glpTokens) external onlyOwner() {
    glpTokens = _glpTokens;
  }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Test.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {IPriceUtils} from "./IPriceUtils.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {IVaultReader} from "./IVaultReader.sol";
import {IGlpUtils} from "./IGlpUtils.sol";
import {Ownable} from "./Ownable.sol";
import {IPoolCommitter} from "./IPoolCommitter.sol";
import {ERC20} from "./ERC20.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {GlpTokenAllocation} from "./GlpTokenAllocation.sol";
import {DeltaNeutralRebalancer} from "./DeltaNeutralRebalancer.sol";
import {IRewardRouter} from "./IRewardRouter.sol";

contract GlpPositionManager is IPositionManager, Ownable, Test {
  uint256 private constant USDC_MULTIPLIER = 1*10**6;
  uint256 private constant GLP_MULTIPLIER = 1*10**18;
  uint256 private constant PERCENT_DIVISOR = 1000;
  uint256 private constant BASIS_POINTS_DIVISOR = 10000;
  uint256 private constant DEFAULT_SLIPPAGE = 30;
  uint256 private constant PRICE_PRECISION = 10 ** 30;

  uint256 private _costBasis;
  uint256 private tokenAmount;

  IPriceUtils private priceUtils;
  IGlpUtils private glpUtils;
  IPoolCommitter private poolCommitter;
  DeltaNeutralRebalancer private deltaNeutralRebalancer;
  ERC20 private usdcToken;
  IRewardRouter private rewardRouter;
  address[] private glpTokens;

  modifier onlyRebalancer {
    require(msg.sender == address(deltaNeutralRebalancer));
    _;
  }

  constructor(address _priceUtilsAddress, address _glpUtilsAddress, address _poolCommitterAddress, address _usdcAddress, address _rewardRouterAddress, address _deltaNeutralRebalancerAddress) {
    priceUtils = IPriceUtils(_priceUtilsAddress);
    glpUtils = IGlpUtils(_glpUtilsAddress);
    poolCommitter = IPoolCommitter(_poolCommitterAddress);
    usdcToken = ERC20(_usdcAddress);
    deltaNeutralRebalancer = DeltaNeutralRebalancer(_deltaNeutralRebalancerAddress);
    rewardRouter = IRewardRouter(_rewardRouterAddress);
  }

  function positionWorth() override public view returns (uint256) {
    uint256 glpPrice = priceUtils.glpPrice();
    return (tokenAmount * glpPrice / GLP_MULTIPLIER);
  }

  function costBasis() override public view returns (uint256) {
    return _costBasis;
  }

  function buy(uint256 usdcAmount) override external returns (uint256) {
    // uint256 currentPrice = priceUtils.glpPrice();
    // uint256 glpToPurchase = usdcAmount * currentPrice / USDC_MULTIPLIER;
    // usdcToken.transferFrom(address(deltaNeutralRebalancer), address(this), 100);
    uint256 glpAmount = IRewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1).mintAndStakeGlp(address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8), 100, 0, 60);

    // _costBasis += 100;
    // tokenAmount += glpAmount;  
    // return glpAmount;
    return 0;
  }

  function sell(uint256 usdcAmount) override external returns (uint256) {
    uint256 currentPrice = priceUtils.glpPrice();
    uint256 glpToSell = usdcAmount * currentPrice / USDC_MULTIPLIER;
    uint256 usdcAmountAfterSlippage = usdcAmount * (BASIS_POINTS_DIVISOR - DEFAULT_SLIPPAGE) / BASIS_POINTS_DIVISOR;

    uint256 usdcRetrieved = rewardRouter.unstakeAndRedeemGlp(address(usdcToken), glpToSell, usdcAmountAfterSlippage, address(deltaNeutralRebalancer));
    _costBasis -= usdcRetrieved;
    tokenAmount -= glpToSell;
    return usdcRetrieved;
  }

  function pnl() override external view returns (int256) {
    return int256(positionWorth()) - int256(costBasis());
  }

  function exposures() override external view returns (TokenExposure[] memory) {
    return glpUtils.getGlpTokenExposure(positionWorth(), glpTokens);
  }

  function allocation() override external view returns (TokenAllocation[] memory) {
    GlpTokenAllocation[] memory glpAllocations = glpUtils.getGlpTokenAllocations(glpTokens);
    TokenAllocation[] memory tokenAllocations = new TokenAllocation[](glpAllocations.length);

    for (uint i = 0; i < glpAllocations.length; i++) {
      tokenAllocations[i] = TokenAllocation({
        tokenAddress: glpAllocations[i].tokenAddress,
        percentage: glpAllocations[i].allocation,
        leverage: 1
      });
    }

    return tokenAllocations;
  }

  function canRebalance() override external pure returns (bool) {
    return true;
  }

  function price() override external view returns (uint256) {
    return priceUtils.glpPrice();
  }

  function setGlpTokens(address[] memory _glpTokens) external onlyOwner() {
    glpTokens = _glpTokens;
  }
}


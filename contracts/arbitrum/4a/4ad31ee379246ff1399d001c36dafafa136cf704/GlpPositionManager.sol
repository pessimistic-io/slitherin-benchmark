// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Test.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {PriceUtils} from "./PriceUtils.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {IVaultReader} from "./IVaultReader.sol";
import {GlpUtils} from "./GlpUtils.sol";
import {Ownable} from "./Ownable.sol";
import {ERC20} from "./ERC20.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {GlpTokenAllocation} from "./GlpTokenAllocation.sol";
import {DeltaNeutralRebalancer} from "./DeltaNeutralRebalancer.sol";
import {IRewardRouter} from "./IRewardRouter.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {ProtohedgeVault} from "./ProtohedgeVault.sol";
import {PositionType} from "./PositionType.sol";
import {Math} from "./Math.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";


contract GlpPositionManager is IPositionManager, Initializable, UUPSUpgradeable, OwnableUpgradeable {
  uint256 private constant USDC_MULTIPLIER = 1*10**6;
  uint256 private constant GLP_MULTIPLIER = 1*10**18;
  uint256 private constant PERCENT_DIVISOR = 1000;
  uint256 private constant BASIS_POINTS_DIVISOR = 10000;
  uint256 private constant DEFAULT_SLIPPAGE = 30;
  uint256 private constant PRICE_PRECISION = 10 ** 30;
  uint256 private constant ETH_PRICE_DIVISOR = 1*10**20;

  uint256 private _costBasis;
  uint256 private tokenAmount;

  PriceUtils private priceUtils;
  GlpUtils private glpUtils;
  ProtohedgeVault private protohedgeVault;
  ERC20 private usdcToken;
  ERC20 private wethToken;
  IRewardRouter private rewardRouter;
  IGlpManager private glpManager;
  address private ethPriceFeedAddress;
  address[] private glpTokens;

  modifier onlyVault {
    require(msg.sender == address(protohedgeVault));
    _;
  }

  function initialize(
    address _priceUtilsAddress,
    address _glpUtilsAddress,
    address _glpManagerAddress,
    address _usdcAddress,
    address _wethAddress,
    address _ethPriceFeedAddress, 
    address _rewardRouterAddress,
    address _protohedgeVaultAddress 
  ) public initializer {
    priceUtils = PriceUtils(_priceUtilsAddress);
    glpUtils = GlpUtils(_glpUtilsAddress);
    usdcToken = ERC20(_usdcAddress);
    wethToken = ERC20(_wethAddress);
    protohedgeVault = ProtohedgeVault(_protohedgeVaultAddress);
    rewardRouter = IRewardRouter(_rewardRouterAddress);
    glpManager = IGlpManager(_glpManagerAddress);
    ethPriceFeedAddress = _ethPriceFeedAddress;

    __Ownable_init();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function name() override external pure returns (string memory) {
    return "Glp";
  }

  function positionWorth() override public view returns (uint256) {
    uint256 glpPrice = priceUtils.glpPrice();
    return (tokenAmount * glpPrice / GLP_MULTIPLIER);
  }

  function costBasis() override public view returns (uint256) {
    return _costBasis;
  }

  function buy(uint256 usdcAmount) override external returns (uint256) {
    uint256 currentPrice = priceUtils.glpPrice();
    uint256 glpToPurchase = usdcAmount * currentPrice / USDC_MULTIPLIER;
    usdcToken.transferFrom(address(protohedgeVault), address(this), usdcAmount);

    uint256 glpAmountAfterSlippage = glpToPurchase * (BASIS_POINTS_DIVISOR - DEFAULT_SLIPPAGE) / BASIS_POINTS_DIVISOR;
    usdcToken.approve(address(glpManager), usdcAmount);

    uint256 glpAmount = rewardRouter.mintAndStakeGlp(address(usdcToken), usdcAmount, 0, glpAmountAfterSlippage);

    _costBasis += usdcAmount;
    tokenAmount += glpAmount;  
    return glpAmount;
  }

  event unstakeAndRedeemGlp(address token, uint256 glpToSell, uint256 minOutput, address transferAddress);

  function sell(uint256 usdcAmount) override external returns (uint256) {
    uint256 currentPrice = priceUtils.glpPrice();
    uint256 glpToSell = Math.min(usdcAmount * currentPrice * USDC_MULTIPLIER, tokenAmount);
    uint256 usdcRetrieved = rewardRouter.unstakeAndRedeemGlp(address(usdcToken), glpToSell, 0, address(protohedgeVault));
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
        symbol: ERC20(glpAllocations[i].tokenAddress).symbol(),
        percentage: glpAllocations[i].allocation,
        leverage: 1,
        positionType: PositionType.Long
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

  function setGlpTokens(address[] memory _glpTokens) external onlyOwner {
    glpTokens = _glpTokens;
  }

  function compound() override external {
    rewardRouter.handleRewards(false, false, false, false, false, true, false);  
    uint256 amountOfWeth = wethToken.balanceOf(address(this));
    wethToken.approve(address(glpManager), amountOfWeth);
    uint256 usdcAmount = priceUtils.getTokenPrice(ethPriceFeedAddress) * amountOfWeth / ETH_PRICE_DIVISOR;
    uint256 glpAmount = rewardRouter.mintAndStakeGlp(address(wethToken), amountOfWeth, 0, 0);

    _costBasis += uint256(usdcAmount);
    tokenAmount += glpAmount;  
  }
}


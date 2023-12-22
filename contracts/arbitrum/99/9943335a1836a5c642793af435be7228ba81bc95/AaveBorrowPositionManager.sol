// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IAaveL2Pool} from "./IAaveL2Pool.sol";
import {IAaveL2Encoder} from "./IAaveL2Encoder.sol";
import {ERC20} from "./ERC20.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {TokenAllocation} from "./TokenAllocation.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {ProtohedgeVault} from "./ProtohedgeVault.sol";
import {PriceUtils} from "./PriceUtils.sol";
import {PositionType} from "./PositionType.sol";
import {IGmxRouter} from "./IGmxRouter.sol";
import {Math} from "./Math.sol";
import {USDC_MULTIPLIER,PERCENTAGE_MULTIPLIER,BASIS_POINTS_DIVISOR} from "./Constants.sol";
import {GlpUtils} from "./GlpUtils.sol";
import "./Test.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";


contract AaveBorrowPositionManager is IPositionManager, Initializable, UUPSUpgradeable, OwnableUpgradeable {
  string private positionName;
  uint256 public usdcAmountBorrowed;
  bool private _canRebalance;
  uint256 private decimals;
  address private tokenPriceFeedAddress;
  uint256 private targetLtv;
  uint256 public amountOfTokens;
  uint256 public collateral;

  IAaveL2Pool private l2Pool;
  IAaveL2Encoder private l2Encoder;
  ERC20 private usdcToken;
  ERC20 private borrowToken;
  ProtohedgeVault private protohedgeVault;
  PriceUtils private priceUtils;
  IGmxRouter private gmxRouter;
  GlpUtils private glpUtils;
   
  function initialize(
    string memory _positionName,
    uint256 _decimals,
    uint256 _targetLtv,
    address _tokenPriceFeedAddress,
    address _aaveL2PoolAddress,
    address _aaveL2EncoderAddress,
    address _usdcAddress,
    address _borrowTokenAddress,
    address _protohedgeVaultAddress,
    address _priceUtilsAddress,
    address _gmxRouterAddress,
    address _glpUtilsAddress
  ) public initializer {
    positionName = _positionName;
    decimals = _decimals;
    _canRebalance = true;
    tokenPriceFeedAddress = _tokenPriceFeedAddress;
    targetLtv = _targetLtv;

    l2Pool = IAaveL2Pool(_aaveL2PoolAddress);
    l2Encoder = IAaveL2Encoder(_aaveL2EncoderAddress);
    usdcToken = ERC20(_usdcAddress);
    borrowToken = ERC20(_borrowTokenAddress);
    protohedgeVault = ProtohedgeVault(_protohedgeVaultAddress);
    priceUtils = PriceUtils(_priceUtilsAddress);
    gmxRouter = IGmxRouter(_gmxRouterAddress);
    glpUtils = GlpUtils(_glpUtilsAddress);

    // usdcToken.approve(address(l2Pool), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    // usdcToken.approve(address(gmxRouter), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    // borrowToken.approve(address(gmxRouter), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    // borrowToken.approve(address(l2Pool), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    __Ownable_init();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function name() override public view returns (string memory) {
    return positionName;
  }

  function positionWorth() override public view returns (uint256) {
    return collateral + getLoanWorth();
  }

  function costBasis() override public view returns (uint256) {
    return collateral + usdcAmountBorrowed;
  }

  function pnl() override external view returns (int256) {
    return int256(positionWorth()) - int256(costBasis());
  }

  function buy(uint256 usdcAmount) override external returns (uint256) {
    require(protohedgeVault.getAvailableLiquidity() >= usdcAmount, "Insufficient liquidity");
    usdcToken.transferFrom(address(protohedgeVault), address(this), usdcAmount);

    bytes32 supplyArgs = l2Encoder.encodeSupplyParams(
      address(usdcToken),
      usdcAmount,
      0
    );

    l2Pool.supply(supplyArgs);

    collateral += usdcAmount;
    uint256 usdcAmountToBorrow = usdcAmount * targetLtv / 100;
    uint256 tokensToBorrow = usdcAmountToBorrow * (1*10**decimals) / price();

    bytes32 borrowArgs = l2Encoder.encodeBorrowParams(
      address(borrowToken),
      tokensToBorrow,
      2, // variable rate mode,
      0  
    );

    l2Pool.borrow(borrowArgs);

    address[] memory swapPath = new address[](2);
    swapPath[0] = address(borrowToken);
    swapPath[1] = address(usdcToken);
   
    gmxRouter.swap(swapPath, tokensToBorrow, 0, address(protohedgeVault));

    amountOfTokens += tokensToBorrow;
    usdcAmountBorrowed += usdcAmountToBorrow;
     
    return tokensToBorrow;
  }

  function sell(uint256 usdcAmount) override external returns (uint256) {
    require(collateral - usdcAmount >= 0, "Insufficient tokens to sell");
    uint256 desiredCollateral = collateral - usdcAmount;
    uint256 desiredBorrowAmount = desiredCollateral * targetLtv / 100;
    uint256 usdcAmountToRepay = getLoanWorth() - desiredBorrowAmount;
    uint256 feeBasisPoints = glpUtils.getFeeBasisPoints(address(usdcToken), address(borrowToken), usdcAmountToRepay);
    uint256 usdcAmountWithSlippage = usdcAmountToRepay * (BASIS_POINTS_DIVISOR + feeBasisPoints) / BASIS_POINTS_DIVISOR;
    usdcToken.transferFrom(address(protohedgeVault), address(this), usdcAmountWithSlippage);
    
    address[] memory swapPath = new address[](2);
    swapPath[0] = address(usdcToken);
    swapPath[1] = address(borrowToken);

    uint256 amountOut = gmxRouter.swap(swapPath, usdcAmountWithSlippage, 0, address(this));
    bytes32 repayArgs = l2Encoder.encodeRepayParams(
      address(borrowToken),
      Math.min(amountOut, amountOfTokens),
      2 // variable rate mode
    );

    l2Pool.repay(repayArgs);

    return amountOut;
  }

  function exposures() override external view returns (TokenExposure[] memory) {
    TokenExposure[] memory tokenExposures = new TokenExposure[](1);
    tokenExposures[0] = TokenExposure({
      amount: int256(positionWorth()),
      token: address(borrowToken),
      symbol: borrowToken.symbol()
    });
    return tokenExposures;
  }

  function allocation() override external view returns (TokenAllocation[] memory) {
    TokenAllocation[] memory tokenAllocations = new TokenAllocation[](1);
    tokenAllocations[0] = TokenAllocation({
      tokenAddress: address(borrowToken),
      symbol: borrowToken.symbol(),
      percentage: getLoanToValue(),
      leverage: 1,
      positionType: PositionType.Short 
    });
    return tokenAllocations;
  }

  function price() override public view returns (uint256) {
    return priceUtils.getTokenPrice(tokenPriceFeedAddress) / (1*10**2); // Convert to USDC price 
  }

  function claim() external {
  }

  function compound() override external {}

  function canRebalance() override external view returns (bool) {
    return _canRebalance;
  }

  function getLoanToValue() public view returns (uint256) {
    return getLoanWorth() * PERCENTAGE_MULTIPLIER / collateral;
  }

  function getLoanWorth() public view returns (uint256) {
    return amountOfTokens * price() / (1*10**decimals);
  }
}

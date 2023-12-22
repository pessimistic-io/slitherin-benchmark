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
import {ERC20} from "./ERC20.sol";
import {PositionManagerStats} from "./PositionManagerStats.sol";
import {IAaveProtocolDataProvider} from "./IAaveProtocolDataProvider.sol";
import {Strings} from "./Strings.sol";
import {RebalanceAction} from "./RebalanceAction.sol";

uint256 constant MIN_BUY_OR_SELL_AMOUNT = 500000;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

struct InitializeArgs {
    string  positionName;
    uint256 decimals;
    uint256 targetLtv;
    address tokenPriceFeedAddress;
    address aaveL2PoolAddress;
    address aaveL2EncoderAddress;
    address usdcAddress;
    address borrowTokenAddress;
    address protohedgeVaultAddress;
    address priceUtilsAddress;
    address gmxRouterAddress;
    address glpUtilsAddress;
    address aaveProtocolDataProviderAddress;
}

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
  IAaveProtocolDataProvider private aaveProtocolDataProvider;
   
  function initialize(InitializeArgs memory args) public initializer {
    positionName = args.positionName;
    decimals = args.decimals;
    _canRebalance = true;
    tokenPriceFeedAddress = args.tokenPriceFeedAddress;
    targetLtv = args.targetLtv;

    l2Pool = IAaveL2Pool(args.aaveL2PoolAddress);
    l2Encoder = IAaveL2Encoder(args.aaveL2EncoderAddress);
    usdcToken = ERC20(args.usdcAddress);
    borrowToken = ERC20(args.borrowTokenAddress);
    protohedgeVault = ProtohedgeVault(args.protohedgeVaultAddress);
    priceUtils = PriceUtils(args.priceUtilsAddress);
    gmxRouter = IGmxRouter(args.gmxRouterAddress);
    glpUtils = GlpUtils(args.glpUtilsAddress);
    aaveProtocolDataProvider = IAaveProtocolDataProvider(args.aaveProtocolDataProviderAddress);

    usdcToken.approve(address(l2Pool), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    usdcToken.approve(address(gmxRouter), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    borrowToken.approve(address(gmxRouter), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    borrowToken.approve(address(l2Pool), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

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
    uint256 ratio = collateralRatio();
    uint256 desiredCollateral = usdcAmount * ratio / BASIS_POINTS_DIVISOR;
    
    require(protohedgeVault.getAvailableLiquidity() >= desiredCollateral, "Insufficient liquidity");
    usdcToken.transferFrom(address(protohedgeVault), address(this), desiredCollateral);

    bytes32 supplyArgs = l2Encoder.encodeSupplyParams(
      address(usdcToken),
      desiredCollateral,
      0 
    );

    l2Pool.supply(supplyArgs);

    collateral += desiredCollateral;
    uint256 tokensToBorrow = usdcAmount * (1*10**decimals) / price();

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
    usdcAmountBorrowed += usdcAmount;
     
    return tokensToBorrow;
  }

  function sell(uint256 usdcAmount) override external returns (uint256) {
    uint256 loanWorth = getLoanWorth();
    uint256 usdcAmountToRepay = Math.min(loanWorth, usdcAmount);
    uint256 feeBasisPoints = glpUtils.getFeeBasisPoints(address(usdcToken), address(borrowToken), usdcAmountToRepay);
    uint256 usdcAmountWithSlippage = usdcAmountToRepay * (BASIS_POINTS_DIVISOR + feeBasisPoints) / BASIS_POINTS_DIVISOR;
    usdcToken.transferFrom(address(protohedgeVault), address(this), usdcAmountWithSlippage);
    
    address[] memory swapPath = new address[](2);
    swapPath[0] = address(usdcToken);
    swapPath[1] = address(borrowToken);

    uint256 amountBefore = borrowToken.balanceOf(address(this));
    gmxRouter.swap(swapPath, usdcAmountWithSlippage, 0, address(this));
    uint256 amountSwapped = Math.min(borrowToken.balanceOf(address(this)) - amountBefore, amountOfTokens);
    bytes32 repayArgs = l2Encoder.encodeRepayParams(
      address(borrowToken),
      amountSwapped,
      2 // variable rate mode
    );

    l2Pool.repay(repayArgs);

    return amountSwapped;
  }

  function exposures() override external view returns (TokenExposure[] memory) {
    TokenExposure[] memory tokenExposures = new TokenExposure[](1);
    tokenExposures[0] = TokenExposure({
      amount: -1 * int256(getLoanWorth()),
      token: address(borrowToken),
      symbol: borrowToken.symbol()
    });
    return tokenExposures;
  }

  function allocations() override external view returns (TokenAllocation[] memory) {
    TokenAllocation[] memory tokenAllocations = new TokenAllocation[](1);
    tokenAllocations[0] = TokenAllocation({
      tokenAddress: address(borrowToken),
      symbol: borrowToken.symbol(),
      percentage: BASIS_POINTS_DIVISOR,
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

  function canRebalance(uint256 amountOfUsdcToHave) override external view returns (bool, string memory) {
    (,uint256 amountToBuyOrSell) = this.rebalanceInfo(amountOfUsdcToHave);

    if (amountToBuyOrSell < MIN_BUY_OR_SELL_AMOUNT) {
      return (false, string.concat("Min sell amount is ", Strings.toString(MIN_BUY_OR_SELL_AMOUNT), "but buy or sell amount is", Strings.toString(amountToBuyOrSell)));
    }

    return (true, "");
  }

  function getLoanToValue() public view returns (uint256) {
    return collateral > 0
      ? getLoanWorth() * PERCENTAGE_MULTIPLIER / collateral
      : 0;
  }

  function getLoanWorth() public view returns (uint256) {
    return amountOfTokens * price() / (1*10**decimals);
  }

  function getLiquidationThreshold() public view returns (uint256) {
    (,,uint256 liquidationThreshold,,,,,,,) = aaveProtocolDataProvider.getReserveConfigurationData(address(borrowToken));
    return liquidationThreshold;
  }

  function getLiquidationLevel() public view returns (uint256) {
    return collateral * getLiquidationThreshold() / BASIS_POINTS_DIVISOR;
  }

  function collateralRatio() override public view returns (uint256) {
    return 100 * BASIS_POINTS_DIVISOR / targetLtv;
  }

  function stats() override external view returns (PositionManagerStats memory) {
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
      loanWorth: getLoanWorth(),
      liquidationLevel: getLiquidationLevel(),
      collateral: collateral
    });
  }
}


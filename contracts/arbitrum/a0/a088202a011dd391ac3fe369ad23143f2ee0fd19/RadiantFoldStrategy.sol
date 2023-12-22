// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./RadiantInteractorInitializable.sol";
import "./IVault.sol";
import "./BaseUpgradeableStrategy.sol";
import "./IUniswapV3Router.sol";
import "./IBVault.sol";

import "./console.sol";

contract RadiantFoldStrategy is BaseUpgradeableStrategy, RadiantInteractorInitializable {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant bVault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
  address public constant uniV3Router = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _COLLATERALFACTORNUMERATOR_SLOT = 0x129eccdfbcf3761d8e2f66393221fa8277b7623ad13ed7693a0025435931c64a;
  bytes32 internal constant _FACTORDENOMINATOR_SLOT = 0x4e92df66cc717205e8df80bec55fc1429f703d590a2d456b97b74f0008b4a3ee;
  bytes32 internal constant _BORROWTARGETFACTORNUMERATOR_SLOT = 0xa65533f4b41f3786d877c8fdd4ae6d27ada84e1d9c62ea3aca309e9aa03af1cd;
  bytes32 internal constant _FOLD_SLOT = 0x1841be4c16015a744c9fbf595f7c6b32d40278c16c1fc7cf2de88c6348de44ba;

  uint256 public suppliedInUnderlying;
  uint256 public borrowedInUnderlying;

  address[] public WETH2underlying;
  mapping(address => address[]) public reward2WETH;
  mapping(address => mapping(address => bytes32)) public poolIds;
  address[] public rewardTokens;
  mapping(address => mapping(address => uint24)) public storedPairFee;

  constructor() public BaseUpgradeableStrategy() {
    assert(_COLLATERALFACTORNUMERATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.collateralFactorNumerator")) - 1));
    assert(_FACTORDENOMINATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.factorDenominator")) - 1));
    assert(_BORROWTARGETFACTORNUMERATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.borrowTargetFactorNumerator")) - 1));
    assert(_FOLD_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.fold")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _atoken,
    address _lendingPool,
    address _incentivesController,
    uint256 _borrowTargetFactorNumerator,
    uint256 _collateralFactorNumerator,
    uint256 _factorDenominator,
    bool _fold
  )
  public initializer {
    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _incentivesController,
      weth,
      harvestMSIG
    );

    RadiantInteractorInitializable.initialize(_underlying, _atoken, _lendingPool);

    require(IVault(_vault).underlying() == _underlying, "vault does not support underlying");
    _setFactorDenominator(_factorDenominator);
    _setCollateralFactorNumerator(_collateralFactorNumerator);
    require(_borrowTargetFactorNumerator < collateralFactorNumerator(), "Target should be lower than collateral limit");
    setUint256(_BORROWTARGETFACTORNUMERATOR_SLOT, _borrowTargetFactorNumerator);
    setBoolean(_FOLD_SLOT, _fold);
  }

  modifier updateSupplyInTheEnd() {
    _;
    // amount we supplied
    suppliedInUnderlying = IAToken(aToken()).balanceOf(address(this));
    console.log("SUPPLIED:", suppliedInUnderlying);
    // amount we borrowed
    borrowedInUnderlying = getBorrowBalance();
    console.log("BORROWED:", borrowedInUnderlying);
    if(suppliedInUnderlying != 0){
      console.log("LTV:     ", borrowedInUnderlying.mul(100000).div(suppliedInUnderlying));
    }
  }

  function depositArbCheck() public pure returns (bool) {
    // there's no arb here.
    return true;
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying() || token == aToken());
  }

  /**
  * The strategy invests by supplying the underlying as a collateral.
  */
  function investAllUnderlying() public restricted updateSupplyInTheEnd {
    address _underlying = underlying();
    address _aToken = aToken();
    uint _denom = factorDenominator();
    uint _borrowNum = borrowTargetFactorNumerator();
    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    if (underlyingBalance > 0) {
      _supply(underlyingBalance);
    }
    if (!fold()) {
      return;
    }
    // amount we supplied
    uint256 supplied = IAToken(_aToken).balanceOf(address(this));
    // amount we borrowed
    uint256 borrowed = getBorrowBalance();
    uint256 balance = supplied.sub(borrowed);
    uint256 borrowTarget = balance.mul(_borrowNum).div(_denom.sub(_borrowNum));
    while (borrowed < borrowTarget) {
      uint256 wantBorrow = borrowTarget.sub(borrowed);
      uint256 maxBorrow = supplied.mul(collateralFactorNumerator()).div(_denom).sub(borrowed);
      _borrow(Math.min(wantBorrow, maxBorrow));
      underlyingBalance = IERC20(_underlying).balanceOf(address(this));
      if (underlyingBalance > 0) {
        _supply(underlyingBalance);
      }
      //update parameters
      supplied = IAToken(_aToken).balanceOf(address(this));
      borrowed = getBorrowBalance();
      balance = supplied.sub(borrowed);
    }
  }

  /**
  * Exits Radiant and transfers everything to the vault.
  */
  function withdrawAllToVault() external restricted updateSupplyInTheEnd {
    address _underlying = underlying();
    withdrawMaximum(true);
    if (IERC20(_underlying).balanceOf(address(this)) > 0) {
      IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
    }
  }

  function emergencyExit() external onlyGovernance updateSupplyInTheEnd {
    withdrawMaximum(false);
  }

  function withdrawMaximum(bool claim) internal updateSupplyInTheEnd {
    if (claim) {
      claimRewards();
      liquidateRewards();
    }
    redeemMaximum();
  }

  function withdrawToVault(uint256 amountUnderlying) external restricted updateSupplyInTheEnd {
    address _underlying = underlying();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (amountUnderlying <= balance) {
      IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
      return;
    }
    uint256 toRedeem = amountUnderlying.sub(balance);
    // get some of the underlying
    mustRedeemPartial(toRedeem);
    // transfer the amount requested (or the amount we have) back to vault()
    IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
    balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 0) {
      investAllUnderlying();
    }
  }

  /**
  * Withdraws all assets, liquidates XVS, and invests again in the required ratio.
  */
  function doHardWork() public restricted {
    claimRewards();
    liquidateRewards();
    investAllUnderlying();
  }

  /**
  * Redeems maximum that can be redeemed from Venus.
  * Redeem the minimum of the underlying we own, and the underlying that the vToken can
  * immediately retrieve. Ensures that `redeemMaximum` doesn't fail silently.
  *
  * DOES NOT ensure that the strategy vUnderlying balance becomes 0.
  */
  function redeemMaximum() internal {
    redeemMaximumWithLoan(
      collateralFactorNumerator(),
      factorDenominator()
    );
  }

  /**
  * Redeems `amountUnderlying` or fails.
  */
  function mustRedeemPartial(uint256 amountUnderlying) internal {
    address _underlying = underlying();
    uint256 balanceBefore = IERC20(_underlying).balanceOf(address(this));
    redeemPartialWithLoan(
      amountUnderlying,
      fold()? borrowTargetFactorNumerator():0,
      collateralFactorNumerator(),
      factorDenominator()
      );
    uint256 balanceAfter = IERC20(_underlying).balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= amountUnderlying, "Unable to withdraw the entire amountUnderlying");
  }

  /**
  * Salvages a token.
  */
  function salvage(address recipient, address token, uint256 amount) public onlyGovernance {
    // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IERC20(token).safeTransfer(recipient, amount);
  }

  function uniV3PairFee(address sellToken, address buyToken) public view returns(uint24 fee) {
    if(storedPairFee[sellToken][buyToken] != 0) {
      return storedPairFee[sellToken][buyToken];
    } else if(storedPairFee[buyToken][sellToken] != 0) {
      return storedPairFee[buyToken][sellToken];
    } else {
      return 500;
    }
  }

  function setPairFee(address token0, address token1, uint24 fee) public onlyGovernance {
    storedPairFee[token0][token1] = fee;
  }

  function _uniV3Swap(
    uint256 amountIn,
    uint256 minAmountOut,
    address[] memory pathWithoutFee
  ) internal {
    address currentSellToken = pathWithoutFee[0];

    IERC20(currentSellToken).safeIncreaseAllowance(uniV3Router, amountIn);

    bytes memory pathWithFee = abi.encodePacked(currentSellToken);
    for(uint256 i=1; i < pathWithoutFee.length; i++) {
      address currentBuyToken = pathWithoutFee[i];
      pathWithFee = abi.encodePacked(
        pathWithFee,
        uniV3PairFee(currentSellToken, currentBuyToken),
        currentBuyToken);
      currentSellToken = currentBuyToken;
    }

    IUniswapV3Router.ExactInputParams memory param = IUniswapV3Router.ExactInputParams({
      path: pathWithFee,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: amountIn,
      amountOutMinimum: minAmountOut
    });

    IUniswapV3Router(uniV3Router).exactInput(param);
  }

  function _approveIfNeed(address token, address spender, uint256 amount) internal {
    uint256 allowance = IERC20(token).allowance(address(this), spender);
    if (amount > allowance) {
      IERC20(token).safeApprove(spender, 0);
      IERC20(token).safeApprove(spender, amount);
    }
  }

  function _balancerSwap(
    address sellToken,
    address buyToken,
    bytes32 poolId,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal {
    IBVault.SingleSwap memory singleSwap;
    IBVault.SwapKind swapKind = IBVault.SwapKind.GIVEN_IN;

    singleSwap.poolId = poolId;
    singleSwap.kind = swapKind;
    singleSwap.assetIn = IAsset(sellToken);
    singleSwap.assetOut = IAsset(buyToken);
    singleSwap.amount = amountIn;
    singleSwap.userData = abi.encode(0);

    IBVault.FundManagement memory funds;
    funds.sender = address(this);
    funds.fromInternalBalance = false;
    funds.recipient = payable(address(this));
    funds.toInternalBalance = false;

    _approveIfNeed(sellToken, bVault, amountIn);
    IBVault(bVault).swap(singleSwap, funds, minAmountOut, block.timestamp);
  }

  function claimRewards() internal {

  }

  function liquidateRewards() internal {
    address _rewardToken = rewardToken();
    address _underlying = underlying();
    uint256 rewardBalanceBefore = 0;

    if (_underlying == _rewardToken) {
      rewardBalanceBefore = IERC20(_rewardToken).balanceOf(address(this));
    }

    for(uint256 i = 0; i < rewardTokens.length; i++){
      address token = rewardTokens[i];
      uint256 rewardBalance = IERC20(token).balanceOf(address(this));

      if(reward2WETH[token].length < 2 || rewardBalance == 0) {
        continue;
      }

      if(poolIds[token][weth] != bytes32(0)){
        _balancerSwap(token, weth, poolIds[token][weth], rewardBalance, 1);
      } else {
        _uniV3Swap(rewardBalance, 1, reward2WETH[token]);
      }
    }

    uint256 rewardBalanceAfter = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalanceAfter.sub(rewardBalanceBefore));
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    // no liquidation needed when underlying is reward token
    if (_underlying != _rewardToken) {
      _uniV3Swap(remainingRewardBalance, 1, WETH2underlying);
    }
  }

  /**
  * Returns the current balance.
  */
  function investedUnderlyingBalance() public view returns (uint256) {
    // underlying in this strategy + underlying redeemable from Radiant - debt
    return IERC20(underlying()).balanceOf(address(this))
    .add(suppliedInUnderlying)
    .sub(borrowedInUnderlying);
  }

  // updating collateral factor
  // note 1: one should settle the loan first before calling this
  // note 2: collateralFactorDenominator is 1000, therefore, for 20%, you need 200
  function _setCollateralFactorNumerator(uint256 _numerator) internal {
    require(_numerator <= uint(800).mul(factorDenominator()).div(1000), "Collateral factor cannot be this high");
    require(_numerator > borrowTargetFactorNumerator(), "Collateral factor should be higher than borrow target");
    setUint256(_COLLATERALFACTORNUMERATOR_SLOT, _numerator);
  }

  function collateralFactorNumerator() public view returns (uint256) {
    return getUint256(_COLLATERALFACTORNUMERATOR_SLOT);
  }

  function _setFactorDenominator(uint256 _denominator) internal {
    setUint256(_FACTORDENOMINATOR_SLOT, _denominator);
  }

  function factorDenominator() public view returns (uint256) {
    return getUint256(_FACTORDENOMINATOR_SLOT);
  }

  function setBorrowTargetFactorNumerator(uint256 _numerator) public onlyGovernance {
    require(_numerator < collateralFactorNumerator(), "Target should be lower than collateral limit");
    setUint256(_BORROWTARGETFACTORNUMERATOR_SLOT, _numerator);
  }

  function borrowTargetFactorNumerator() public view returns (uint256) {
    return getUint256(_BORROWTARGETFACTORNUMERATOR_SLOT);
  }

  function setFold (bool _fold) public onlyGovernance {
    setBoolean(_FOLD_SLOT, _fold);
  }

  function fold() public view returns (bool) {
    return getBoolean(_FOLD_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance updateSupplyInTheEnd {
    _finalizeUpgrade();
  }
}

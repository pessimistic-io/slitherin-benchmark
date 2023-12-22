//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IUniversalLiquidator.sol";
import "./IVault.sol";
import "./BaseUpgradeableStrategy.sol";
import "./IBVault.sol";
import "./Gauge.sol";
import "./IBalancerMinter.sol";
import "./IAuraBooster.sol";
import "./IAuraBaseRewardPool.sol";

contract AuraStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);
  address public constant bVault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
  address public constant booster = address(0x98Ef32edd24e2c92525E59afc4475C1242a30184);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _AURA_POOLID_SLOT = 0xbc10a276e435b4e9a9e92986f93a224a34b50c1898d7551c38ef30a08efadec4;
  bytes32 internal constant _BALANCER_POOLID_SLOT = 0xbf3f653715dd45c84a3367d2975f271307cb967d6ce603dc4f0def2ad909ca64;
  bytes32 internal constant _DEPOSIT_TOKEN_SLOT = 0x219270253dbc530471c88a9e7c321b36afda219583431e7b6c386d2d46e70c86;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() public BaseUpgradeableStrategy() {
    assert(_AURA_POOLID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.auraPoolId")) - 1));
    assert(_BALANCER_POOLID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.balancerPoolId")) - 1));
    assert(_DEPOSIT_TOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositToken")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    bytes32 _balancerPoolID,
    uint256 _auraPoolID,
    address _depositToken
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      weth,
      harvestMSIG
    );

    (address _lpt,) = IBVault(bVault).getPool(_balancerPoolID);
    require(_lpt == _underlying, "Underlying mismatch");
    (_lpt,,,,,) = IAuraBooster(booster).poolInfo(_auraPoolID);
    require(_lpt == underlying(), "Pool Info does not match underlying");

    _setAuraPoolId(_auraPoolID);
    _setBalancerPoolId(_balancerPoolID);
    _setDepositToken(_depositToken);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function _rewardPoolBalance() internal view returns (uint256 balance) {
      balance = IAuraBaseRewardPool(rewardPool()).balanceOf(address(this));
  }

  function _emergencyExitRewardPool() internal {
    uint256 stakedBalance = _rewardPoolBalance();
    if (stakedBalance != 0) {
        IAuraBaseRewardPool(rewardPool()).withdrawAllAndUnwrap(false); //don't claim rewards
    }
  }

  function _partialWithdrawalRewardPool(uint256 amount) internal {
    IAuraBaseRewardPool(rewardPool()).withdrawAndUnwrap(amount, false);  //don't claim rewards at this point
  }

  function _exitRewardPool() internal {
      uint256 stakedBalance = _rewardPoolBalance();
      if (stakedBalance != 0) {
          IAuraBaseRewardPool(rewardPool()).withdrawAllAndUnwrap(true);
      }
  }

  function _enterRewardPool() internal {
    address underlying_ = underlying();
    uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));
    IERC20(underlying_).safeApprove(booster, 0);
    IERC20(underlying_).safeApprove(booster, entireBalance);
    IAuraBooster(booster).depositAll(auraPoolId(), true); //deposit and stake
  }

  function _investAllUnderlying() internal onlyNotPausedInvesting {
    if(IERC20(underlying()).balanceOf(address(this)) > 0) {
      _enterRewardPool();
    }
  }

  /*
  *   In case there are some issues discovered about the pool or underlying asset
  *   Governance can exit the pool properly
  *   The function is only used for emergency to exit the pool
  */
  function emergencyExit() public onlyGovernance {
    _emergencyExitRewardPool();
    _setPausedInvesting(true);
  }

  /*
  *   Resumes the ability to invest into the underlying reward pools
  */
  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  function changeDepositToken(address _depositToken) public onlyGovernance {
    _setDepositToken(_depositToken);
  }

  function _approveIfNeed(address token, address spender, uint256 amount) internal {
    uint256 allowance = IERC20(token).allowance(address(this), spender);
    if (amount > allowance) {
      IERC20(token).safeApprove(spender, 0);
      IERC20(token).safeApprove(spender, amount);
    }
  }

  function _balancerDeposit(
    address tokenIn,
    bytes32 poolId,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal {
    (address[] memory poolTokens,,) = IBVault(bVault).getPoolTokens(poolId);
    uint256 _nTokens = poolTokens.length;

    IAsset[] memory assets = new IAsset[](_nTokens);
    uint256[] memory amountsIn = new uint256[](_nTokens);
    for (uint256 i = 0; i < _nTokens; i++) {
      assets[i] = IAsset(poolTokens[i]);
      amountsIn[i] = poolTokens[i] == tokenIn ? amountIn : 0;
    }

    IBVault.JoinKind joinKind = IBVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT;

    bytes memory userData = abi.encode(joinKind, amountsIn, minAmountOut);

    IBVault.JoinPoolRequest memory request;
    request.assets = assets;
    request.maxAmountsIn = amountsIn;
    request.userData = userData;
    request.fromInternalBalance = false;

    _approveIfNeed(tokenIn, bVault, amountIn);
    IBVault(bVault).joinPool(
      poolId,
      address(this),
      address(this),
      request
    );
  }

  function _liquidateReward() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }
    address _rewardToken = rewardToken();
    address _universalLiquidator = universalLiquidator();
    for(uint256 i = 0; i < rewardTokens.length; i++){
      address token = rewardTokens[i];
      uint256 rewardBalance = IERC20(token).balanceOf(address(this));
      if (rewardBalance == 0) {
        continue;
      }
      if (token != _rewardToken){
          IERC20(token).safeApprove(_universalLiquidator, 0);
          IERC20(token).safeApprove(_universalLiquidator, rewardBalance);
          IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, rewardBalance, 1, address(this));
      }
    }

    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    address _depositToken = depositToken();
    if (_depositToken != _rewardToken) {
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, remainingRewardBalance);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, _depositToken, remainingRewardBalance, 1, address(this));
    }

    uint256 tokenBalance = IERC20(_depositToken).balanceOf(address(this));
    if (tokenBalance > 0 && !(_depositToken == underlying())) {
      depositLP();
    }
  }

  function depositLP() internal {
    address _depositToken = depositToken();
    uint256 depositTokenBalance = IERC20(_depositToken).balanceOf(address(this));

    _balancerDeposit(
      _depositToken,
      balancerPoolId(),
      depositTokenBalance,
      1
    );
  }

  /** Withdraws all the asset to the vault
   */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    _exitRewardPool();
    _liquidateReward();
    IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
  }

  /** Withdraws specific amount of asset to the vault
   */
  function withdrawToVault(uint256 amount) public restricted {
    address _underlying = underlying();
    // Typically there wouldn't be any amount here
    // however, it is possible because of the emergencyExit
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));

    if(amount > entireBalance){
      // While we have the check above, we still using SafeMath below
      // for the peace of mind (in case something gets changed in between)
      uint256 needToWithdraw = amount.sub(entireBalance);
      uint256 toWithdraw = Math.min(_rewardPoolBalance(), needToWithdraw);
      _partialWithdrawalRewardPool(toWithdraw);
    }
    IERC20(_underlying).safeTransfer(vault(), amount);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    // Adding the amount locked in the reward pool and the amount that is somehow in this contract
    // both are in the units of "underlying"
    // The second part is needed because there is the emergency exit mechanism
    // which would break the assumption that all the funds are always inside of the reward pool
    return _rewardPoolBalance().add(IERC20(underlying()).balanceOf(address(this)));
  }

  /*
  *   Governance or Controller can claim coins that are somehow transferred into the contract
  *   Note that they cannot come in take away coins that are used and defined in the strategy itself
  */
  function salvage(address recipient, address token, uint256 amount) external onlyControllerOrGovernance {
     // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IERC20(token).safeTransfer(recipient, amount);
  }

  /*
  *   Get the reward, sell it in exchange for underlying, invest what you got.
  *   It's not much, but it's honest work.
  *
  *   Note that although `onlyNotPausedInvesting` is not added here,
  *   calling `investAllUnderlying()` affectively blocks the usage of `doHardWork`
  *   when the investing is being paused by governance.
  */
  function doHardWork() external onlyNotPausedInvesting restricted {
    IAuraBaseRewardPool(rewardPool()).getReward();
    _liquidateReward();
    _investAllUnderlying();
  }

  /**
  * Can completely disable claiming UNI rewards and selling. Good for emergency withdraw in the
  * simplest possible way.
  */
  function setSell(bool s) public onlyGovernance {
    _setSell(s);
  }

  /**
  * Sets the minimum amount of CRV needed to trigger a sale.
  */
  function setSellFloor(uint256 floor) public onlyGovernance {
    _setSellFloor(floor);
  }

  /** Aura deposit pool ID
   */
  function _setAuraPoolId(uint256 _value) internal {
    setUint256(_AURA_POOLID_SLOT, _value);
  }

  /** Balancer deposit pool ID
   */
  function _setBalancerPoolId(bytes32 _value) internal {
    setBytes32(_BALANCER_POOLID_SLOT, _value);
  }

  function auraPoolId() public view returns (uint256) {
    return getUint256(_AURA_POOLID_SLOT);
  }

  function balancerPoolId() public view returns (bytes32) {
    return getBytes32(_BALANCER_POOLID_SLOT);
  }

  function _setDepositToken(address _address) internal {
    setAddress(_DEPOSIT_TOKEN_SLOT, _address);
  }

  function depositToken() public view returns (address) {
    return getAddress(_DEPOSIT_TOKEN_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {} // this is needed for the receiving Matic
}


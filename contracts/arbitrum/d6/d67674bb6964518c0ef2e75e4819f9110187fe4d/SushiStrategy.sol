//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IVault.sol";
import "./BaseUpgradeableStrategy.sol";
import "./ICamelotRouter.sol";
import "./ILizardRouter.sol";
import "./IMiniChefV2.sol";

contract SushiStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant sushiRouter = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _POOLID_SLOT = 0x3fd729bfa2e28b7806b03a6e014729f59477b530f995be4d51defc9dad94810b;

  // this would be reset on each upgrade
  mapping(address => address[]) public WETH2deposit;
  mapping(address => address[]) public reward2WETH;
  address[] public rewardTokens;

  constructor() public BaseUpgradeableStrategy() {
    assert(_POOLID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.poolId")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    uint256 _poolID
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      weth,
      harvestMSIG
    );

    address _lpt = IMiniChefV2(rewardPool()).lpToken(_poolID);
    require(_lpt == _underlying, "Underlying mismatch");

    _setPoolId(_poolID);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function _rewardPoolBalance() internal view returns (uint256 balance) {
    (balance,) = IMiniChefV2(rewardPool()).userInfo(poolId(), address(this));
  }

  function _emergencyExitRewardPool() internal {
    uint256 stakedBalance = _rewardPoolBalance();
    if (stakedBalance != 0) {
        _withdrawUnderlyingFromPool(stakedBalance);
    }
  }

  function _withdrawUnderlyingFromPool(uint256 amount) internal {
    if (amount > 0) {
      IMiniChefV2(rewardPool()).withdraw(poolId(), amount, address(this));
    }
  }

  function _enterRewardPool() internal {
    address underlying_ = underlying();
    address rewardPool_ = rewardPool();
    uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));
    IERC20(underlying_).safeApprove(rewardPool_, 0);
    IERC20(underlying_).safeApprove(rewardPool_, entireBalance);
    IMiniChefV2(rewardPool_).deposit(poolId(), entireBalance, address(this));
  }

  function _investAllUnderlying() internal onlyNotPausedInvesting {
    // this check is needed, because most of the SNX reward pools will revert if
    // you try to stake(0).
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

  function setDepositLiquidationPath(address [] memory _route) public onlyGovernance {
    address _underlying = underlying();
    address token0 = IUniswapV2Pair(_underlying).token0();
    address token1 = IUniswapV2Pair(_underlying).token1();
    require(_route[0] == weth, "Path should start with WETH");
    require(_route[_route.length-1] == token0 || _route[_route.length-1] == token1, "Path should end with a token in the underlying LP");
    WETH2deposit[_route[_route.length-1]] = _route;
  }

  function setRewardLiquidationPath(address [] memory _route) public onlyGovernance {
    require(_route[_route.length-1] == weth, "Path should end with WETH");
    bool isReward = false;
    for(uint256 i = 0; i < rewardTokens.length; i++){
      if (_route[0] == rewardTokens[i]) {
        isReward = true;
      }
    }
    require(isReward, "Path should start with a rewardToken");
    reward2WETH[_route[0]] = _route;
  }

  function addRewardToken(address _token, address[] memory _path2WETH) public onlyGovernance {
    rewardTokens.push(_token);
    setRewardLiquidationPath(_path2WETH);
  }

  function _liquidateReward() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }

    for(uint256 i = 0; i < rewardTokens.length; i++){
      address token = rewardTokens[i];
      uint256 rewardBalance = IERC20(token).balanceOf(address(this));

      if (rewardBalance == 0) {
        continue;
      }
      if (reward2WETH[token].length < 2) {
        continue;
      }
      IERC20(token).safeApprove(sushiRouter, 0);
      IERC20(token).safeApprove(sushiRouter, rewardBalance);
      IUniswapV2Router02(sushiRouter).swapExactTokensForTokens(
      rewardBalance, 1, reward2WETH[token], address(this), block.timestamp);
    }

    address _rewardToken = rewardToken();
    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    address _underlying = underlying();
    address token0 = IUniswapV2Pair(_underlying).token0();
    address token1 = IUniswapV2Pair(_underlying).token1();

    uint256 toToken0 = remainingRewardBalance.div(2);
    uint256 toToken1 = remainingRewardBalance.sub(toToken0);

    IERC20(_rewardToken).safeApprove(sushiRouter, 0);
    IERC20(_rewardToken).safeApprove(sushiRouter, remainingRewardBalance);

    uint256 token0Amount;
    if (WETH2deposit[token0].length > 0) {
      IUniswapV2Router02(sushiRouter).swapExactTokensForTokens(
      toToken0, 1, WETH2deposit[token0], address(this), block.timestamp);
      token0Amount = IERC20(token0).balanceOf(address(this));
    } else {
      // otherwise we assme token0 is weth itself
      token0Amount = toToken0;
    }

    uint256 token1Amount;
    if (WETH2deposit[token1].length > 0) {
      IUniswapV2Router02(sushiRouter).swapExactTokensForTokens(
      toToken1, 1, WETH2deposit[token1], address(this), block.timestamp);
      token1Amount = IERC20(token1).balanceOf(address(this));
    } else {
      token1Amount = toToken1;
    }

    // provide token1 and token2 to Lizard
    IERC20(token0).safeApprove(sushiRouter, 0);
    IERC20(token0).safeApprove(sushiRouter, token0Amount);

    IERC20(token1).safeApprove(sushiRouter, 0);
    IERC20(token1).safeApprove(sushiRouter, token1Amount);

    IUniswapV2Router02(sushiRouter).addLiquidity(
      token0,
      token1,
      token0Amount,
      token1Amount,
      1,
      1,
      address(this),
      block.timestamp
    );
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawAllToVault() public restricted {
    _withdrawUnderlyingFromPool(_rewardPoolBalance());
    IMiniChefV2(rewardPool()).harvest(poolId(), address(this));
    _liquidateReward();
    address underlying_ = underlying();
    IERC20(underlying_).safeTransfer(vault(), IERC20(underlying_).balanceOf(address(this)));
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawToVault(uint256 _amount) public restricted {
    // Typically there wouldn't be any amount here
    // however, it is possible because of the emergencyExit
    address underlying_ = underlying();
    uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));

    if(_amount > entireBalance){
      // While we have the check above, we still using SafeMath below
      // for the peace of mind (in case something gets changed in between)
      uint256 needToWithdraw = _amount.sub(entireBalance);
      uint256 toWithdraw = Math.min(_rewardPoolBalance(), needToWithdraw);
      _withdrawUnderlyingFromPool(toWithdraw);
    }
    IERC20(underlying_).safeTransfer(vault(), _amount);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    if (rewardPool() == address(0)) {
      return IERC20(underlying()).balanceOf(address(this));
    }
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
    IMiniChefV2(rewardPool()).harvest(poolId(), address(this));
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

  // masterchef rewards pool ID
  function _setPoolId(uint256 _value) internal {
    setUint256(_POOLID_SLOT, _value);
  }

  function poolId() public view returns (uint256) {
    return getUint256(_POOLID_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }
}


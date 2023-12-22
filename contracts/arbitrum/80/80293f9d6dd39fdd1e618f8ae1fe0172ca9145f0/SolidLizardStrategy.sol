//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IVault.sol";
import "./BaseUpgradeableStrategy.sol";
import "./ILizardRouter.sol";
import "./IGauge.sol";
import "./ILizardPair.sol";

contract SolidLizardStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant lizardRouter = address(0xF26515D5482e2C2FD237149bF6A653dA4794b3D0);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // this would be reset on each upgrade
  address[] public rewardTokens;
  mapping(address => ILizardRouter.Route[]) public reward2WETH;
  mapping(address => ILizardRouter.Route[]) public lpLiquidationPath;

  
  constructor() public BaseUpgradeableStrategy() {}

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      weth,
      harvestMSIG
    );
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function _rewardPoolBalance() internal view returns (uint256 balance) {
      balance = IGauge(rewardPool()).balanceOf(address(this));
  }

  function _emergencyExitRewardPool() internal {
    uint256 stakedBalance = _rewardPoolBalance();
    if (stakedBalance != 0) {
        _withdrawUnderlyingFromPool(stakedBalance);
    }
  }

  function _withdrawUnderlyingFromPool(uint256 amount) internal {
    address rewardPool_ = rewardPool();
    IGauge(rewardPool_).withdraw(
      Math.min(IGauge(rewardPool_).balanceOf(address(this)), amount)
    );
  }

  function _enterRewardPool() internal {
    address underlying_ = underlying();
    address rewardPool_ = rewardPool();
    uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));
    IERC20(underlying_).safeApprove(rewardPool_, 0);
    IERC20(underlying_).safeApprove(rewardPool_, entireBalance);
    IGauge(rewardPool_).deposit(entireBalance, 0);
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

  function setRewardLiquidationPath(address _token, ILizardRouter.Route[] memory _route) public onlyGovernance {
    require(_route[_route.length-1].to == weth, "Path should end with WETH");
    require(_route[0].from == _token, "Path should start with rewardToken");

    delete reward2WETH[_token];
    for(uint256 i = 0; i < _route.length; i++) {
      reward2WETH[_token].push(_route[i]);
    }
  }

  function setLpLiquidationPath(address _token, ILizardRouter.Route[] memory _route) public onlyGovernance {
    require(_route[_route.length-1].to == _token, "Path should end with lp token");
    require(_route[0].from == weth, "Path should start with WETH");

    delete lpLiquidationPath[_token];
    for(uint256 i = 0; i < _route.length; i++) {
      lpLiquidationPath[_token].push(_route[i]);
    }
  }

  function addRewardToken(address _token, ILizardRouter.Route[] memory _path2WETH) public onlyGovernance {
    rewardTokens.push(_token);
    setRewardLiquidationPath(_token, _path2WETH);
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
      if (reward2WETH[token].length == 0) {
        continue;
      }

      IERC20(token).safeApprove(lizardRouter, 0);
      IERC20(token).safeApprove(lizardRouter, rewardBalance);
  
      ILizardRouter(lizardRouter).swapExactTokensForTokens(
        rewardBalance,
        1,
        reward2WETH[token],
        address(this),
        block.timestamp
      );
    }

    address _rewardToken = rewardToken();
    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    address _underlying = underlying();

    address token0 = ILizardPair(_underlying).token0();
    address token1 = ILizardPair(_underlying).token1();

    uint256 toToken0 = remainingRewardBalance.div(2);
    uint256 toToken1 = remainingRewardBalance.sub(toToken0);

    IERC20(_rewardToken).safeApprove(lizardRouter, 0);
    IERC20(_rewardToken).safeApprove(lizardRouter, remainingRewardBalance);

    uint256 token0Amount;
    if (lpLiquidationPath[token0].length > 0) {
      ILizardRouter(lizardRouter).swapExactTokensForTokens(
        toToken0,
        1,
        lpLiquidationPath[token0],
        address(this),
        block.timestamp
      );
      token0Amount = IERC20(token0).balanceOf(address(this));
    } else {
      // otherwise we assme token0 is weth itself
      token0Amount = toToken0;
    }

    uint256 token1Amount;
    if (lpLiquidationPath[token1].length > 0) {
      ILizardRouter(lizardRouter).swapExactTokensForTokens(
        toToken1,
        1,
        lpLiquidationPath[token1],
        address(this),
        block.timestamp
      );
      token1Amount = IERC20(token1).balanceOf(address(this));
    } else {
      token1Amount = toToken1;
    }

    // provide token1 and token2 to Lizard
    IERC20(token0).safeApprove(lizardRouter, 0);
    IERC20(token0).safeApprove(lizardRouter, token0Amount);

    IERC20(token1).safeApprove(lizardRouter, 0);
    IERC20(token1).safeApprove(lizardRouter, token1Amount);

    ILizardRouter(lizardRouter).addLiquidity(
      token0,
      token1,
      ILizardPair(_underlying).stable(), 
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
    IGauge(rewardPool()).getReward(address(this), rewardTokens);
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

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {} // this is needed for the receiving Matic
}


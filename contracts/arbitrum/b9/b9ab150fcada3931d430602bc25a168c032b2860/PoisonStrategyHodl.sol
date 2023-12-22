//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV3Router.sol";
import "./IVault.sol";
import "./PotPool.sol";
import "./BaseUpgradeableStrategy.sol";
import "./IMasterChef.sol";
import "./IiPoison.sol";

contract PoisonStrategyHodl is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant poison = address(0x31C91D8Fb96BfF40955DD2dbc909B36E8b104Dde);
  address public constant sushiRouter = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
  address public constant uniV3Router = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _POOLID_SLOT = 0x3fd729bfa2e28b7806b03a6e014729f59477b530f995be4d51defc9dad94810b;
  bytes32 internal constant _HODLVAULT_SLOT = 0xc26d330f887c749cb38ae7c37873ff08ac4bba7aec9113c82d48a0cf6cc145f2;
  bytes32 internal constant _POTPOOL_SLOT = 0x7f4b50847e7d7a4da6a6ea36bfb188c77e9f093697337eb9a876744f926dd014;
  bytes32 internal constant _HODLTOKEN_SLOT = 0x3ed76c1ddd44f6251c0d268c9f5a0af4a2227e90ab146d70e6b186ad3fc7e183;


  // this would be reset on each upgrade
  mapping(address => address[]) public WETH2deposit;
  mapping(address => address[]) public reward2WETH;
  mapping (address => mapping(address => uint24)) public storedPairFee;

  constructor() public BaseUpgradeableStrategy() {
    assert(_POOLID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.poolId")) - 1));
    assert(_HODLVAULT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.hodlVault")) - 1));
    assert(_POTPOOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.potPool")) - 1));
    assert(_HODLTOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.hodlToken")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    uint256 _poolId,
    address _hodlToken,
    address _hodlVault,
    address _potPool
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      weth,
      harvestMSIG
    );

    (address _lpt,,,) = IMasterChef(_rewardPool).poolInfo(_poolId);
    require(_lpt == _underlying, "Underlying mismatch");

    _setPoolId(_poolId);
    setAddress(_HODLVAULT_SLOT, _hodlVault);
    setAddress(_POTPOOL_SLOT, _potPool);
    setHodlToken(_hodlToken);
  }

  /*///////////////////////////////////////////////////////////////
                  STORAGE SETTER AND GETTER
  //////////////////////////////////////////////////////////////*/

  function setHodlVault(address _value) public onlyGovernance {
    require(hodlVault() == address(0), "Hodl vault already set");
    setAddress(_HODLVAULT_SLOT, _value);
  }

  function hodlVault() public view returns (address) {
    return getAddress(_HODLVAULT_SLOT);
  }

  function setPotPool(address _value) public onlyGovernance {
    require(potPool() == address(0), "PotPool already set");
    setAddress(_POTPOOL_SLOT, _value);
  }

  function potPool() public view returns (address) {
    return getAddress(_POTPOOL_SLOT);
  }

  function setHodlToken(address _value) internal {
    setAddress(_HODLTOKEN_SLOT, _value);
  }

  function hodlToken() public view returns (address) {
    return getAddress(_HODLTOKEN_SLOT);
  }

  function setSell(bool s) public onlyGovernance {
    _setSell(s);
  }

  // masterchef rewards pool ID
  function _setPoolId(uint256 _value) internal {
    setUint256(_POOLID_SLOT, _value);
  }

  function poolId() public view returns (uint256) {
    return getUint256(_POOLID_SLOT);
  }

  function setDepositLiquidationPath(address [] memory _route) public onlyGovernance {
    require(_route[_route.length-1] == poison, "Path should end with Poison token");
    require(_route[0] == weth, "Path should start with WETH");
    WETH2deposit[_route[_route.length-1]] = _route;
  }

  function setRewardLiquidationPath(address [] memory _route) public onlyGovernance {
    require(_route[_route.length-1] == weth, "Path should end with WETH");
    require(_route[0] == poison, "Path should start with Poison token");
    reward2WETH[_route[0]] = _route;
  }

  function setPairFee(address token0, address token1, uint24 fee) public onlyGovernance {
    storedPairFee[token0][token1] = fee;
  }

  /*///////////////////////////////////////////////////////////////
                  PROXY - FINALIZE UPGRADE
  //////////////////////////////////////////////////////////////*/

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  /*///////////////////////////////////////////////////////////////
                  INTERNAL HELPER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function _rewardPoolBalance() internal view returns (uint256 balance) {
    (balance, ) = IMasterChef(rewardPool()).userInfo(poolId(), address(this));
  }

  function _emergencyExitRewardPool() internal {
    IMasterChef(rewardPool()).emergencyWithdraw(poolId());
  }

  function _withdrawUnderlyingFromPool(uint256 amount) internal {
    IMasterChef(rewardPool()).withdraw(poolId(), amount);
  }

  function _enterRewardPool() internal {
    address underlying_ = underlying();
    address rewardPool_ = rewardPool();
    uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));
    IERC20(underlying_).safeApprove(rewardPool_, 0);
    IERC20(underlying_).safeApprove(rewardPool_, entireBalance);
    IMasterChef(rewardPool_).deposit(poolId(), entireBalance);
  }

  function _investAllUnderlying() internal onlyNotPausedInvesting {
    // this check is needed, because most of the SNX reward pools will revert if
    // you try to stake(0).
    if(IERC20(underlying()).balanceOf(address(this)) > 0) {
      _enterRewardPool();
    }
  }
  
  function uniV3PairFee(address sellToken, address buyToken) public view returns(uint24 fee) {
    if(storedPairFee[sellToken][buyToken] != 0) {
      return storedPairFee[sellToken][buyToken];
    } else if(storedPairFee[buyToken][sellToken] != 0) {
      return storedPairFee[buyToken][sellToken];
    } else {
      return 3000;
    }
  }

  function uniV3Swap(
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

  // We Hodl all the rewards
  function _hodlAndNotify() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }

    uint256 poisonBalance = IERC20(poison).balanceOf(address(this));
    if (poisonBalance == 0) {
      return;
    }

    uniV3Swap(poisonBalance, 1, reward2WETH[poison]);

    address _rewardToken = rewardToken();
    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    uniV3Swap(remainingRewardBalance, 1, WETH2deposit[poison]);
    poisonBalance = IERC20(poison).balanceOf(address(this));
    if (poisonBalance > 0) {
      address _hodlToken = hodlToken();
      IERC20(poison).safeApprove(_hodlToken, 0);
      IERC20(poison).safeApprove(_hodlToken, poisonBalance);
      IiPoison(_hodlToken).depositPoison(poisonBalance);
    }

    address _hodlVault = hodlVault();
    address _hodlToken = hodlToken();
    address _potPool = potPool();
    uint256 hodlBalance = IERC20(_hodlToken).balanceOf(address(this));

    IERC20(_hodlToken).safeApprove(_hodlVault, 0);
    IERC20(_hodlToken).safeApprove(_hodlVault, hodlBalance);

    IVault(_hodlVault).deposit(hodlBalance);

    uint256 fRewardBalance = IERC20(_hodlVault).balanceOf(address(this));
    IERC20(_hodlVault).safeTransfer(_potPool, fRewardBalance);

    PotPool(_potPool).notifyTargetRewardAmount(_hodlVault, fRewardBalance);
  }

  /*///////////////////////////////////////////////////////////////
                  PUBLIC EMERGENCY FUNCTIONS
  //////////////////////////////////////////////////////////////*/

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

  /*///////////////////////////////////////////////////////////////
                  ISTRATEGY FUNCTION IMPLEMENTATIONS
  //////////////////////////////////////////////////////////////*/

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawAllToVault() public restricted {
    _withdrawUnderlyingFromPool(_rewardPoolBalance());
    _hodlAndNotify();
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

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
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
    IMasterChef(rewardPool()).deposit(poolId(), 0);
    _hodlAndNotify();
    _investAllUnderlying();
  }
  
  function depositArbCheck() public pure returns(bool) {
    return true;
  }
}


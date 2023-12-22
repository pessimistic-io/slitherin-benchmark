//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IVault.sol";
import "./BaseUpgradeableStrategy.sol";
import "./ICamelotRouter.sol";
import "./ILizardRouter.sol";
import "./IBVault.sol";
import "./Gauge.sol";
import "./IBalancerMinter.sol";

contract BalancerStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant camelotRouter = address(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
  address public constant lizardRouter = address(0xF26515D5482e2C2FD237149bF6A653dA4794b3D0);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _POOLID_SLOT = 0x3fd729bfa2e28b7806b03a6e014729f59477b530f995be4d51defc9dad94810b;
  bytes32 internal constant _BVAULT_SLOT = 0x85cbd475ba105ca98d9a2db62dcf7cf3c0074b36303ef64160d68a3e0fdd3c67;
  bytes32 internal constant _DEPOSIT_TOKEN_SLOT = 0x219270253dbc530471c88a9e7c321b36afda219583431e7b6c386d2d46e70c86;
  bytes32 internal constant _BOOSTED_POOL = 0xd816e748a078d825fa9cc9dc9335909f9baa20dc1b5619211972fc7e672bd2fb;

  // this would be reset on each upgrade
  address[] public WETH2deposit;
  mapping(address => address[]) public reward2WETH;
  mapping(address => mapping(address => bytes32)) public poolIds;
  mapping(address => mapping(address => address)) public router;
  address[] public rewardTokens;
  mapping(address => mapping(address => bool)) public deposit;

  constructor() public BaseUpgradeableStrategy() {
    assert(_POOLID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.poolId")) - 1));
    assert(_BVAULT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.bVault")) - 1));
    assert(_DEPOSIT_TOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositToken")) - 1));
    assert(_BOOSTED_POOL == bytes32(uint256(keccak256("eip1967.strategyStorage.boostedPool")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    address _bVault,
    bytes32 _poolID,
    address _depositToken,
    bool _boosted
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      weth,
      harvestMSIG
    );

    (address _lpt,) = IBVault(_bVault).getPool(_poolID);
    require(_lpt == _underlying, "Underlying mismatch");

    _setPoolId(_poolID);
    _setBVault(_bVault);
    _setDepositToken(_depositToken);
    _setBoostedPool(_boosted);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function _rewardPoolBalance() internal view returns (uint256 balance) {
      balance = Gauge(rewardPool()).balanceOf(address(this));
  }

  function _emergencyExitRewardPool() internal {
    uint256 stakedBalance = _rewardPoolBalance();
    if (stakedBalance != 0) {
        _withdrawUnderlyingFromPool(stakedBalance);
    }
  }

  function _withdrawUnderlyingFromPool(uint256 amount) internal {
    address rewardPool_ = rewardPool();
    Gauge(rewardPool_).withdraw(
      Math.min(Gauge(rewardPool_).balanceOf(address(this)), amount)
    );
  }

  function _enterRewardPool() internal {
    address underlying_ = underlying();
    address rewardPool_ = rewardPool();
    uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));
    IERC20(underlying_).safeApprove(rewardPool_, 0);
    IERC20(underlying_).safeApprove(rewardPool_, entireBalance);
    Gauge(rewardPool_).deposit(entireBalance);
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
    require(_route[0] == weth, "Path should start with WETH");
    require(_route[_route.length-1] == depositToken(), "Path should end with depositToken");
    WETH2deposit = _route;
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

  function changeDepositToken(address _depositToken, address[] memory _liquidationPath) public onlyGovernance {
    _setDepositToken(_depositToken);
    setDepositLiquidationPath(_liquidationPath);
  }

  function setBalancerSwapPoolId(address _sellToken, address _buyToken, bytes32 _poolId) public onlyGovernance {
    poolIds[_sellToken][_buyToken] = _poolId;
  }

  function _approveIfNeed(address token, address spender, uint256 amount) internal {
    uint256 allowance = IERC20(token).allowance(address(this), spender);
    if (amount > allowance) {
      IERC20(token).safeApprove(spender, 0);
      IERC20(token).safeApprove(spender, amount);
    }
  }

  function _camelotSwap(
    address sellToken,
    address buyToken,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal {
    address[] memory path = new address[](2);
    path[0] = sellToken;
    path[1] = buyToken;
    IERC20(sellToken).safeApprove(camelotRouter, 0);
    IERC20(sellToken).safeApprove(camelotRouter, amountIn);
    ICamelotRouter(camelotRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
      amountIn, minAmountOut, path, address(this), harvestMSIG, block.timestamp
    );
  }

  function _lizardSwap(
    address sellToken,
    address buyToken,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal {
    IERC20(sellToken).safeApprove(lizardRouter, 0);
    IERC20(sellToken).safeApprove(lizardRouter, amountIn);
    ILizardRouter(lizardRouter).swapExactTokensForTokensSimple(
      amountIn, minAmountOut, sellToken, buyToken, false, address(this), block.timestamp
    );
  }

  function _balancerSwap(
    address sellToken,
    address buyToken,
    bytes32 poolId,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal {
    address _bVault = bVault();
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

    _approveIfNeed(sellToken, _bVault, amountIn);
    IBVault(_bVault).swap(singleSwap, funds, minAmountOut, block.timestamp);
  }

  function _balancerDeposit(
    address tokenIn,
    bytes32 poolId,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal {
    address _bVault = bVault();
    (address[] memory poolTokens,,) = IBVault(_bVault).getPoolTokens(poolId);
    uint256 _nTokens = poolTokens.length;

    IAsset[] memory assets = new IAsset[](_nTokens);
    for (uint256 i = 0; i < _nTokens; i++) {
      assets[i] = IAsset(poolTokens[i]);
    }

    IBVault.JoinKind joinKind = IBVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT;

    uint256[] memory amountsIn = new uint256[](_nTokens);
    for (uint256 j = 0; j < amountsIn.length; j++) {
      amountsIn[j] = address(assets[j]) == tokenIn ? amountIn : 0;
    }

    bytes memory userData = abi.encode(joinKind, amountsIn, minAmountOut);

    IBVault.JoinPoolRequest memory request;
    request.assets = assets;
    request.maxAmountsIn = amountsIn;
    request.userData = userData;
    request.fromInternalBalance = false;

    _approveIfNeed(tokenIn, _bVault, amountIn);
    IBVault(_bVault).joinPool(
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

    for(uint256 i = 0; i < rewardTokens.length; i++){
      address token = rewardTokens[i];
      uint256 rewardBalance = IERC20(token).balanceOf(address(this));

      if (rewardBalance == 0) {
        continue;
      }
      if (reward2WETH[token].length < 2) {
        continue;
      }
      for (uint256 j = 0; j < reward2WETH[token].length - 1; j++) {
        address sellToken = reward2WETH[token][j];
        address buyToken = reward2WETH[token][j+1];
        uint256 sellTokenBalance = IERC20(sellToken).balanceOf(address(this));
        if (poolIds[sellToken][buyToken] == bytes32(0)) {
          if (router[sellToken][buyToken] == lizardRouter) {
            _lizardSwap(sellToken, buyToken, sellTokenBalance, 1);
          } else if (router[sellToken][buyToken] == camelotRouter) {
            _camelotSwap(sellToken, buyToken, sellTokenBalance, 1);
          }
        } else {
          if (deposit[sellToken][buyToken]) {
            _balancerDeposit(
              sellToken,
              poolIds[sellToken][buyToken],
              sellTokenBalance,
              1
            );
          } else {
            _balancerSwap(
              sellToken,
              buyToken,
              poolIds[sellToken][buyToken],
              sellTokenBalance,
              1
            );
          }
        }
      }
    }

    address _rewardToken = rewardToken();
    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    if (WETH2deposit.length > 1) { //else we assume WETH is the deposit token, no need to swap
      for(uint256 i = 0; i < WETH2deposit.length - 1; i++){
        address sellToken = WETH2deposit[i];
        address buyToken = WETH2deposit[i+1];
        uint256 sellTokenBalance = IERC20(sellToken).balanceOf(address(this));
        if (poolIds[sellToken][buyToken] == bytes32(0)) {
          if (router[sellToken][buyToken] == lizardRouter) {
            _lizardSwap(sellToken, buyToken, sellTokenBalance, 1);
          } else if (router[sellToken][buyToken] == camelotRouter) {
            _camelotSwap(sellToken, buyToken, sellTokenBalance, 1);
          }
        } else {
          if (deposit[sellToken][buyToken]) {
            _balancerDeposit(
              sellToken,
              poolIds[sellToken][buyToken],
              sellTokenBalance,
              1
            );
          } else {
            _balancerSwap(
              sellToken,
              buyToken,
              poolIds[sellToken][buyToken],
              sellTokenBalance,
              1
            );
          }
        }
      }
    }

    address _depositToken = depositToken();
    uint256 tokenBalance = IERC20(depositToken()).balanceOf(address(this));
    if (tokenBalance > 0 && !(_depositToken == underlying())) {
      depositLP();
    }
  }

  function depositLP() internal {
    address _depositToken = depositToken();
    bytes32 _poolId = poolId();
    uint256 depositTokenBalance = IERC20(_depositToken).balanceOf(address(this));

    if (boostedPool()) {
      _balancerSwap(
        _depositToken,
        underlying(),
        _poolId,
        depositTokenBalance,
        1
      );
    } else {
      _balancerDeposit(
        _depositToken,
        _poolId,
        depositTokenBalance,
        1
      );
    }
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
    address _rewardPool = rewardPool();
    IBalancerMinter(Gauge(_rewardPool).bal_pseudo_minter()).mint(_rewardPool);
    Gauge(_rewardPool).claim_rewards();
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
  function _setPoolId(bytes32 _value) internal {
    setBytes32(_POOLID_SLOT, _value);
  }

  function poolId() public view returns (bytes32) {
    return getBytes32(_POOLID_SLOT);
  }

  function _setBVault(address _address) internal {
    setAddress(_BVAULT_SLOT, _address);
  }

  function bVault() public view returns (address) {
    return getAddress(_BVAULT_SLOT);
  }

  function _setDepositToken(address _address) internal {
    setAddress(_DEPOSIT_TOKEN_SLOT, _address);
  }

  function depositToken() public view returns (address) {
    return getAddress(_DEPOSIT_TOKEN_SLOT);
  }

  function _setBoostedPool(bool _boosted) internal {
    setBoolean(_BOOSTED_POOL, _boosted);
  }

  function boostedPool() public view returns (bool) {
    return getBoolean(_BOOSTED_POOL);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {} // this is needed for the receiving Matic
}


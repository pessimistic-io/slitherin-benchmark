// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IWETH.sol";
import "./IAutoOreo.sol";
import "./IRouteOracle.sol";

/**
 * @title Auto Compound Strategy
 * @notice handles deposits and withdraws on the underlying farm and auto-compound rewards
 * @author OreoSwap
 */
abstract contract AutoCompoundVault is ERC20, ReentrancyGuard, Pausable {
  using SafeERC20 for IERC20;

  IAutoOreo public immutable autoOreo; // address of the AutoOreo staking contract
  address public immutable masterChef; // address of the farm staking contract
  uint256 public immutable pid; // pid of pool in the farm staking contract
  IERC20 public immutable stakeToken; // token staked on the underlying farm
  IERC20 public immutable earnToken; // reward token paid by the underlying farm
  address[] public extraEarnTokens; // some underlying farms can give rewards in multiple tokens
  address immutable WNATIVE; // address of the network's wrapped native currency

  IRouteOracle public immutable routeOracle;

  bool public emergencyWithdrawn;

  uint256 public performanceFee = 300;

  uint256 constant MAX_PERFORMANCE_FEE = 500;

  mapping(address => uint256) public userAmountOnPoolAction;

  event Deposit(address indexed user, uint256 amount);
  event Withdraw(address indexed user, uint256 amount);
  event Earn();
  event Farm();
  event EmergencyWithdraw();
  event TokenToEarn(address token);
  event WrapNative();
  event SetExtraEarnTokens(address[] _extraEarnTokens);
  event SetPerformanceFee(uint256 _performanceFee);

  modifier onlyOwner() {
    require(address(autoOreo) == _msgSender(), "onlyOwner: not allowed");
    _;
  }

  modifier onlyOperator() {
    require(autoOreo.operators(msg.sender), "onlyOperator: not allowed");
    _;
  }

  function _farmDeposit(uint256 depositAmount) internal virtual;

  function _farmWithdraw(uint256 withdrawAmount) internal virtual;

  function _earnToStake(uint256 _earnAmount) internal virtual;

  function _farmEmergencyWithdraw() internal virtual;

  function _totalStaked() internal view virtual returns (uint256);

  receive() external payable {}

  constructor(uint256 _pid, address[6] memory _addresses) {
    autoOreo = IAutoOreo(_addresses[0]);
    stakeToken = IERC20(_addresses[1]);
    earnToken = IERC20(_addresses[2]);
    masterChef = _addresses[3];
    routeOracle = IRouteOracle(_addresses[4]);
    WNATIVE = _addresses[5];
    pid = _pid;
    IERC20(stakeToken).approve(masterChef, type(uint256).max);
  }

  /**
   * @notice deposits stake tokens in the underlying farm
   * @dev can only be called by AutoOreo contract which performs the required validations
   * @param _user address
   * @param _depositAmount amount deposited by the user
   */
  function deposit(address _user, uint256 _depositAmount) external virtual onlyOwner whenNotPaused {
    uint256 stakeTokenAmount = stakeToken.balanceOf(address(this));
    uint256 totalStakedBefore = _totalStaked() + stakeTokenAmount - _depositAmount;
    _farmDeposit(stakeTokenAmount);
    uint256 totalStakedAfter = _totalStaked() + stakeToken.balanceOf(address(this));

    // adjust for deposit fees on the underlying farm and token transfer fees
    _depositAmount = totalStakedAfter - totalStakedBefore;

    uint256 sharesAdded = _depositAmount;
    uint256 _totalSupply = totalSupply();
    if (totalStakedBefore > 0 && _totalSupply > 0) {
      sharesAdded = (_depositAmount * _totalSupply) / totalStakedBefore;
    }

    _mint(_user, sharesAdded);
    userAmountOnPoolAction[_user] = userAmountOnPoolAction[_user] + _depositAmount;
    emit Deposit(_user, _depositAmount);
  }

  /**
   * @notice unstake tokens from the underlying farm and transfers them to the given address
   * @dev can only be called by AutoOreo contract
   * @param _user address that will receive the stake tokens
   * @param _withdrawAmount number of vault tokens to withdraw
   */
  function withdraw(address _user, uint256 _withdrawAmount) external virtual onlyOwner nonReentrant {
    require(_withdrawAmount > 0, "withdraw: cannot be zero");
    uint256 totalStakedOnFarm = _totalStaked();
    uint256 totalStake = totalStakedOnFarm + stakeToken.balanceOf(address(this));
    uint256 sharesTotal = totalSupply();
    uint256 userBalance = balanceOf(_user);

    require(userBalance > 0, "withdraw: no shares");

    uint256 maxAmount = (userBalance * totalStake) / sharesTotal;
    if (_withdrawAmount > maxAmount) {
      _withdrawAmount = maxAmount;
    }

    // number of shares that the withdraw amount represents (rounded up)
    uint256 sharesRemoved = (_withdrawAmount * sharesTotal - 1) / totalStake + 1;

    if (sharesRemoved > sharesTotal) {
      sharesRemoved = sharesTotal;
    }

    if (totalStakedOnFarm > 0) {
      _farmWithdraw(_withdrawAmount);
    }

    uint256 stakeBalance = stakeToken.balanceOf(address(this));
    if (_withdrawAmount > stakeBalance) {
      _withdrawAmount = stakeBalance;
    }

    _burn(_user, sharesRemoved);
    stakeToken.safeTransfer(_user, _withdrawAmount);
    if (_withdrawAmount >= userAmountOnPoolAction[_user]) {
      userAmountOnPoolAction[_user] = 0;
    } else {
      userAmountOnPoolAction[_user] = userAmountOnPoolAction[_user] - _withdrawAmount;
    }
    emit Withdraw(_user, _withdrawAmount);
  }

  /**
   * @notice deposits the contract's balance of stake tokens in the underlying farm
   */
  function farm() external virtual nonReentrant whenNotPaused {
    _farm();
    emit Farm();
  }

  /**
   * @notice harvests earn tokens and deposits stake tokens in the underlying farm
   * @param _bountyHunter address that will get paid the bounty reward
   */
  function earn(address _bountyHunter) external virtual nonReentrant returns (uint256 bountyReward) {
    if (paused()) {
      return 0;
    }

    // harvest earn tokens
    uint256 earnAmountBefore = earnToken.balanceOf(address(this));
    _farmHarvest();

    for (uint256 i; i < extraEarnTokens.length; ) {
      address extraEarnToken = extraEarnTokens[i];
      uint256 balanceExtraEarn = IERC20(extraEarnToken).balanceOf(address(this));
      _trySafeSwap(balanceExtraEarn, extraEarnToken, address(earnToken));
      unchecked {
        i++;
      }
    }

    uint256 earnAmountAfter = earnToken.balanceOf(address(this));
    uint256 harvestAmount = earnAmountAfter - earnAmountBefore;

    uint256 platformFee;
    if (harvestAmount > 0) {
      (bountyReward, platformFee) = _distributeFees(harvestAmount, _bountyHunter);
    }
    uint256 earnAmount = earnAmountAfter - platformFee - bountyReward;

    _earnToStake(earnAmount);
    _farm();

    if (_bountyHunter != address(0)) {
      emit Earn();
    }
  }

  /**
   * @notice pauses the vault in case of emergency
   * @dev can only be called by the operator. Only in case of emergency.
   */
  function pause() external virtual onlyOperator {
    _removeAllowances();
    _pause();
  }

  /**
   * @notice unpauses the vault
   * @dev can only be called by the operator
   */
  function unpause() external virtual onlyOperator {
    require(!emergencyWithdrawn, "unpause: cannot unpause after emergency withdraw");
    _addAllowances();
    _unpause();
  }

  function setPerformanceFee(uint256 _performanceFee) external virtual onlyOperator {
    require(_performanceFee <= MAX_PERFORMANCE_FEE, "setPerformanceFee: too high");
    performanceFee = _performanceFee;
    emit SetPerformanceFee(_performanceFee);
  }

  /**
   * @notice updates the list of extra earn tokens
   * @dev can only be called by the operator
   */
  function setExtraEarnTokens(address[] calldata _extraEarnTokens) external virtual onlyOperator {
    require(_extraEarnTokens.length <= 5, "setExtraEarnTokens: cap exceeded");

    for (uint256 i; i < _extraEarnTokens.length; i++) {
      require(
        _extraEarnTokens[i] != address(earnToken) && _extraEarnTokens[i] != address(stakeToken),
        "setExtraEarnTokens: not allowed"
      );
      // erc20 sanity check
      IERC20(_extraEarnTokens[i]).balanceOf(address(this));
    }

    extraEarnTokens = _extraEarnTokens;
    emit SetExtraEarnTokens(_extraEarnTokens);
  }

  /**
   * @notice converts any token in the contract into earn tokens
   * @dev can only be called by the operator
   */
  function tokenToEarn(address _token) external virtual nonReentrant whenNotPaused onlyOperator {
    uint256 amount = IERC20(_token).balanceOf(address(this));
    require(_token != address(earnToken) && _token != address(stakeToken), "tokenToEarn: not allowed");
    if (amount > 0) {
      _safeSwap(amount, _token, address(earnToken));
    }
    emit TokenToEarn(_token);
  }

  /**
   * @notice converts NATIVE into WNATIVE (e.g. ETH -> WETH)
   */
  function wrapNative() external virtual {
    uint256 balance = address(this).balance;
    if (balance > 0) {
      IWETH(WNATIVE).deposit{ value: balance }();
    }
    emit WrapNative();
  }

  function totalStakeTokens() external view virtual returns (uint256) {
    return _totalStaked() + stakeToken.balanceOf(address(this));
  }

  /**
   * @notice invokes the emergency withdraw function in the underlying farm
   * @dev can only be called by the operator. Only in case of emergency.
   */
  function emergencyWithdraw() external virtual onlyOperator {
    if (!paused()) {
      _pause();
    }
    emergencyWithdrawn = true;
    _farmEmergencyWithdraw();
    emit EmergencyWithdraw();
  }

  function _farm() internal virtual {
    uint256 depositAmount = stakeToken.balanceOf(address(this));
    _farmDeposit(depositAmount);
  }

  function _farmHarvest() internal virtual {
    _farmDeposit(0);
  }

  function _distributeFees(uint256 _amount, address _bountyHunter)
    internal
    virtual
    returns (uint256 bountyReward, uint256 platformFee)
  {
    platformFee = (_amount * performanceFee) / 10000;
    if (_bountyHunter != address(0)) {
      bountyReward = platformFee / 10;
      unchecked {
        platformFee = platformFee - bountyReward;
      }
      earnToken.safeTransfer(_bountyHunter, bountyReward);
    }
    earnToken.safeTransfer(autoOreo.feeAddress(), platformFee);
  }

  function _addAllowances() internal virtual {
    IERC20(stakeToken).approve(masterChef, type(uint256).max);
  }

  function _removeAllowances() internal virtual {
    IERC20(stakeToken).approve(masterChef, 0);
  }

  function _safeSwap(
    uint256 _amountIn,
    address _tokenFrom,
    address _tokenTo
  ) internal virtual {
    (address router, address nextToken, bytes memory sig) = routeOracle.resolveSwapExactTokensForTokens(
      _amountIn,
      _tokenFrom,
      _tokenTo,
      address(this)
    );
    require(router != address(this) && router != masterChef, "_safeSwap: invalid router");
    if (router == address(stakeToken)) {
      require(
        !(sig[0] == 0xa9 && sig[1] == 0x05 && sig[2] == 0x9c && sig[3] == 0xbb) &&
          !(sig[0] == 0x23 && sig[1] == 0xb8 && sig[2] == 0x72 && sig[3] == 0xdd) &&
          !(sig[0] == 0x09 && sig[1] == 0x5e && sig[2] == 0xa7 && sig[3] == 0xb3),
        "_safeSwap: not allowed"
      );
    }
    if (IERC20(_tokenFrom).allowance(address(this), router) < _amountIn) {
      IERC20(_tokenFrom).approve(router, type(uint256).max);
    }
    uint256 nextTokenBalanceBefore;
    if (nextToken != address(0)) {
      nextTokenBalanceBefore = IERC20(nextToken).balanceOf(address(this));
    }
    (bool success, ) = router.call(sig);
    require(success, "_safeSwap: swap failed");
    if (nextToken != address(0)) {
      uint256 nextTokenAmount = IERC20(nextToken).balanceOf(address(this)) - nextTokenBalanceBefore;
      _safeSwap(nextTokenAmount, nextToken, _tokenTo);
    }
  }

  function _trySafeSwap(
    uint256 _amountIn,
    address _tokenFrom,
    address _tokenTo
  ) internal virtual {
    (address router, address nextToken, bytes memory sig) = routeOracle.resolveSwapExactTokensForTokens(
      _amountIn,
      _tokenFrom,
      _tokenTo,
      address(this)
    );
    require(router != address(this) && router != masterChef, "_trySafeSwap: invalid router");
    if (router == address(stakeToken)) {
      require(
        !(sig[0] == 0xa9 && sig[1] == 0x05 && sig[2] == 0x9c && sig[3] == 0xbb) &&
          !(sig[0] == 0x23 && sig[1] == 0xb8 && sig[2] == 0x72 && sig[3] == 0xdd) &&
          !(sig[0] == 0x09 && sig[1] == 0x5e && sig[2] == 0xa7 && sig[3] == 0xb3),
        "_trySafeSwap: not allowed"
      );
    }
    if (IERC20(_tokenFrom).allowance(address(this), router) < _amountIn) {
      IERC20(_tokenFrom).approve(router, type(uint256).max);
    }
    uint256 nextTokenBalanceBefore;
    if (nextToken != address(0)) {
      nextTokenBalanceBefore = IERC20(nextToken).balanceOf(address(this));
    }
    (bool success, ) = router.call(sig);
    if (success && nextToken != address(0)) {
      uint256 nextTokenAmount = IERC20(nextToken).balanceOf(address(this)) - nextTokenBalanceBefore;
      _safeSwap(nextTokenAmount, nextToken, _tokenTo);
    }
  }
}


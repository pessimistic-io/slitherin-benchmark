// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./IERC20.sol";
import { IWhitelist } from "./Whitelist.sol";
import { IPlutusChef } from "./Interfaces.sol";

contract PlsArbPlutusChefV2 is Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {
  uint256 private constant MUL_CONSTANT = 1e18;

  address public constant esPLSTokenAddr = 0xc636C1f678df0a834AD103196338CB7dd1D194FF;
  address public constant plsTokenAddr = 0x51318B7D00db7ACc4026C88c3952B66278B6A67F;
  IERC20 public constant pls = IERC20(plsTokenAddr);
  IERC20 public constant esPLS = IERC20(esPLSTokenAddr);

  IERC20 public constant stakingToken = IERC20(0x7a5D193fE4ED9098F7EAdC99797087C96b002907);

  // Info of each user.
  struct UserInfo {
    uint128 amount; // Staking tokens the user has provided
    int128 plsRewardDebt;
    int128 esPlsRewardDebt; // New variable for esPLS reward debt
  }

  mapping(address => bool) private handlers;
  IWhitelist public whitelist;

  uint128 public accPlsPerShare;
  uint128 private shares; // total staked
  uint128 public plsPerSecond;
  uint32 public lastRewardSecond;
  mapping(address => UserInfo) public userInfo;

  // new esPLS rewards tracking
  uint128 public accEsPlsPerShare;
  uint128 public esPlsPerSecond;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(uint32 _rewardEmissionStart) public initializer {
    __Pausable_init();
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
    lastRewardSecond = _rewardEmissionStart;
  }

  function deposit(uint128 _amount) external {
    _isEligibleSender();
    _deposit(msg.sender, msg.sender, _amount);
  }

  function withdraw(uint128 _amount) external {
    _isEligibleSender();
    _withdraw(msg.sender, _amount);
  }

  function harvest() external {
    _isEligibleSender();
    _harvest(msg.sender);
  }

  /**
   * Withdraw without caring about rewards. EMERGENCY ONLY.
   */
  function emergencyWithdraw() external {
    _isEligibleSender();
    UserInfo storage user = userInfo[msg.sender];

    uint128 _amount = user.amount;

    user.amount = 0;
    user.plsRewardDebt = 0;
    user.esPlsRewardDebt = 0;

    if (shares >= _amount) {
      shares -= _amount;
    } else {
      shares = 0;
    }

    stakingToken.transfer(msg.sender, _amount);
    emit EmergencyWithdraw(msg.sender, _amount);
  }

  /**
    Keep reward variables up to date. Ran before every mutative function.
   */
  function updateShares() public whenNotPaused {
    // if block.timestamp <= lastRewardSecond, already updated.
    if (block.timestamp <= lastRewardSecond) {
      return;
    }

    // if pool has no supply
    if (shares == 0) {
      lastRewardSecond = uint32(block.timestamp);
      return;
    }

    unchecked {
      accPlsPerShare += rewardPerShare(plsPerSecond);
      accEsPlsPerShare += rewardPerShare(esPlsPerSecond);
    }

    lastRewardSecond = uint32(block.timestamp);
  }

  /** HANDLER */
  function depositFor(address _user, uint128 _amount) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _deposit(msg.sender, _user, _amount);
  }

  function withdrawFor(address _user, uint128 _amount) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _withdraw(_user, _amount);
  }

  function harvestFor(address _user) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _harvest(_user);
  }

  /** VIEWS */

  /**
    Calculates the reward per share since `lastRewardSecond` was updated
  */
  function rewardPerShare(uint256 _rewardRatePerSecond) public view returns (uint128) {
    // duration = block.timestamp - lastRewardSecond;
    // tokenReward = duration * _rewardRatePerSecond;
    // tokenRewardPerShare = (tokenReward * MUL_CONSTANT) / shares;

    unchecked {
      return uint128(((block.timestamp - lastRewardSecond) * _rewardRatePerSecond * MUL_CONSTANT) / shares);
    }
  }

  /**
    View function to see pending rewards on frontend
   */
  function pendingRewards(address _user) external view returns (uint256 _pendingPls, uint256 _pendingEsPls) {
    uint256 _plsPS = accPlsPerShare;
    // For esPLS rewards
    uint256 _esPlsPS = accEsPlsPerShare;

    if (block.timestamp > lastRewardSecond && shares != 0) {
      _plsPS += rewardPerShare(plsPerSecond);
      _esPlsPS += rewardPerShare(esPlsPerSecond);
    }

    UserInfo memory user = userInfo[_user];

    _pendingPls = _calculatePending(user.plsRewardDebt, _plsPS, user.amount);

    _pendingEsPls = _calculatePending(user.esPlsRewardDebt, _esPlsPS, user.amount);
  }

  /** PRIVATE */
  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  function _calculatePending(
    int128 _rewardDebt,
    uint256 _accPerShare, // Stay 256;
    uint128 _amount
  ) private pure returns (uint128) {
    if (_rewardDebt < 0) {
      return uint128(_calculateRewardDebt(_accPerShare, _amount)) + uint128(-_rewardDebt);
    } else {
      return uint128(_calculateRewardDebt(_accPerShare, _amount)) - uint128(_rewardDebt);
    }
  }

  function _calculateRewardDebt(uint256 _accPerShare, uint128 _amount) private pure returns (uint256) {
    unchecked {
      return (_amount * _accPerShare) / MUL_CONSTANT;
    }
  }

  function _safeTokenTransfer(IERC20 _token, address _to, uint256 _amount) private {
    uint256 bal = _token.balanceOf(address(this));

    if (_amount > bal) {
      _token.transfer(_to, bal);
    } else {
      _token.transfer(_to, _amount);
    }
  }

  function _deposit(address _from, address _user, uint128 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (_amount < 1 ether) revert FAILED('min deposit: 1 ARB');
    updateShares();

    uint256 _prev = stakingToken.balanceOf(address(this));

    unchecked {
      user.amount += _amount;
      shares += _amount;
    }

    user.plsRewardDebt = user.plsRewardDebt + int128(uint128(_calculateRewardDebt(accPlsPerShare, _amount)));
    user.esPlsRewardDebt = user.esPlsRewardDebt + int128(uint128(_calculateRewardDebt(accEsPlsPerShare, _amount)));

    stakingToken.transferFrom(_from, address(this), _amount);

    unchecked {
      if (_prev + _amount != stakingToken.balanceOf(address(this))) revert FAILED('invariant violation');
    }

    emit Deposit(_user, _amount);
  }

  function _withdraw(address _user, uint128 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (user.amount < _amount || _amount == 0) revert WITHDRAW_ERROR();
    updateShares();

    unchecked {
      user.amount -= _amount;
      shares -= _amount;
    }

    user.plsRewardDebt = user.plsRewardDebt - int128(uint128(_calculateRewardDebt(accPlsPerShare, _amount)));
    user.esPlsRewardDebt = user.esPlsRewardDebt - int128(uint128(_calculateRewardDebt(accEsPlsPerShare, _amount)));

    stakingToken.transfer(_user, _amount);
    emit Withdraw(_user, _amount);
  }

  function _harvest(address _user) private {
    updateShares();
    UserInfo storage user = userInfo[_user];

    uint256 plsPending = _calculatePending(user.plsRewardDebt, accPlsPerShare, user.amount);

    user.plsRewardDebt = int128(uint128(_calculateRewardDebt(accPlsPerShare, user.amount)));

    _safeTokenTransfer(pls, _user, plsPending);

    // esPls pending reward

    uint256 esPlsPending = _calculatePending(user.esPlsRewardDebt, accEsPlsPerShare, user.amount);

    user.esPlsRewardDebt = int128(uint128(_calculateRewardDebt(accEsPlsPerShare, user.amount)));

    _safeTokenTransfer(esPLS, _user, esPlsPending);

    emit Harvest(_user, esPLSTokenAddr, esPlsPending);
    emit Harvest(_user, plsTokenAddr, plsPending);
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  function setWhitelist(address _whitelist) external onlyOwner {
    whitelist = IWhitelist(_whitelist);
  }

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    handlers[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  function setEmission(uint128 _plsPerSecond, uint128 _esPlsPerSecond) external onlyOwner {
    plsPerSecond = _plsPerSecond;
    esPlsPerSecond = _esPlsPerSecond;
  }

  function setStartTime(uint32 _startTime) external onlyOwner {
    lastRewardSecond = _startTime;
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  error FAILED(string);
  error WITHDRAW_ERROR();
  error UNAUTHORIZED();

  event HandlerUpdated(address indexed _handler, bool _isActive);
  event Deposit(address indexed _user, uint256 _amount);
  event Withdraw(address indexed _user, uint256 _amount);
  event Harvest(address indexed _user, address indexed _token, uint256 _amount);
  event EmergencyWithdraw(address indexed _user, uint256 _amount);
}


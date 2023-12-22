// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable.sol";
import { IRewardsDistro } from "./PlsJonesRewardsDistro.sol";
import { IWhitelist } from "./Whitelist.sol";

/**
  Assumptions:
  Total stake: <= 309_485_009 * 1e18 tokens
  Individual stake: <= 309_485_009 * 1e18 tokens
  DPX max supply: 5e23
  JONES max siupply: 1e25
  PLS max supply: 1e26
 */
contract PlsJonesPlutusChef is Ownable {
  uint256 private constant MUL_CONSTANT = 1e14;
  IRewardsDistro public immutable rewardsDistro;
  IERC20 public immutable plsJones;

  // Info of each user.
  struct UserInfo {
    uint96 amount; // Staking tokens the user has provided
    int128 plsRewardDebt;
    int128 plsDpxRewardDebt;
    int128 plsJonesRewardDebt;
    int128 jonesRewardDebt;
  }

  IWhitelist public whitelist;
  address public operator;

  uint128 public accPlsPerShare;
  uint96 private shares; // total staked
  uint32 public lastRewardSecond;

  // Treasury
  uint128 public accPlsDpxPerShare;
  uint128 public accPlsJonesPerShare;

  // Farm
  uint128 public accJonesPerShare;

  mapping(address => UserInfo) public userInfo;

  constructor(address _rewardsDistro, address _plsJones) {
    rewardsDistro = IRewardsDistro(_rewardsDistro);
    plsJones = IERC20(_plsJones);
  }

  function deposit(uint96 _amount) external {
    _isEligibleSender();
    _deposit(msg.sender, _amount);
  }

  function withdraw(uint96 _amount) external {
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

    uint96 _amount = user.amount;

    user.amount = 0;
    user.plsRewardDebt = 0;

    if (shares >= _amount) {
      shares -= _amount;
    } else {
      shares = 0;
    }

    plsJones.transfer(msg.sender, _amount);
    emit EmergencyWithdraw(msg.sender, _amount);
  }

  /**
    Keep reward variables up to date. Ran before every mutative function.
   */
  function updateShares() public {
    // if block.timestamp <= lastRewardSecond, already updated.
    if (block.timestamp <= lastRewardSecond) {
      return;
    }

    // if pool has no supply
    if (shares == 0) {
      lastRewardSecond = uint32(block.timestamp);
      return;
    }

    (uint80 pls_, uint80 plsDpx_, uint80 plsJones_, uint80 pendingJonesLessFee_) = rewardsDistro.updateInfo();

    unchecked {
      accPlsPerShare += rewardPerShare(pls_);
      accPlsDpxPerShare += rewardPerShare(plsDpx_);
      accPlsJonesPerShare += rewardPerShare(plsJones_);

      accJonesPerShare += uint128((pendingJonesLessFee_ * MUL_CONSTANT) / shares);
    }

    rewardsDistro.harvestFromUnderlyingFarm();
    lastRewardSecond = uint32(block.timestamp);
  }

  /** OPERATOR */
  function depositFor(address _user, uint88 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _deposit(_user, _amount);
  }

  function withdrawFor(address _user, uint88 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _withdraw(_user, _amount);
  }

  function harvestFor(address _user) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _harvest(_user);
  }

  /** VIEWS */

  /**
    Calculates the reward per share since `lastRewardSecond` was updated
  */
  function rewardPerShare(uint80 _rewardRatePerSecond) public view returns (uint128) {
    // duration = block.timestamp - lastRewardSecond;
    // tokenReward = duration * _rewardRatePerSecond;
    // tokenRewardPerShare = (tokenReward * MUL_CONSTANT) / shares;

    unchecked {
      return uint128(((block.timestamp - lastRewardSecond) * uint256(_rewardRatePerSecond) * MUL_CONSTANT) / shares);
    }
  }

  /**
    View function to see pending rewards on frontend
   */
  function pendingRewards(address _user)
    external
    view
    returns (
      uint256 _pendingPls,
      uint256 _pendingPlsDpx,
      uint256 _pendingPlsJones,
      uint256 _pendingJones
    )
  {
    uint256 _accPlsPerShare = accPlsPerShare;
    uint256 _accPlsDpxPerShare = accPlsDpxPerShare;
    uint256 _accPlsJonesPerShare = accPlsJonesPerShare;
    uint256 _accJonesPerShare = accJonesPerShare;

    (uint80 pls_, uint80 plsDpx_, uint80 plsJones_, uint80 pendingJonesLessFee_) = rewardsDistro.updateInfo();

    if (block.timestamp > lastRewardSecond && shares != 0) {
      _accPlsPerShare += rewardPerShare(pls_);
      _accPlsDpxPerShare += rewardPerShare(plsDpx_);
      _accPlsJonesPerShare += rewardPerShare(plsJones_);

      _accJonesPerShare += uint256((pendingJonesLessFee_ * MUL_CONSTANT) / shares);
    }

    UserInfo memory user = userInfo[_user];

    _pendingPls = _calculatePending(user.plsRewardDebt, _accPlsPerShare, user.amount);
    _pendingPlsDpx = _calculatePending(user.plsDpxRewardDebt, _accPlsDpxPerShare, user.amount);
    _pendingPlsJones = _calculatePending(user.plsJonesRewardDebt, _accPlsJonesPerShare, user.amount);
    _pendingJones = _calculatePending(user.jonesRewardDebt, _accJonesPerShare, user.amount);
  }

  /** PRIVATE */
  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  function _calculatePending(
    int128 _rewardDebt,
    uint256 _accPerShare, // Stay 256;
    uint96 _amount
  ) private pure returns (uint128) {
    if (_rewardDebt < 0) {
      return uint128(_calculateRewardDebt(_accPerShare, _amount)) + uint128(-_rewardDebt);
    } else {
      return uint128(_calculateRewardDebt(_accPerShare, _amount)) - uint128(_rewardDebt);
    }
  }

  function _calculateRewardDebt(uint256 _accPlsPerShare, uint96 _amount) private pure returns (uint256) {
    unchecked {
      return (_amount * _accPlsPerShare) / MUL_CONSTANT;
    }
  }

  function _deposit(address _user, uint96 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (_amount == 0) revert DEPOSIT_ERROR();
    updateShares();

    uint256 _prev = plsJones.balanceOf(address(this));

    unchecked {
      user.amount += _amount;
      shares += _amount;
    }

    user.plsRewardDebt = user.plsRewardDebt + int128(uint128(_calculateRewardDebt(accPlsPerShare, _amount)));

    user.plsDpxRewardDebt = user.plsDpxRewardDebt + int128(uint128(_calculateRewardDebt(accPlsDpxPerShare, _amount)));

    user.plsJonesRewardDebt =
      user.plsJonesRewardDebt +
      int128(uint128(_calculateRewardDebt(accPlsJonesPerShare, _amount)));

    user.jonesRewardDebt = user.jonesRewardDebt + int128(uint128(_calculateRewardDebt(accJonesPerShare, _amount)));

    plsJones.transferFrom(_user, address(this), _amount);

    unchecked {
      if (_prev + _amount != plsJones.balanceOf(address(this))) revert DEPOSIT_ERROR();
    }

    emit Deposit(_user, _amount);
  }

  function _withdraw(address _user, uint96 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (user.amount < _amount || _amount == 0) revert WITHDRAW_ERROR();
    updateShares();

    unchecked {
      user.amount -= _amount;
      shares -= _amount;
    }

    user.plsRewardDebt = user.plsRewardDebt - int128(uint128(_calculateRewardDebt(accPlsPerShare, _amount)));

    user.plsDpxRewardDebt = user.plsDpxRewardDebt - int128(uint128(_calculateRewardDebt(accPlsDpxPerShare, _amount)));

    user.plsJonesRewardDebt =
      user.plsJonesRewardDebt -
      int128(uint128(_calculateRewardDebt(accPlsJonesPerShare, _amount)));

    user.jonesRewardDebt = user.jonesRewardDebt - int128(uint128(_calculateRewardDebt(accJonesPerShare, _amount)));

    plsJones.transfer(_user, _amount);
    emit Withdraw(_user, _amount);
  }

  function _harvest(address _user) private {
    updateShares();
    UserInfo storage user = userInfo[_user];

    uint128 plsPending = _calculatePending(user.plsRewardDebt, accPlsPerShare, user.amount);

    uint128 plsDpxPending = _calculatePending(user.plsDpxRewardDebt, accPlsDpxPerShare, user.amount);

    uint128 plsJonesPending = _calculatePending(user.plsJonesRewardDebt, accPlsJonesPerShare, user.amount);

    uint128 jonesPending = _calculatePending(user.jonesRewardDebt, accJonesPerShare, user.amount);

    user.plsRewardDebt = int128(uint128(_calculateRewardDebt(accPlsPerShare, user.amount)));

    user.plsDpxRewardDebt = int128(uint128(_calculateRewardDebt(accPlsDpxPerShare, user.amount)));

    user.plsJonesRewardDebt = int128(uint128(_calculateRewardDebt(accPlsJonesPerShare, user.amount)));

    user.jonesRewardDebt = int128(uint128(_calculateRewardDebt(accJonesPerShare, user.amount)));

    rewardsDistro.sendRewards(_user, plsPending, plsDpxPending, plsJonesPending, jonesPending);
  }

  /** OWNER FUNCTIONS */
  function setWhitelist(address _whitelist) external onlyOwner {
    whitelist = IWhitelist(_whitelist);
  }

  function setOperator(address _operator) external onlyOwner {
    operator = _operator;
  }

  function setStartTime(uint32 _startTime) external onlyOwner {
    if (lastRewardSecond == 0) {
      lastRewardSecond = _startTime;
    }
  }

  error DEPOSIT_ERROR();
  error WITHDRAW_ERROR();
  error UNAUTHORIZED();

  event Deposit(address indexed _user, uint256 _amount);
  event Withdraw(address indexed _user, uint256 _amount);
  event EmergencyWithdraw(address indexed _user, uint256 _amount);
}


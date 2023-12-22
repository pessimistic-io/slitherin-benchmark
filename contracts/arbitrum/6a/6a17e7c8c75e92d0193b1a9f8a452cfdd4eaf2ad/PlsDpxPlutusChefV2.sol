// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import { IPlsDpxRewardsDistroV2 } from "./PlsDpxRewardsDistroV2.sol";
import { IWhitelist } from "./Whitelist.sol";

/**
  Assumptions:
  Total stake: <= 309_485_009 * 1e18 tokens
  Individual stake: <= 309_485_009 * 1e18 tokens
  DPX max supply: 5e23
  JONES max supply: 1e25
  PLS max supply: 1e26
 */
contract PlsDpxPlutusChefV2 is Initializable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
  uint256 private constant MUL_CONSTANT = 1e14;
  IERC20 public constant plsDpx = IERC20(0xF236ea74B515eF96a9898F5a4ed4Aa591f253Ce1);
  IPlsDpxRewardsDistroV2 public constant REWARDS_DISTRO =
    IPlsDpxRewardsDistroV2(0xE0B84A2A3cBab94376296694A443ac3D5De18A23);

  // Info of each user.
  struct UserInfo {
    uint96 amount; // Staking tokens the user has provided
    int128 plsRewardDebt;
    int128 plsDpxRewardDebt;
    int128 plsJonesRewardDebt;
    int128 dpxRewardDebt;
  }

  bool private initialRewardsCheckpointed;
  IWhitelist public whitelist;
  address public operator;

  uint128 public accPlsPerShare;
  uint96 private shares; // total staked
  uint32 public lastRewardSecond;

  // Treasury
  uint128 public accPlsDpxPerShare;
  uint128 public accPlsJonesPerShare;

  // Farm
  uint128 public accDpxPerShare;

  mapping(address => UserInfo) public userInfo;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Pausable_init();
    __Ownable_init();
    __UUPSUpgradeable_init();
    lastRewardSecond = 1657951200;
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

    plsDpx.transfer(msg.sender, _amount);
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

    (uint80 pls_, uint80 plsDpx_, uint80 plsJones_, uint256 pendingDpxLessFee_) = REWARDS_DISTRO.getEmissions();

    unchecked {
      if (initialRewardsCheckpointed) {
        accPlsPerShare += rewardPerShare(pls_);
        accPlsDpxPerShare += rewardPerShare(plsDpx_);
        accPlsJonesPerShare += rewardPerShare(plsJones_);
      } else {
        accPlsPerShare += uint128((22143633639269406213924 * MUL_CONSTANT) / shares);
        accPlsDpxPerShare += uint128((2615602764577530702 * MUL_CONSTANT) / shares);
        accPlsJonesPerShare += uint128((440456322143624202 * MUL_CONSTANT) / shares);
        initialRewardsCheckpointed = true;
      }

      accDpxPerShare += uint128((pendingDpxLessFee_ * MUL_CONSTANT) / shares);
    }

    REWARDS_DISTRO.harvest();
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
      uint256 _pendingDpx
    )
  {
    uint256 _plsPS = accPlsPerShare;
    uint256 _plsDpxPS = accPlsDpxPerShare;
    uint256 _plsJonesPS = accPlsJonesPerShare;
    uint256 _dpxPS = accDpxPerShare;

    if (block.timestamp > lastRewardSecond && shares != 0) {
      (uint80 pls_, uint80 plsDpx_, uint80 plsJones_, uint256 pendingDpxLessFee_) = REWARDS_DISTRO.getEmissions();

      _plsPS += rewardPerShare(pls_);
      _plsDpxPS += rewardPerShare(plsDpx_);
      _plsJonesPS += rewardPerShare(plsJones_);

      _dpxPS += uint256((pendingDpxLessFee_ * MUL_CONSTANT) / shares);
    }

    UserInfo memory user = userInfo[_user];

    _pendingPls = _calculatePending(user.plsRewardDebt, _plsPS, user.amount);
    _pendingPlsDpx = _calculatePending(user.plsDpxRewardDebt, _plsDpxPS, user.amount);
    _pendingPlsJones = _calculatePending(user.plsJonesRewardDebt, _plsJonesPS, user.amount);
    _pendingDpx = _calculatePending(user.dpxRewardDebt, _dpxPS, user.amount);
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

    uint256 _prev = plsDpx.balanceOf(address(this));

    unchecked {
      user.amount += _amount;
      shares += _amount;
    }

    user.plsRewardDebt = user.plsRewardDebt + int128(uint128(_calculateRewardDebt(accPlsPerShare, _amount)));

    user.plsDpxRewardDebt = user.plsDpxRewardDebt + int128(uint128(_calculateRewardDebt(accPlsDpxPerShare, _amount)));

    user.plsJonesRewardDebt =
      user.plsJonesRewardDebt +
      int128(uint128(_calculateRewardDebt(accPlsJonesPerShare, _amount)));

    user.dpxRewardDebt = user.dpxRewardDebt + int128(uint128(_calculateRewardDebt(accDpxPerShare, _amount)));

    plsDpx.transferFrom(_user, address(this), _amount);

    unchecked {
      if (_prev + _amount != plsDpx.balanceOf(address(this))) revert DEPOSIT_ERROR();
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

    user.dpxRewardDebt = user.dpxRewardDebt - int128(uint128(_calculateRewardDebt(accDpxPerShare, _amount)));

    plsDpx.transfer(_user, _amount);
    emit Withdraw(_user, _amount);
  }

  function _harvest(address _user) private {
    updateShares();
    UserInfo storage user = userInfo[_user];

    uint128 plsPending = _calculatePending(user.plsRewardDebt, accPlsPerShare, user.amount);

    uint128 plsDpxPending = _calculatePending(user.plsDpxRewardDebt, accPlsDpxPerShare, user.amount);

    uint128 plsJonesPending = _calculatePending(user.plsJonesRewardDebt, accPlsJonesPerShare, user.amount);

    uint128 dpxPending = _calculatePending(user.dpxRewardDebt, accDpxPerShare, user.amount);

    user.plsRewardDebt = int128(uint128(_calculateRewardDebt(accPlsPerShare, user.amount)));

    user.plsDpxRewardDebt = int128(uint128(_calculateRewardDebt(accPlsDpxPerShare, user.amount)));

    user.plsJonesRewardDebt = int128(uint128(_calculateRewardDebt(accPlsJonesPerShare, user.amount)));

    user.dpxRewardDebt = int128(uint128(_calculateRewardDebt(accDpxPerShare, user.amount)));

    REWARDS_DISTRO.sendRewards(_user, plsPending, plsDpxPending, plsJonesPending, dpxPending);
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  function setWhitelist(address _whitelist) external onlyOwner {
    whitelist = IWhitelist(_whitelist);
  }

  function setOperator(address _operator) external onlyOwner {
    operator = _operator;
  }

  function setStartTime(uint32 _startTime) external onlyOwner {
    lastRewardSecond = _startTime;
  }

  error DEPOSIT_ERROR();
  error WITHDRAW_ERROR();
  error UNAUTHORIZED();

  event Deposit(address indexed _user, uint256 _amount);
  event Withdraw(address indexed _user, uint256 _amount);
  event EmergencyWithdraw(address indexed _user, uint256 _amount);
}


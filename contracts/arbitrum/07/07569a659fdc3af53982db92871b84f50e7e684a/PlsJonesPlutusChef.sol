// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./IERC20.sol";
import { IWhitelist } from "./Whitelist.sol";
import { IPlsJonesRewardsDistro, IPlsJonesPlutusChef } from "./Interfaces.sol";

contract PlsJonesPlutusChef is
  Initializable,
  PausableUpgradeable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  IPlsJonesPlutusChef
{
  struct UserInfo {
    uint96 amount;
    int128 gxpRewardDebt;
    int128 grailRewardDebt;
  }

  uint256 private constant MUL_CONSTANT = 1e24;
  IERC20 public constant STAKING_TOKEN = IERC20(0xe7f6C3c1F0018E4C08aCC52965e5cbfF99e34A44);

  uint128 public acc_gxp_PerShare;
  uint128 public acc_grail_PerShare;
  uint96 public shares;

  IWhitelist public whitelist;
  IPlsJonesRewardsDistro public distro;
  mapping(address => UserInfo) public userInfo;
  mapping(address => bool) private handlers;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Pausable_init();
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
  }

  function deposit(uint96 _amount) external {
    _isEligibleSender();
    _deposit(msg.sender, msg.sender, _amount);
  }

  function withdraw(uint96 _amount) external {
    _isEligibleSender();
    _withdraw(msg.sender, _amount);
  }

  function harvest() external {
    _isEligibleSender();
    _harvest(msg.sender);
  }

  function emergencyWithdraw() external {
    _isEligibleSender();
    UserInfo storage user = userInfo[msg.sender];

    uint96 _amount = user.amount;

    user.amount = 0;
    user.gxpRewardDebt = 0;
    user.grailRewardDebt = 0;

    if (shares >= _amount) {
      shares -= _amount;
    } else {
      shares = 0;
    }

    STAKING_TOKEN.transfer(msg.sender, _amount);
    emit EmergencyWithdraw(msg.sender, _amount);
  }

  function updateShares() public whenNotPaused {
    uint _shares = shares;

    if (_shares == 0) {
      return;
    }

    if (distro.hasBufferedRewards()) {
      (uint _grailAmt, uint _gxpAmt) = distro.record();
      acc_gxp_PerShare += uint128((_gxpAmt * MUL_CONSTANT) / _shares);
      acc_grail_PerShare += uint128((_grailAmt * MUL_CONSTANT) / _shares);
    }
  }

  /** VIEWS */
  function pendingRewards(address _user) external view returns (uint _grail, uint _gxp) {
    uint _shares = shares;
    uint _accGxpPerShare = acc_gxp_PerShare;
    uint _accGrailPerShare = acc_grail_PerShare;

    if (_shares != 0) {
      (uint _grailAmt, uint _gxpAmt) = distro.pendingRewards();
      _accGxpPerShare += uint128((_gxpAmt * MUL_CONSTANT) / _shares);
      _accGrailPerShare += uint128((_grailAmt * MUL_CONSTANT) / _shares);
    }

    UserInfo memory user = userInfo[_user];
    _grail = _calculatePending(user.grailRewardDebt, _accGrailPerShare, user.amount);
    _gxp = _calculatePending(user.gxpRewardDebt, _accGxpPerShare, user.amount);
  }

  /** PRIVATE */
  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  function _calculatePending(
    int128 _rewardDebt,
    uint256 _accTokenPerShare, // Stay 256;
    uint96 _amount
  ) private pure returns (uint128) {
    if (_rewardDebt < 0) {
      return uint128(_calculateRewardDebt(_accTokenPerShare, _amount)) + uint128(-_rewardDebt);
    } else {
      return uint128(_calculateRewardDebt(_accTokenPerShare, _amount)) - uint128(_rewardDebt);
    }
  }

  function _deposit(address _from, address _user, uint96 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (_amount < 1e6) revert DEPOSIT_ERROR('min deposit: 0.000000000001');
    updateShares();

    uint256 _prev = STAKING_TOKEN.balanceOf(address(this));

    unchecked {
      user.amount += _amount;
      shares += _amount;
    }

    user.grailRewardDebt += int128(uint128(_calculateRewardDebt(acc_grail_PerShare, _amount)));
    user.gxpRewardDebt += int128(uint128(_calculateRewardDebt(acc_gxp_PerShare, _amount)));
    STAKING_TOKEN.transferFrom(_from, address(this), _amount);

    unchecked {
      if (_prev + _amount != STAKING_TOKEN.balanceOf(address(this))) revert DEPOSIT_ERROR('invariant violation');
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

    user.grailRewardDebt -= int128(uint128(_calculateRewardDebt(acc_grail_PerShare, _amount)));
    user.gxpRewardDebt -= int128(uint128(_calculateRewardDebt(acc_gxp_PerShare, _amount)));
    STAKING_TOKEN.transfer(_user, _amount);
    emit Withdraw(_user, _amount);
  }

  function _harvest(address _user) private {
    updateShares();
    UserInfo storage user = userInfo[_user];

    uint _pendingGrail = _calculatePending(user.grailRewardDebt, acc_grail_PerShare, user.amount);
    uint _pendingGxp = _calculatePending(user.gxpRewardDebt, acc_gxp_PerShare, user.amount);

    user.grailRewardDebt = int128(uint128(_calculateRewardDebt(acc_grail_PerShare, user.amount)));
    user.gxpRewardDebt = int128(uint128(_calculateRewardDebt(acc_gxp_PerShare, user.amount)));

    distro.sendRewards(_user, _pendingGrail, _pendingGxp);
  }

  function _calculateRewardDebt(uint256 _accTokenPerShare, uint256 _amount) private pure returns (uint256) {
    unchecked {
      return (_amount * _accTokenPerShare) / MUL_CONSTANT;
    }
  }

  /** HANDLER */
  function depositFor(address _user, uint96 _amount) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _deposit(msg.sender, _user, _amount);
  }

  function withdrawFor(address _user, uint96 _amount) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _withdraw(_user, _amount);
  }

  function harvestFor(address _user) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _harvest(_user);
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

  function setDistro(address _distro) external onlyOwner {
    distro = IPlsJonesRewardsDistro(_distro);
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }
}


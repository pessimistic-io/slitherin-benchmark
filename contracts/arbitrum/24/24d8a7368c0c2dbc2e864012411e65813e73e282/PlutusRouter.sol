// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import { IRewardTracker, IErrors, IBaseMintableToken, IBaseDistributor } from "./Interfaces.sol";
import { ILockedToken } from "./LockedToken.sol";
import { IBonusTracker } from "./BonusTracker.sol";
import { ICheckpointer } from "./Checkpointer.sol";

interface IPlutusRouter {
  event Stake(address indexed _account, address indexed _token, uint _amount);

  event Unstake(address indexed _account, address indexed _token, uint _amount);

  struct TrackerSet {
    address staked;
    address bonus;
    address locked;
    address checkpointer;
  }
}

contract PlutusRouter is
  IPlutusRouter,
  IErrors,
  Initializable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable
{
  address public constant pls = 0x51318B7D00db7ACc4026C88c3952B66278B6A67F;
  address public mpPls;
  address public esPls;
  address public constant plsWeth = 0xbFD465E270F8D6bA62b5000cD27D155FB5aE70f0;

  address public stakedPlsTracker;
  address public bonusPlsTracker;
  ILockedToken public lockedPls;
  address public plsCheckpointer;

  address public stakedPlsWethTracker;
  address public bonusPlsWethTracker;
  ILockedToken public lockedPlsWeth;
  address public plsWethCheckpointer;

  address public stakedEsPlsTracker;
  address public bonusEsPlsTracker;
  address public esPlsCheckpointer;

  IBonusTracker public mpPlsTracker;
  address public mpPlsCheckpointer;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _mpPls,
    address _esPls,
    TrackerSet memory _plsTracker,
    TrackerSet memory _plsWethTracker,
    TrackerSet memory _esPlsTracker,
    address _mpPlsTracker,
    address _mpPlsCheckpointer
  ) public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
    __Pausable_init();
    __ReentrancyGuard_init();

    mpPls = _mpPls;
    esPls = _esPls;

    stakedPlsTracker = _plsTracker.staked;
    bonusPlsTracker = _plsTracker.bonus;
    lockedPls = ILockedToken(_plsTracker.locked);
    plsCheckpointer = _plsTracker.checkpointer;

    stakedPlsWethTracker = _plsWethTracker.staked;
    bonusPlsWethTracker = _plsWethTracker.bonus;
    lockedPlsWeth = ILockedToken(_plsWethTracker.locked);
    plsWethCheckpointer = _plsWethTracker.checkpointer;

    stakedEsPlsTracker = _esPlsTracker.staked;
    bonusEsPlsTracker = _esPlsTracker.bonus;
    esPlsCheckpointer = _esPlsTracker.checkpointer;

    mpPlsTracker = IBonusTracker(_mpPlsTracker);
    mpPlsCheckpointer = _mpPlsCheckpointer;
  }

  /// @dev need to delegate to self to reflect voting power
  function delegateToSelf() external nonReentrant whenNotPaused {
    ICheckpointer(plsCheckpointer).delegateOnBehalf(msg.sender, msg.sender);
    ICheckpointer(plsWethCheckpointer).delegateOnBehalf(msg.sender, msg.sender);
    ICheckpointer(esPlsCheckpointer).delegateOnBehalf(msg.sender, msg.sender);
    ICheckpointer(mpPlsCheckpointer).delegateOnBehalf(msg.sender, msg.sender);
  }

  function toggleAutoExtend(ILockedToken _token) external nonReentrant whenNotPaused {
    ILockedToken(_token).toggleAutoExtendOnBehalf(msg.sender);
  }

  function stakeAndLockPls(uint _amount) external nonReentrant whenNotPaused {
    _autoExtendExpiredLocks(msg.sender);

    _stake(msg.sender, msg.sender, pls, _amount, stakedPlsTracker, bonusPlsTracker, plsCheckpointer);
    lockedPls.lock(msg.sender, msg.sender, _amount);
  }

  function unlockAndUnstakePls() external nonReentrant whenNotPaused {
    if (lockedPls.isAutoextendDisabled(msg.sender) == false) revert FAILED('PlutusRouter: Auto-extend is enabled');

    uint256 _withdrawn = uint256(lockedPls.withdrawExpiredLocksOnBehalf(msg.sender, msg.sender));
    _unstake(msg.sender, pls, _withdrawn, true, stakedPlsTracker, bonusPlsTracker, plsCheckpointer);
  }

  function stakeAndLockPlsWeth(uint _amount) external nonReentrant whenNotPaused {
    _autoExtendExpiredLocks(msg.sender);

    _stake(msg.sender, msg.sender, plsWeth, _amount, stakedPlsWethTracker, bonusPlsWethTracker, plsWethCheckpointer);
    lockedPlsWeth.lock(msg.sender, msg.sender, _amount);
  }

  function unlockAndUnstakePlsWeth() external nonReentrant whenNotPaused {
    if (lockedPlsWeth.isAutoextendDisabled(msg.sender) == false) revert FAILED('PlutusRouter: Auto-extend is enabled');

    uint256 _withdrawn = uint256(lockedPlsWeth.withdrawExpiredLocksOnBehalf(msg.sender, msg.sender));
    _unstake(msg.sender, plsWeth, _withdrawn, true, stakedPlsWethTracker, bonusPlsWethTracker, plsWethCheckpointer);
  }

  function stakeEsPls(uint _amount) external nonReentrant whenNotPaused {
    _autoExtendExpiredLocks(msg.sender);

    _stake(msg.sender, msg.sender, esPls, _amount, stakedEsPlsTracker, bonusEsPlsTracker, esPlsCheckpointer);
  }

  function unstakeEsPls(uint _amount) external nonReentrant whenNotPaused {
    _autoExtendExpiredLocks(msg.sender);

    _unstake(msg.sender, esPls, _amount, true, stakedEsPlsTracker, bonusEsPlsTracker, esPlsCheckpointer);
  }

  function claimAndStakeMpPls() external nonReentrant whenNotPaused {
    _autoExtendExpiredLocks(msg.sender);

    _claimAllAndStakeMpPls(msg.sender);
  }

  function claimEsPls() external nonReentrant whenNotPaused {
    _autoExtendExpiredLocks(msg.sender);

    IRewardTracker(stakedPlsTracker).claimForAccount(msg.sender, msg.sender);
    IRewardTracker(stakedPlsWethTracker).claimForAccount(msg.sender, msg.sender);
    IRewardTracker(stakedEsPlsTracker).claimForAccount(msg.sender, msg.sender);
  }

  /** PRIVATE */
  function _autoExtendExpiredLocks(address _account) private {
    lockedPls.processExpiredLocksOnBehalf(_account);
    lockedPlsWeth.processExpiredLocksOnBehalf(_account);
  }

  function _claimAllAndStakeMpPls(address _account) private returns (uint256 _totalClaimedAmount) {
    _totalClaimedAmount += _claimAndStakeMpPlsFor(_account, bonusPlsTracker);
    _totalClaimedAmount += _claimAndStakeMpPlsFor(_account, bonusPlsWethTracker);
    _totalClaimedAmount += _claimAndStakeMpPlsFor(_account, bonusEsPlsTracker);
  }

  function _claimAndStakeMpPlsFor(address _account, address _rewardTracker) private returns (uint256 _claimedAmount) {
    _claimedAmount = IRewardTracker(_rewardTracker).claimForAccount(_account, _account);

    if (_claimedAmount > 0) {
      mpPlsTracker.stakeForAccount(_account, _account, _rewardTracker, _claimedAmount);
      ICheckpointer(mpPlsCheckpointer).increment(_account, _claimedAmount);
    }
  }

  function _unstake(
    address _account,
    address _token,
    uint256 _amount,
    bool _shouldReduceMp,
    address _rewardTracker,
    address _bonusTracker,
    address _checkpointer
  ) private {
    if (_amount == 0) revert FAILED('PlutusRouter: invalid amount');

    uint256 _accountStakedMpsPls = IRewardTracker(bonusPlsTracker).stakedSynthAmounts(_account) +
      IRewardTracker(bonusPlsWethTracker).stakedSynthAmounts(_account) +
      IRewardTracker(bonusEsPlsTracker).stakedSynthAmounts(_account);

    IRewardTracker(_bonusTracker).unstakeForAccount(_account, _rewardTracker, _amount, _account);
    IRewardTracker(_rewardTracker).unstakeForAccount(_account, _token, _amount, _account);
    ICheckpointer(_checkpointer).decrement(_account, _amount);

    emit Unstake(_account, _token, _amount);

    if (_shouldReduceMp) {
      if (plsWeth == _token) {
        _amount = (_amount * IBaseDistributor(IRewardTracker(bonusPlsWethTracker).distributor()).getRate()) / 1e4;
      }
      _reduceMps(_account, _accountStakedMpsPls, _amount);
    }
  }

  function _reduceMps(address _account, uint256 _accountStakedMpsPls, uint256 _amountUnstaked) private {
    _claimAllAndStakeMpPls(_account);
    uint256 _totalStakedMpPls = mpPlsTracker.stakedAmounts(_account);

    if (_totalStakedMpPls > 0) {
      uint256 _reductionAmount = (_totalStakedMpPls * _amountUnstaked) / _accountStakedMpsPls;

      mpPlsTracker.unstakeForAccount(_account, _reductionAmount, _account);
      ICheckpointer(mpPlsCheckpointer).decrement(_account, _reductionAmount);
      IBaseMintableToken(mpPls).burn(_account, _reductionAmount);
    }
  }

  function _stake(
    address _fundingAccount,
    address _account,
    address _token,
    uint256 _amount,
    address _rewardTracker,
    address _bonusTracker,
    address _checkpointer
  ) private {
    if (_amount == 0) revert FAILED('PlutusRouter: invalid amount');

    IRewardTracker(_rewardTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
    IRewardTracker(_bonusTracker).stakeForAccount(_account, _account, _rewardTracker, _amount);
    ICheckpointer(_checkpointer).increment(_account, _amount);

    emit Stake(_account, _token, _amount);
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function recoverErc20(IERC20Upgradeable _erc20, uint _amount) external onlyOwner {
    IERC20Upgradeable(_erc20).transfer(owner(), _amount);
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./IStakingRewards.sol";
import "./IEpochStaking.sol";
import "./IWhitelist.sol";

contract PlutusEpochStaking is IEpochStaking, Ownable, Pausable {
  IERC20 public immutable pls;
  uint32 public immutable lockDuration;

  struct StakedDetails {
    uint112 amount;
    uint32 lastCheckpoint;
  }

  struct EpochCheckpoint {
    uint32 startedAt;
    uint32 endedAt;
    uint112 totalStaked;
  }

  address public operator;
  IStakingRewards public stakingRewards;
  IWhitelist public whitelist;

  bool public stakingWindowOpen;
  uint112 public currentTotalStaked;
  uint32 public currentEpochStartedAt;
  uint32 public currentEpoch;
  mapping(address => StakedDetails) public stakedDetails;

  mapping(uint32 => EpochCheckpoint) public epochCheckpoints;
  mapping(address => mapping(uint32 => uint112)) public stakedCheckpoints;

  constructor(
    address _pls,
    address _operator,
    address _governance,
    uint32 _lockDuration
  ) {
    operator = _operator;
    lockDuration = _lockDuration;
    pls = IERC20(_pls);
    _pause();
    transferOwnership(_governance);
  }

  function stake(uint112 _amt) external onlyEligibleSender whenNotPaused whenStakingOpen {
    _stake(_amt, msg.sender);
  }

  function unstake() external onlyEligibleSender whenNotPaused whenStakingOpen {
    _unstake(msg.sender, msg.sender);
  }

  function claimRewards(uint32 _epoch) external onlyEligibleSender whenNotPaused {
    _claimRewards(_epoch, msg.sender, msg.sender);
  }

  /** MODIFIERS */
  modifier whenStakingOpen() {
    require(stakingWindowOpen, '!Open');
    _;
  }
  modifier onlyEligibleSender() {
    require(msg.sender == tx.origin || whitelist.isWhitelisted(msg.sender), '!Eligible');
    _;
  }

  modifier onlyOwnerOrOperator() {
    require(msg.sender == operator || msg.sender == owner(), '!Unauthorized');
    _;
  }

  /** INTERNAL */
  function _stake(uint112 _amt, address _user) internal {
    require(_amt > 0, '<0');

    StakedDetails storage _staked = stakedDetails[_user];

    if (_staked.lastCheckpoint != currentEpoch) {
      // Checkpoint previous epochs

      for (uint32 i = _staked.lastCheckpoint; i < currentEpoch; i++) {
        stakedCheckpoints[_user][i] = _staked.amount;
      }

      _staked.lastCheckpoint = currentEpoch;
    }

    _staked.amount += _amt;
    currentTotalStaked += _amt;

    pls.transferFrom(_user, address(this), _amt);
    emit Staked(_user, _amt, currentEpoch);
  }

  function _unstake(address _user, address _to) internal {
    require(lockDuration == 0 || currentEpoch > lockDuration - 1, 'Locked');

    StakedDetails storage _staked = stakedDetails[_user];

    uint112 deposited = _staked.amount;

    require(deposited > 0, '!Staked');

    if (_staked.lastCheckpoint != currentEpoch) {
      // Checkpoint previous epochs

      for (uint32 i = _staked.lastCheckpoint; i < currentEpoch; i++) {
        stakedCheckpoints[_user][i] = deposited;
      }

      _staked.lastCheckpoint = currentEpoch;
    }

    _staked.amount = 0;
    currentTotalStaked -= deposited;

    pls.transfer(_to, deposited);
    emit Unstaked(_user, deposited, currentEpoch);
  }

  function _claimRewards(
    uint32 _epoch,
    address _user,
    address _to
  ) internal {
    uint32 _currentEpoch = currentEpoch;
    require(_epoch < _currentEpoch, 'Epoch !Ended');

    StakedDetails storage _staked = stakedDetails[_user];
    if (_staked.lastCheckpoint != _currentEpoch) {
      // Checkpoint previous epochs

      for (uint32 i = _staked.lastCheckpoint; i < _currentEpoch; i++) {
        stakedCheckpoints[_user][i] = _staked.amount;
      }

      _staked.lastCheckpoint = _currentEpoch;
    }

    stakingRewards.claimRewardsFor(_epoch, _currentEpoch, _user, _to);

    emit ClaimedRewards(_user, _epoch);
  }

  /** OPERATOR FUNCTIONS */
  function stakeFor(uint112 _amt, address _user) external onlyOwnerOrOperator {
    _stake(_amt, _user);
  }

  function unstakeFor(address _user, address _to) external onlyOwnerOrOperator {
    _unstake(_user, _to);
  }

  function claimRewardsFor(
    uint32 _epoch,
    address _user,
    address _to
  ) external onlyOwnerOrOperator {
    _claimRewards(_epoch, _user, _to);
  }

  function advanceEpoch() external onlyOwnerOrOperator {
    epochCheckpoints[currentEpoch] = EpochCheckpoint({
      startedAt: currentEpochStartedAt,
      endedAt: uint32(block.timestamp),
      totalStaked: currentTotalStaked
    });

    currentEpoch += 1;
    currentEpochStartedAt = uint32(block.timestamp);

    if (lockDuration == 0 || currentEpoch > lockDuration - 1) {
      openStakingWindow();
    }

    emit AdvanceEpoch();
  }

  function setCurrentEpochStart(uint32 _timestamp) public onlyOwnerOrOperator {
    currentEpochStartedAt = _timestamp;
  }

  function init() external onlyOwnerOrOperator {
    setCurrentEpochStart(uint32(block.timestamp));
    _unpause();
    openStakingWindow();
  }

  function closeStakingWindow() public onlyOwnerOrOperator {
    stakingWindowOpen = false;
  }

  function openStakingWindow() public onlyOwnerOrOperator {
    stakingWindowOpen = true;
  }

  function setWhitelist(address _whitelist) external onlyOwnerOrOperator {
    whitelist = IWhitelist(_whitelist);
  }

  function pause() external onlyOwnerOrOperator {
    _pause();
  }

  function unpause() external onlyOwnerOrOperator {
    _unpause();
  }

  /** GOVERNANCE FUNCTIONS */
  function setOperator(address _operator) public onlyOwner {
    address _old = operator;
    operator = _operator;
    emit OperatorChange(_operator, _old);
  }

  function setRewards(address _stakingRewards) public onlyOwner {
    stakingRewards = IStakingRewards(_stakingRewards);
  }

  event AdvanceEpoch();
  event OperatorChange(address indexed _to, address indexed _from);
  event Staked(address indexed _from, uint112 _amt, uint32 _epoch);
  event Unstaked(address indexed _from, uint112 _amt, uint32 _epoch);
  event ClaimedRewards(address indexed _user, uint32 _epoch);
}


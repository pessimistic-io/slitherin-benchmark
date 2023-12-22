// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AddressUpgradeable.sol";

import "./IERC20MintableBurnableUpgradeable.sol";
import "./IKommunitasStakingV3.sol";
import "./AdminProxyManager.sol";
import "./OwnableUpgradeable.sol";

contract KommunitasStakingV3 is
  Initializable,
  UUPSUpgradeable,
  OwnableUpgradeable,
  PausableUpgradeable,
  AdminProxyManager,
  IKommunitasStakingV3
{
  using SafeERC20Upgradeable for IERC20MintableBurnableUpgradeable;

  uint256 private constant yearInSeconds = 365 * 86400;

  uint64 public minStaking;
  uint64 public minPrivatePartner;
  uint64 public minGetKomV; // min kom staked to receive komVToken

  uint16 public minLockIndexGetGiveaway; // min lock index to be choosen to join free token giveaway
  uint16 public lockNumber;
  uint32 public workerNumber;

  uint256 public giveawayStakedAmount;
  uint256 public privatePartnerStakedAmount;

  address[] public staker;

  address public komToken; // Kommunitas Token
  address public komVToken; // Kommunitas Voting Token
  address public savior; // who will wd

  enum CompoundTypes {
    NoCompound,
    RewardOnly,
    PrincipalAndReward
  }

  struct Lock {
    uint128 lockPeriodInSeconds;
    uint64 apy_d2;
    uint64 feeInPercent_d2;
    uint256 komStaked;
    uint256 pendingReward;
  }

  struct Stake {
    uint16 lockIndex;
    uint232 userStakedIndex;
    CompoundTypes compoundType;
    uint256 amount;
    uint256 reward;
    uint128 stakedAt;
    uint128 endedAt;
  }

  struct StakeData {
    uint256 stakedAmount;
    uint256 stakerPendingReward;
  }

  mapping(uint16 => Lock) private lock;
  mapping(address => uint232) private stakerIndex;
  mapping(address => Stake[]) private staked;

  mapping(address => StakeData) public stakerDetail;
  mapping(address => bool) public isWorker;
  mapping(address => bool) public isTrustedForwarder;
  mapping(address => bool) public hasKomV;

  /* ========== EVENTS ========== */

  event Staked(
    address indexed stakerAddress,
    uint128 lockPeriodInDays,
    CompoundTypes compoundType,
    uint256 amount,
    uint256 reward,
    uint128 stakedAt,
    uint128 endedAt
  );
  event Unstaked(
    address indexed stakerAddress,
    uint128 lockPeriodInDays,
    CompoundTypes compoundType,
    uint256 amount,
    uint256 reward,
    uint256 prematurePenalty,
    uint128 stakedAt,
    uint128 endedAt,
    uint128 unstakedAt,
    bool isPremature
  );

  function init(
    address _komToken,
    address _komVToken,
    uint128[] calldata _lockPeriodInDays,
    uint64[] calldata _apy_d2,
    uint64[] calldata _feeInPercent_d2,
    address _savior
  ) external initializer proxied {
    __UUPSUpgradeable_init();
    __Pausable_init();
    __Ownable_init();
    __AdminProxyManager_init(_msgSender());

    require(
      _lockPeriodInDays.length == _apy_d2.length &&
        _lockPeriodInDays.length == _feeInPercent_d2.length &&
        AddressUpgradeable.isContract(_komToken) &&
        AddressUpgradeable.isContract(_komVToken) &&
        _savior != address(0),
      'misslength'
    );

    komToken = _komToken;
    komVToken = _komVToken;
    lockNumber = uint16(_lockPeriodInDays.length);
    savior = _savior;

    uint16 i = 0;
    do {
      lock[i] = Lock({
        lockPeriodInSeconds: _lockPeriodInDays[i] * 86400,
        apy_d2: _apy_d2[i],
        feeInPercent_d2: _feeInPercent_d2[i],
        komStaked: 0,
        pendingReward: 0
      });

      ++i;
    } while (i < _lockPeriodInDays.length);

    minStaking = 100 * 1e8; // 100 komToken
    minPrivatePartner = 500000 * 1e8; // 500K komToken
    minGetKomV = 3000 * 1e8; // 3K komToken
    minLockIndexGetGiveaway = uint16(_lockPeriodInDays.length - 1); // last lock index
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override proxied {}

  function onlySavior() internal view virtual {
    require(_msgSender() == savior, '!savior');
  }

  function totalPendingReward() external view virtual returns (uint256 total) {
    for (uint16 i = 0; i < lockNumber; ++i) {
      total += lock[i].pendingReward;
    }
  }

  function totalKomStaked() external view virtual returns (uint256 total) {
    for (uint16 i = 0; i < lockNumber; ++i) {
      total += lock[i].komStaked;
    }
  }

  function stakerLength() external view virtual returns (uint256 length) {
    length = staker.length;
  }

  function locked(
    uint16 _lockIndex
  )
    external
    view
    virtual
    returns (uint128 lockPeriodInDays, uint64 apy_d2, uint64 feeInPercent_d2, uint256 komStaked, uint256 pendingReward)
  {
    lockPeriodInDays = lock[_lockIndex].lockPeriodInSeconds / 86400;
    apy_d2 = lock[_lockIndex].apy_d2;
    feeInPercent_d2 = lock[_lockIndex].feeInPercent_d2;
    komStaked = lock[_lockIndex].komStaked;
    pendingReward = lock[_lockIndex].pendingReward;
  }

  function userStakedLength(address _staker) external view virtual returns (uint256 length) {
    length = staked[_staker].length;
  }

  function getStakedDetail(
    address _staker,
    uint232 _userStakedIndex
  )
    external
    view
    virtual
    returns (
      uint128 lockPeriodInDays,
      CompoundTypes compoundType,
      uint256 amount,
      uint256 reward,
      uint256 prematurePenalty,
      uint128 stakedAt,
      uint128 endedAt
    )
  {
    // get stake data
    Stake memory stakeDetail = staked[_staker][_userStakedIndex];

    lockPeriodInDays = lock[stakeDetail.lockIndex].lockPeriodInSeconds / 86400;
    compoundType = stakeDetail.compoundType;
    amount = stakeDetail.amount;
    reward = stakeDetail.reward;
    prematurePenalty = (stakeDetail.amount * lock[stakeDetail.lockIndex].feeInPercent_d2) / 10000;
    stakedAt = stakeDetail.stakedAt;
    endedAt = stakeDetail.endedAt;
  }

  function getTotalWithdrawableTokens(address _staker) external view virtual returns (uint256 withdrawableTokens) {
    for (uint232 i = 0; i < staked[_staker].length; ++i) {
      if (staked[_staker][i].endedAt < block.timestamp) {
        withdrawableTokens += staked[_staker][i].amount + staked[_staker][i].reward;
      }
    }
  }

  function getTotalLockedTokens(address _staker) external view virtual returns (uint256 lockedTokens) {
    for (uint232 i = 0; i < staked[_staker].length; ++i) {
      if (staked[_staker][i].endedAt >= block.timestamp) {
        lockedTokens += staked[_staker][i].amount + staked[_staker][i].reward;
      }
    }
  }

  function getUserNextUnlock(
    address _staker
  ) external view virtual returns (uint128 nextUnlockTime, uint256 nextUnlockRewards) {
    for (uint232 i = 0; i < staked[_staker].length; ++i) {
      Stake memory stakeDetail = staked[_staker][i];
      if (stakeDetail.endedAt >= block.timestamp) {
        if (nextUnlockTime == 0 || nextUnlockTime > stakeDetail.endedAt) {
          nextUnlockTime = stakeDetail.endedAt;
          nextUnlockRewards = stakeDetail.reward;
        }
      }
    }
  }

  function getUserStakedGiveawayEligibleBeforeDate(
    address _staker,
    uint128 _beforeAt
  ) external view virtual returns (uint256 lockedTokens) {
    for (uint232 i = 0; i < staked[_staker].length; ++i) {
      Stake memory stakeDetail = staked[_staker][i];
      if (stakeDetail.lockIndex >= minLockIndexGetGiveaway && stakeDetail.stakedAt <= _beforeAt) {
        lockedTokens += stakeDetail.amount;
      }
    }
  }

  function getUserStakedTokensBeforeDate(
    address _staker,
    uint128 _beforeAt
  ) external view virtual returns (uint256 lockedTokens) {
    for (uint232 i = 0; i < staked[_staker].length; ++i) {
      Stake memory stakeDetail = staked[_staker][i];
      if (stakeDetail.stakedAt <= _beforeAt) {
        lockedTokens += stakeDetail.amount;
      }
    }
  }

  function getTotalStakedAmountBeforeDate(uint128 _beforeAt) external view virtual returns (uint256 totalStaked) {
    for (uint256 i = 0; i < staker.length; ++i) {
      for (uint232 j = 0; j < staked[staker[i]].length; ++j) {
        if (staked[staker[i]][j].stakedAt <= _beforeAt) {
          totalStaked += staked[staker[i]][j].amount;
        }
      }
    }
  }

  function calculateReward(uint256 _amount, uint16 _lockIndex) public view virtual returns (uint256 reward) {
    Lock memory lockDetail = lock[_lockIndex];

    uint256 effectiveAPY = lockDetail.apy_d2 * lockDetail.lockPeriodInSeconds;
    reward = (_amount * effectiveAPY) / (yearInSeconds * 10000);
  }

  function stake(uint256 _amount, uint16 _lockIndex, CompoundTypes _compoundType) external virtual whenNotPaused {
    require(
      _amount >= minStaking, // validate min amount to stake
      '<min'
    );

    // fetch sender
    address sender = _msgSender();

    // push staker if eligible
    if (staked[sender].length == 0) {
      staker.push(sender);
      stakerIndex[sender] = uint232(staker.length - 1);
    }

    // stake
    _stake(sender, _amount, _lockIndex, _compoundType);

    // take out komToken
    IERC20MintableBurnableUpgradeable(komToken).safeTransferFrom(sender, address(this), _amount);
  }

  function unstake(uint232 _userStakedIndex, uint256 _amount, address _staker) public virtual {
    // worker check
    if (isWorker[_msgSender()]) {
      require(block.timestamp > staked[_staker][_userStakedIndex].endedAt, 'premature');
    } else {
      _staker = _msgSender();
    }

    // validate existance of staker stake index
    require(staked[_staker].length > _userStakedIndex, 'bad');

    // get stake data
    Stake memory stakeDetail = staked[_staker][_userStakedIndex];

    if (block.timestamp > stakeDetail.endedAt) {
      _amount = stakeDetail.amount;
      // compound
      _compound(_staker, _amount, stakeDetail.lockIndex, stakeDetail.compoundType);
    } else {
      if (stakeDetail.amount > _amount) {
        uint256 remainderAmount = stakeDetail.amount - _amount;

        // stake remainder
        _stake(_staker, remainderAmount, stakeDetail.lockIndex, stakeDetail.compoundType);

        // adjust new staking amount to be partially withdrawn
        uint256 newPartialReward = calculateReward(_amount, stakeDetail.lockIndex);
        staked[_staker][_userStakedIndex].amount = _amount;
        staked[_staker][_userStakedIndex].reward = newPartialReward;

        // subtract staked amount & pending reward to staker
        stakerDetail[_staker].stakedAmount -= remainderAmount;
        stakerDetail[_staker].stakerPendingReward -= (stakeDetail.reward - newPartialReward);

        // subtract komStaked & pending reward to lock index
        lock[stakeDetail.lockIndex].komStaked -= remainderAmount;
        lock[stakeDetail.lockIndex].pendingReward -= (stakeDetail.reward - newPartialReward);

        // subtract to private if eligible
        if (stakeDetail.amount >= minPrivatePartner) privatePartnerStakedAmount -= stakeDetail.amount;
        if (_amount >= minPrivatePartner) privatePartnerStakedAmount += _amount;

        // subtract to giveaway if eligible
        if (stakeDetail.lockIndex >= minLockIndexGetGiveaway) giveawayStakedAmount -= remainderAmount;
      }
    }

    // unstake
    _unstake(_staker, _userStakedIndex, stakeDetail.endedAt >= block.timestamp);
  }

  function changeCompoundType(uint232 _userStakedIndex, CompoundTypes _newCompoundType) external virtual {
    // owner validation
    address _staker = _msgSender();

    // get stake data
    Stake memory stakeDetail = staked[_staker][_userStakedIndex];

    require(
      staked[_staker].length > _userStakedIndex && // user staked index validation
        stakeDetail.compoundType != _newCompoundType, // compound type validation
      'bad'
    );

    // assign new compound type
    staked[_staker][_userStakedIndex].compoundType = _newCompoundType;
  }

  function _stake(address _sender, uint256 _amount, uint16 _lockIndex, CompoundTypes _compoundType) internal virtual {
    require(
      _lockIndex < lockNumber, // validate existance of lock index
      '!lockIndex'
    );

    // calculate reward
    uint256 reward = calculateReward(_amount, _lockIndex);

    // add staked amount & pending reward to sender
    stakerDetail[_sender].stakedAmount += _amount;
    stakerDetail[_sender].stakerPendingReward += reward;

    // add komStaked & pending reward to lock index
    lock[_lockIndex].komStaked += _amount;
    lock[_lockIndex].pendingReward += reward;

    // add to private if eligible
    if (_amount >= minPrivatePartner) privatePartnerStakedAmount += _amount;

    // add to giveaway if eligible
    if (_lockIndex >= minLockIndexGetGiveaway) giveawayStakedAmount += _amount;

    // push stake struct to staked mapping
    staked[_sender].push(
      Stake({
        lockIndex: _lockIndex,
        userStakedIndex: uint232(staked[_sender].length),
        compoundType: _compoundType,
        amount: _amount,
        reward: reward,
        stakedAt: uint128(block.timestamp),
        endedAt: uint128(block.timestamp) + lock[_lockIndex].lockPeriodInSeconds
      })
    );

    // mint komVToken if eligible
    if (
      stakerDetail[_sender].stakedAmount >= minGetKomV &&
      IERC20MintableBurnableUpgradeable(komVToken).balanceOf(_sender) == 0
    ) {
      IERC20MintableBurnableUpgradeable(komVToken).mint(_sender, 1);
      if (!hasKomV[_sender]) hasKomV[_sender] = true;
    }

    // emit staked event
    emit Staked(
      _sender,
      lock[_lockIndex].lockPeriodInSeconds / 86400,
      _compoundType,
      _amount,
      reward,
      uint128(block.timestamp),
      uint128(block.timestamp) + lock[_lockIndex].lockPeriodInSeconds
    );
  }

  function _compound(
    address _sender,
    uint256 _amount,
    uint16 _lockIndex,
    CompoundTypes _compoundType
  ) internal virtual {
    if (_compoundType == CompoundTypes.RewardOnly) {
      _stake(_sender, _amount, _lockIndex, _compoundType);
    } else if (_compoundType == CompoundTypes.PrincipalAndReward) {
      uint256 reward = calculateReward(_amount, _lockIndex);
      _stake(_sender, _amount + reward, _lockIndex, _compoundType);
    }
  }

  function _unstake(address _sender, uint232 _userStakedIndex, bool _isPremature) internal virtual {
    // get stake data
    Stake memory stakeDetail = staked[_sender][_userStakedIndex];

    // subtract staked amount & pending reward to sender
    stakerDetail[_sender].stakedAmount -= stakeDetail.amount;
    stakerDetail[_sender].stakerPendingReward -= stakeDetail.reward;

    // subtract komStaked & pending reward to lock index
    lock[stakeDetail.lockIndex].komStaked -= stakeDetail.amount;
    lock[stakeDetail.lockIndex].pendingReward -= stakeDetail.reward;

    // subtract to private if eligible
    if (stakeDetail.amount >= minPrivatePartner) privatePartnerStakedAmount -= stakeDetail.amount;

    // subtract to giveaway if eligible
    if (stakeDetail.lockIndex >= minLockIndexGetGiveaway) giveawayStakedAmount -= stakeDetail.amount;

    // shifts struct from lastIndex to currentIndex & pop lastIndex from staked mapping
    staked[_sender][_userStakedIndex] = staked[_sender][staked[_sender].length - 1];
    staked[_sender][_userStakedIndex].userStakedIndex = _userStakedIndex;
    staked[_sender].pop();

    // remove staker if eligible
    if (staked[_sender].length == 0 && staker[stakerIndex[_sender]] == _sender) {
      uint232 indexToDelete = stakerIndex[_sender];
      address stakerToMove = staker[staker.length - 1];

      staker[indexToDelete] = stakerToMove;
      stakerIndex[stakerToMove] = indexToDelete;

      delete stakerIndex[_sender];
      staker.pop();
    }

    // burn komVToken if eligible
    if (
      stakerDetail[_sender].stakedAmount < minGetKomV &&
      IERC20MintableBurnableUpgradeable(komVToken).balanceOf(_sender) > 0
    ) {
      _burnToken(komVToken, _sender, 1);
      if (hasKomV[_sender]) hasKomV[_sender] = false;
    }

    // set withdrawable amount to transfer
    uint256 withdrawableAmount = stakeDetail.amount + stakeDetail.reward;

    if (_isPremature) {
      // calculate penalty & staked amount to withdraw
      uint256 penaltyAmount = (stakeDetail.amount * lock[stakeDetail.lockIndex].feeInPercent_d2) / 10000;
      withdrawableAmount = stakeDetail.amount - penaltyAmount;

      // burn penalty
      _burnToken(komToken, address(this), penaltyAmount);
    } else {
      if (stakeDetail.compoundType == CompoundTypes.RewardOnly) {
        withdrawableAmount = stakeDetail.reward;
      } else if (stakeDetail.compoundType == CompoundTypes.PrincipalAndReward) {
        emitUnstaked(
          _sender,
          lock[stakeDetail.lockIndex].lockPeriodInSeconds / 86400,
          stakeDetail.compoundType,
          stakeDetail.amount,
          stakeDetail.reward,
          0,
          stakeDetail.stakedAt,
          stakeDetail.endedAt,
          _isPremature
        );
        return;
      }
    }

    // send staked + reward to sender
    IERC20MintableBurnableUpgradeable(komToken).safeTransfer(_sender, withdrawableAmount);

    // emit unstaked event
    emitUnstaked(
      _sender,
      lock[stakeDetail.lockIndex].lockPeriodInSeconds / 86400,
      stakeDetail.compoundType,
      stakeDetail.amount,
      stakeDetail.reward,
      _isPremature ? (stakeDetail.amount * lock[stakeDetail.lockIndex].feeInPercent_d2) / 10000 : 0,
      stakeDetail.stakedAt,
      stakeDetail.endedAt,
      _isPremature
    );
  }

  function emitUnstaked(
    address _stakerAddress,
    uint128 _lockPeriodInDays,
    CompoundTypes _compoundType,
    uint256 _amount,
    uint256 _reward,
    uint256 _penaltyPremature,
    uint128 _stakedAt,
    uint128 _endedAt,
    bool _isPremature
  ) internal virtual {
    emit Unstaked(
      _stakerAddress,
      _lockPeriodInDays,
      _compoundType,
      _amount,
      _reward,
      _penaltyPremature,
      _stakedAt,
      _endedAt,
      uint128(block.timestamp),
      _isPremature
    );
  }

  function _msgSender() internal view virtual override returns (address sender) {
    if (isTrustedForwarder[msg.sender]) {
      // The assembly code is more direct than the Solidity version using `abi.decode`.
      /// @solidity memory-safe-assembly
      assembly {
        sender := shr(96, calldataload(sub(calldatasize(), 20)))
      }
    } else {
      return super._msgSender();
    }
  }

  function _msgData() internal view virtual override returns (bytes calldata) {
    if (isTrustedForwarder[msg.sender]) {
      return msg.data[:msg.data.length - 20];
    } else {
      return super._msgData();
    }
  }

  function addWorker(address _worker) external virtual onlyOwner {
    require(_worker != address(0) && !isWorker[_worker], 'bad');
    isWorker[_worker] = true;
    ++workerNumber;
  }

  function removeWorker(address _worker) external virtual onlyOwner {
    require(_worker != address(0) && isWorker[_worker], 'bad');
    isWorker[_worker] = false;
    --workerNumber;
  }

  function changeWorker(address _oldWorker, address _newWorker) external virtual onlyOwner {
    require(
      _oldWorker != address(0) && _newWorker != address(0) && isWorker[_oldWorker] && !isWorker[_newWorker],
      'bad'
    );
    isWorker[_oldWorker] = false;
    isWorker[_newWorker] = true;
  }

  function toggleTrustedForwarder(address _forwarder) external virtual onlyOwner {
    require(_forwarder != address(0), '0x0');
    isTrustedForwarder[_forwarder] = !isTrustedForwarder[_forwarder];
  }

  function setMin(
    uint64 _minStaking,
    uint64 _minPrivatePartner,
    uint64 _minGetKomV,
    uint16 _minLockIndexGetGiveaway
  ) external virtual whenPaused onlyOwner {
    if (_minStaking > 0) minStaking = _minStaking;
    if (_minPrivatePartner > 0) {
      minPrivatePartner = _minPrivatePartner;
      privatePartnerStakedAmount = 0; // reset private partner total staked amount
    }
    if (_minGetKomV > 0) minGetKomV = _minGetKomV;
    if (_minLockIndexGetGiveaway > 0) {
      minLockIndexGetGiveaway = _minLockIndexGetGiveaway;
      giveawayStakedAmount = 0; // reset giveaway total staked amount
    }

    // unpause
    _unpause();
  }

  function setPeriodInDays(uint16 _lockIndex, uint128 _newLockPeriodInDays) external virtual onlyOwner {
    require(
      lockNumber > _lockIndex && _newLockPeriodInDays >= 86400 && _newLockPeriodInDays <= (5 * yearInSeconds),
      'bad'
    );
    lock[_lockIndex].lockPeriodInSeconds = _newLockPeriodInDays * 86400;
  }

  function setPenaltyFee(uint16 _lockIndex, uint64 _feeInPercent_d2) external virtual onlyOwner {
    require(lockNumber > _lockIndex && _feeInPercent_d2 >= 100 && _feeInPercent_d2 < 10000, 'bad');
    lock[_lockIndex].feeInPercent_d2 = _feeInPercent_d2;
  }

  function setAPY(uint16 _lockIndex, uint64 _apy_d2) external virtual onlyOwner {
    require(lockNumber > _lockIndex && _apy_d2 < 10000, 'bad');
    lock[_lockIndex].apy_d2 = _apy_d2;
  }

  function setSavior(address _savior) external virtual {
    require(_savior != address(0), '0x0');
    onlySavior();
    savior = _savior;
  }

  function togglePause() external virtual onlyOwner {
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  function emergencyWithdraw(address _token, uint256 _amount, address _receiver) external virtual {
    onlySavior();

    // adjust amount to wd
    uint256 balance = IERC20Upgradeable(_token).balanceOf(address(this));
    if (_amount > balance) _amount = balance;

    IERC20MintableBurnableUpgradeable(_token).safeTransfer(_receiver, _amount);
  }

  function getStakerIndex(address _staker) external view virtual returns (uint232) {
    return stakerIndex[_staker];
  }

  function insertIntoArray(address[] calldata _users) external virtual onlyOwner {
    // push staker if eligible
    for (uint8 i = 0; i < _users.length; ++i) {
      if (
        staker[stakerIndex[_users[i]]] == _users[i] ||
        (staker[stakerIndex[_users[i]]] != _users[i] && staked[_users[i]].length == 0)
      ) continue;

      staker.push(_users[i]);
      stakerIndex[_users[i]] = uint232(staker.length - 1);
    }
  }

  function assignNewLockDataValue(
    uint16 _lockIndex,
    uint256 _komStaked,
    uint256 _pendingReward
  ) external virtual onlyOwner {
    require(_lockIndex < lockNumber, '!index');

    lock[_lockIndex].komStaked = _komStaked;
    lock[_lockIndex].pendingReward = _pendingReward;
  }

  function _burnToken(address _token, address _account, uint256 _amount) internal {
    (bool success1, ) = _token.call(abi.encodeWithSignature('burn(uint256)', _amount));
    if (!success1) {
      (bool success2, ) = _token.call(abi.encodeWithSignature('burn(address,uint256)', _account, _amount));
      if (!success2) {
        (bool success3, ) = _token.call(abi.encodeWithSignature('burnFrom(address,uint256)', _account, _amount));
        require(success3, '!burnToken');
      }
    }
  }
}


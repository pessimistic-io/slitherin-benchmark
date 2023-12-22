// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./IPlutusEpochStakingV2.sol";
import { ISpaStakerGaugeHandler } from "./GaugeInterfaces.sol";

interface IBribeDistro {
  struct BribeReward {
    address token;
    uint96 amount;
  }

  event BribeRewardsClaimed(
    address indexed user,
    uint indexed bribeEpoch,
    uint indexed stakeEpoch,
    uint userStaked,
    uint epochTotalStaked,
    BribeReward[] rewardInfo
  );

  event RewardsReady(uint indexed bribeEpoch, uint indexed stakeEpoch, BribeReward[] rewardInfo);

  error FAILED(string reason);
}

contract BribeDistro is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, PausableUpgradeable, IBribeDistro {
  IPlutusEpochStakingV2 public constant PLUTUS_EPOCH_STAKER =
    IPlutusEpochStakingV2(0x27Aaa9D562237BF8E024F9b21DE177e20ae50c05);

  ISpaStakerGaugeHandler public constant SPA_STAKER =
    ISpaStakerGaugeHandler(0x46ac70bf830896EEB2a2e4CBe29cD05628824928);

  uint public constant FIRST_BRIBE_EPOCH = 1;
  uint public currentBribeEpoch;

  mapping(uint => uint) public bribeStakeEpochLookup; // bribeEpoch => stakeEpoch

  mapping(uint => BribeReward[]) public bribeRewards; // bribeEpoch => [{token, amount}]

  mapping(uint => mapping(address => bool)) public hasClaimedRewards; // bribeEpoch => wallet => bool

  mapping(address => mapping(uint => BribeReward[])) public claimedRewards; // wallet => bribeEpoch => BribeReward

  mapping(address => bool) public migrated;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
    __Pausable_init();
    currentBribeEpoch = FIRST_BRIBE_EPOCH; // bribe epoch starts from 1;
  }

  function getBribeRewardsForEpoch(uint _bribeEpoch) external view returns (BribeReward[] memory) {
    return bribeRewards[_bribeEpoch];
  }

  function getClaimedRewardsForBribeEpoch(
    address _user,
    uint _bribeEpoch
  ) external view returns (BribeReward[] memory) {
    return claimedRewards[_user][_bribeEpoch];
  }

  function pendingRewardsForBribeEpoch(
    address _user,
    uint _bribeEpoch
  ) external view returns (uint _stakeEpoch, BribeReward[] memory rewards) {
    _stakeEpoch = bribeStakeEpochLookup[_bribeEpoch];
    rewards = new BribeReward[](0);

    if (
      _bribeEpoch >= 1 &&
      _bribeEpoch <= currentBribeEpoch &&
      bribeRewards[_bribeEpoch].length > 0 &&
      hasClaimedRewards[_bribeEpoch][_user] == false
    ) {
      (rewards, , ) = _calculateRewards(_user, _bribeEpoch, _stakeEpoch);
    }
  }

  function claimRewards(uint _bribeEpoch) external whenNotPaused {
    if (_bribeEpoch < 1 || _bribeEpoch > currentBribeEpoch) revert FAILED('Invalid Epoch');

    // Check if rewards already registered
    if (bribeRewards[_bribeEpoch].length == 0) revert FAILED('No rewards for bribe epoch');

    if (hasClaimedRewards[_bribeEpoch][msg.sender] == true) revert FAILED('Already claimed');

    _claimRewards(msg.sender, _bribeEpoch);
  }

  function claimAllRewards() external whenNotPaused {
    for (uint i = FIRST_BRIBE_EPOCH; i < currentBribeEpoch; i++) {
      // Check if user already claimed the bribe epoch rewards
      if (hasClaimedRewards[i][msg.sender] == true) continue;
      // Check if rewards registered
      if (bribeRewards[i].length == 0) continue;

      _claimRewards(msg.sender, i);
    }
  }

  function recalculateRewards() external whenNotPaused {
    _recalculateRewards(msg.sender);
  }

  function _claimRewards(address _user, uint _bribeEpoch) internal {
    hasClaimedRewards[_bribeEpoch][_user] = true;

    uint _stakeEpoch = bribeStakeEpochLookup[_bribeEpoch];

    (BribeReward[] memory _userBribeRewardsArr, uint _userStaked, uint _totalStaked) = _calculateRewards(
      _user,
      _bribeEpoch,
      _stakeEpoch
    );

    for (uint i; i < _userBribeRewardsArr.length; i = _unsafeInc(i)) {
      claimedRewards[_user][_bribeEpoch].push(_userBribeRewardsArr[i]);
      // Transfer tokens to user
      _safeTokenTransfer(IERC20(_userBribeRewardsArr[i].token), _user, _userBribeRewardsArr[i].amount);
    }

    emit BribeRewardsClaimed(_user, _bribeEpoch, _stakeEpoch, _userStaked, _totalStaked, _userBribeRewardsArr);
  }

  function _calculateRewards(
    address _user,
    uint _bribeEpoch,
    uint _stakeEpoch
  ) private view returns (BribeReward[] memory _userBribeRewardsArr, uint _userStaked, uint _totalStaked) {
    uint _currentStakingEpoch = PLUTUS_EPOCH_STAKER.currentEpoch();
    uint32 _lastCheckpoint;
    (_userStaked, _lastCheckpoint) = PLUTUS_EPOCH_STAKER.stakedDetails(_user);

    if (_stakeEpoch == _currentStakingEpoch) {
      _totalStaked = PLUTUS_EPOCH_STAKER.currentTotalStaked();
    } else if (_stakeEpoch < _currentStakingEpoch) {
      // we are in past epoch
      // but stakedCheckpoints does not get updated if user did not call claimRewards/stake/unstake
      // we will use the last checkpoint to calculate the user share if last checkpoint is <= stakeEpoch
      // But if last checkpoint is > stakeEpoch, we will use the stakedCheckpoints to query the user staked amount
      if (_lastCheckpoint > _stakeEpoch) {
        _userStaked = PLUTUS_EPOCH_STAKER.stakedCheckpoints(_user, uint32(_stakeEpoch));
      }

      (, , _totalStaked) = PLUTUS_EPOCH_STAKER.epochCheckpoints(uint32(_stakeEpoch));
    } else {
      revert FAILED('Unreachable');
    }

    if (_userStaked > 0) {
      BribeReward[] memory _bribeRewardsArr = bribeRewards[_bribeEpoch];

      _userBribeRewardsArr = new BribeReward[](_bribeRewardsArr.length);

      for (uint i; i < _bribeRewardsArr.length; i = _unsafeInc(i)) {
        address _token = _bribeRewardsArr[i].token;
        uint _totalTokenReward = _bribeRewardsArr[i].amount;
        // calculate share and distribute

        uint _userShare = _calculateShare(_userStaked, _totalStaked, _totalTokenReward);

        if (_userShare > type(uint96).max) revert FAILED('Invalid amount');

        _userBribeRewardsArr[i] = BribeReward({ token: _token, amount: uint96(_userShare) });
      }
    } else {
      _userBribeRewardsArr = new BribeReward[](0);
    }
  }

  function _recalculateRewards(address _user) internal {
    if (migrated[_user]) {
      return;
    }

    migrated[_user] = true;

    uint bEpoch = 4; // migrate bribe epoch 1-3

    for (uint i = 1; i < bEpoch; i = _unsafeInc(i)) {
      uint _stakeEpoch = bribeStakeEpochLookup[i];
      if (hasClaimedRewards[i][_user] == true && claimedRewards[_user][i].length == 0) {
        (BribeReward[] memory _userBribeRewardsArr, , ) = _calculateRewards(_user, i, _stakeEpoch);

        // We use the correct _calculateRewards function to calculate the rewards
        // if rewards length is > 0, that means we have rewards that has not been claimed
        // i.e. claimedRewards[_user][i].length should not be 0
        if (_userBribeRewardsArr.length > 0) {
          hasClaimedRewards[i][_user] = false;
        }
      }
    }
  }

  function _calculateShare(
    uint _userStaked,
    uint _totalStaked,
    uint _totalBribeEpochTokenReward
  ) private pure returns (uint) {
    unchecked {
      return (_userStaked * _totalBribeEpochTokenReward) / _totalStaked;
    }
  }

  function _unsafeInc(uint x) private pure returns (uint) {
    unchecked {
      return x + 1;
    }
  }

  function _safeTokenTransfer(IERC20 _token, address _to, uint _amount) private {
    uint bal = _token.balanceOf(address(this));

    if (_amount > bal) {
      _token.transfer(_to, bal);
    } else {
      _token.transfer(_to, _amount);
    }
  }

  /** GOVERNANCE FUNCTIONS */

  /// @dev Claim and register bribe rewards to currentStakingEpoch
  function transferAndRegisterRewards() external onlyOwner {
    if (PLUTUS_EPOCH_STAKER.stakingWindowOpen()) {
      revert FAILED('Staking window != closed');
    }

    uint _currentStakingEpoch = PLUTUS_EPOCH_STAKER.currentEpoch();

    ISpaStakerGaugeHandler.BribeRewardData[] memory rewardData = SPA_STAKER.claimAndTransferBribes();

    bribeStakeEpochLookup[currentBribeEpoch] = _currentStakingEpoch;
    uint256 _rewardDataLen = rewardData.length;

    for (uint256 i; i < _rewardDataLen; i = _unsafeInc(i)) {
      if (rewardData[i].amount > 0) {
        bribeRewards[currentBribeEpoch].push(
          BribeReward({ token: rewardData[i].token, amount: uint96(rewardData[i].amount) })
        );
      }
    }

    emit RewardsReady(currentBribeEpoch, _currentStakingEpoch, bribeRewards[currentBribeEpoch]);
    currentBribeEpoch = _unsafeInc(currentBribeEpoch);
  }

  function registerRewardsWithBribeEpochAndStakeEpoch(
    uint32 _stakeEpoch,
    address[] calldata _tokens,
    uint96[] calldata _amounts
  ) external onlyOwner {
    if (_tokens.length != _amounts.length) revert FAILED('Mismatch');

    if (PLUTUS_EPOCH_STAKER.currentEpoch() == _stakeEpoch && PLUTUS_EPOCH_STAKER.stakingWindowOpen() == true) {
      revert FAILED('Staking window != closed');
    }

    bribeStakeEpochLookup[currentBribeEpoch] = _stakeEpoch;

    for (uint256 i; i < _tokens.length; i = _unsafeInc(i)) {
      bribeRewards[currentBribeEpoch].push(BribeReward({ token: _tokens[i], amount: _amounts[i] }));
    }

    // Emit event
    emit RewardsReady(currentBribeEpoch, _stakeEpoch, bribeRewards[currentBribeEpoch]);

    // increment epoch
    currentBribeEpoch = _unsafeInc(currentBribeEpoch);
  }

  function resetBribeRewards() external onlyOwner {
    uint _fromBribeEpoch = 5;

    //  re-register epoch 5 rewards

    BribeReward[] memory _epoch5Rw = new BribeReward[](7);

    // PLS
    _epoch5Rw[0] = BribeReward({
      token: address(0x51318B7D00db7ACc4026C88c3952B66278B6A67F),
      amount: 4897521994716507277810
    });

    // SPA
    _epoch5Rw[1] = BribeReward({
      token: address(0x5575552988A3A80504bBaeB1311674fCFd40aD4B),
      amount: 291168985216233434826496
    });

    // BFR
    _epoch5Rw[2] = BribeReward({
      token: address(0x1A5B0aaF478bf1FDA7b934c76E7692D722982a6D),
      amount: 5410085800058509930000
    });

    // VELA
    _epoch5Rw[3] = BribeReward({
      token: address(0x088cd8f5eF3652623c22D48b1605DCfE860Cd704),
      amount: 266277587543784436400
    });

    // ROUL
    _epoch5Rw[4] = BribeReward({
      token: address(0xc7831178793868a75122EAaFF634ECe07a2ecAAA),
      amount: 381573644189669003000000
    });

    // L2DAO
    _epoch5Rw[5] = BribeReward({
      token: address(0x2CaB3abfC1670D1a452dF502e216a66883cDf079),
      amount: 588436286744408830000
    });

    // NFTE
    _epoch5Rw[6] = BribeReward({
      token: address(0xB261104A83887aE92392Fb5CE5899fCFe5481456),
      amount: 2942181433722044150000
    });

    BribeReward[] memory _epoch6Rw = bribeRewards[12];

    for (uint i = _fromBribeEpoch; i < currentBribeEpoch; i = _unsafeInc(i)) {
      // reset bribe rewards
      delete bribeRewards[i];
      if (i > 6) {
        delete bribeStakeEpochLookup[i];
      }
    }

    for (uint i = 0; i < _epoch5Rw.length; i = _unsafeInc(i)) {
      bribeRewards[5].push(_epoch5Rw[i]);
    }

    for (uint i = 0; i < _epoch6Rw.length; i = _unsafeInc(i)) {
      bribeRewards[6].push(_epoch6Rw[i]);
    }

    // reset currentBribeEpoch
    currentBribeEpoch = 7;
  }

  function setPause(bool _isPaused) external onlyOwner {
    if (_isPaused) {
      _pause();
    } else {
      _unpause();
    }
  }

  function retrieve(IERC20 erc20, uint amount) external onlyOwner {
    if ((address(this).balance) != 0) {
      payable(owner()).transfer(address(this).balance);
    }

    erc20.transfer(owner(), amount);
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}


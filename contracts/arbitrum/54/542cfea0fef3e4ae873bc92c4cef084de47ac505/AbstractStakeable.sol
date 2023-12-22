// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IMintable.sol";
import "./IStakeable.sol";
import "./Errors.sol";
import "./FixedPoint.sol";
import "./Initializable.sol";
import "./EnumerableSet.sol";
import "./SafeCast.sol";

abstract contract AbstractStakeable is Initializable, IStakeable {
  using FixedPoint for uint256;
  using FixedPoint for int256;
  using SafeCast for uint256;
  using SafeCast for int256;
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @custom:oz-renamed-from stakingPaused
  bool public stakingPaused;

  /// @custom:oz-renamed-from _totalStaked
  uint256 internal _totalStaked;
  EnumerableSet.AddressSet internal _rewardTokens;

  mapping(address => uint256) internal _stakedByStaker;
  mapping(address => mapping(IMintable => uint256))
    internal _balanceBaseByStaker;
  mapping(address => mapping(IMintable => uint256))
    internal _accruedRewardsByStaker;

  event PauseEvent(bool paused);
  event AddRewardTokenEvent(address indexed rewardToken);
  event RemoveRewardTokenEvent(address indexed rewardToken);
  event StakeEvent(
    address indexed sender,
    address indexed user,
    uint256 amount
  );
  event UnstakeEvent(address indexed user, uint256 amount);
  event ClaimEvent(
    address indexed user,
    address indexed rewardToken,
    uint256 claimed
  );

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function __AbstractStakeable_init() internal onlyInitializing {
    stakingPaused = true;
  }

  modifier whenStakingNotPaused() {
    _require(!stakingPaused, Errors.TRADING_PAUSED);
    _;
  }

  // external functions

  function contains(address rewardToken) external view returns (bool) {
    return _rewardTokens.contains(rewardToken);
  }

  function getRewards(
    address staker,
    address rewardToken
  ) external view override returns (uint256) {
    if (!_rewardTokens.contains(rewardToken)) {
      return 0;
    }
    return
      _accruedRewardsByStaker[staker][IMintable(rewardToken)].add(
        _getRewards(staker, IMintable(rewardToken))
      );
  }

  function hasStake(address _user) external view virtual returns (bool) {
    return _stakedByStaker[_user] > 0;
  }

  function getStaked(address _user) external view virtual returns (uint256) {
    return _stakedByStaker[_user];
  }

  function getTotalStaked() external view virtual override returns (uint256) {
    return _totalStaked;
  }

  // @dev to be removed before deployment
  function balanceBaseByStaker(
    address user,
    IMintable token
  ) external view returns (uint256) {
    return _balanceBaseByStaker[user][token];
  }

  function _pauseStaking() internal virtual {
    stakingPaused = true;
    emit PauseEvent(stakingPaused);
  }

  function _unpauseStaking() internal virtual {
    stakingPaused = false;
    emit PauseEvent(stakingPaused);
  }

  function _addRewardToken(IMintable rewardToken) internal virtual {
    _rewardTokens.add(address(rewardToken));
    emit AddRewardTokenEvent(address(rewardToken));
  }

  function _removeRewardToken(IMintable rewardToken) internal virtual {
    _rewardTokens.remove(address(rewardToken));
    emit RemoveRewardTokenEvent(address(rewardToken));
  }

  function _update(address staker, int256 stakedDelta) internal virtual {
    uint256 oldStaked = _stakedByStaker[staker];
    uint256 newStaked = oldStaked.add(stakedDelta).toUint256();
    uint256 _length = _rewardTokens.length();
    for (uint256 i = 0; i < _length; ++i) {
      IMintable rewardToken = IMintable(_rewardTokens.at(i));

      uint256 accruedRewards = _getRewards(staker, rewardToken);

      // simulate out
      uint256 balanceOut = accruedRewards.add(
        _balanceBaseByStaker[staker][rewardToken]
      );
      uint256 newTotalStaked = _totalStaked.sub(oldStaked);
      rewardToken.removeBalance(balanceOut);

      // simulate in
      uint256 balanceIn = rewardToken.balance();
      if (newTotalStaked > 0) {
        balanceIn = balanceIn.mulDown(newStaked).divDown(newTotalStaked);
      }
      rewardToken.addBalance(balanceIn);

      _balanceBaseByStaker[staker][rewardToken] = balanceIn;

      // update accrued rewards
      _accruedRewardsByStaker[staker][rewardToken] = _accruedRewardsByStaker[
        staker
      ][rewardToken].add(accruedRewards);
    }
    _stakedByStaker[staker] = newStaked;
    _totalStaked = _totalStaked.add(stakedDelta).toUint256();
  }

  function _getRewards(
    address staker,
    IMintable _rewardToken
  ) internal view virtual returns (uint256) {
    if (_totalStaked == 0) {
      return 0;
    }
    uint256 newBal = _rewardToken
      .balance()
      .mulDown(_stakedByStaker[staker])
      .divDown(_totalStaked);
    if (newBal <= _balanceBaseByStaker[staker][_rewardToken]) {
      return 0;
    }
    return newBal.sub(_balanceBaseByStaker[staker][_rewardToken]);
  }

  function _claim(address staker) internal virtual {
    uint256 _length = _rewardTokens.length();
    for (uint256 i = 0; i < _length; ++i) {
      _claim(staker, _rewardTokens.at(i));
    }
  }

  function _claim(address staker, address rewardToken) internal virtual {
    _require(_rewardTokens.contains(rewardToken), Errors.INVALID_REWARD_TOKEN);
    _update(staker, 0);
    IMintable _rewardToken = IMintable(rewardToken);
    uint256 claimed = _accruedRewardsByStaker[staker][_rewardToken];
    delete _accruedRewardsByStaker[staker][_rewardToken];
    if (claimed > 0) {
      _rewardToken.mint(staker, claimed);
    }
    emit ClaimEvent(staker, rewardToken, claimed);
  }

  function _stake(address staker, uint256 amount) internal virtual;

  function _unstake(address staker, uint256 amount) internal virtual;
}


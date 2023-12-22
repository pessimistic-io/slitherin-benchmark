// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IMintableBurnable.sol";
import "./IVestable.sol";
import "./Errors.sol";
import "./ERC20Fixed.sol";
import "./FixedPoint.sol";
import "./ERC20Upgradeable.sol";
import "./EnumerableSet.sol";
import "./SafeCast.sol";

abstract contract AbstractVestable is ERC20Upgradeable, IVestable {
  using FixedPoint for uint256;
  using FixedPoint for int256;
  using SafeCast for uint256;
  using SafeCast for int256;
  using ERC20Fixed for ERC20Upgradeable;
  using EnumerableSet for EnumerableSet.AddressSet;

  bool public vestingPaused;

  address public vestingToken;
  uint256 public vestingSpeed;
  uint256 public vestingRate;

  uint256 internal _totalLocked;

  mapping(address => uint256) public lastVestedByLocker;
  mapping(address => uint256) internal _lockedByLocker;
  mapping(address => uint256) internal _balanceBaseByLocker;
  mapping(address => uint256) internal _accruedVestedByLocker;

  event PauseVestingEvent(bool paused);
  event SetVestingTokenEvent(address indexed vestingToken);
  event LockEvent(address indexed sender, address indexed user, uint256 amount);
  event UnlockEvent(address indexed user, uint256 amount);
  event VestEvent(address indexed user, uint256 vested);
  event SetVestingRateEvent(uint256 vestingRate);
  event SetVestingSpeedEvent(uint256 vestingSpeed);
  event ConvertEvent(address user, uint256 amount);

  modifier whenVestingNotPaused() {
    _require(!vestingPaused, Errors.TRADING_PAUSED);
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function __AbstractVestable_init(
    IMintableBurnable _vestingToken
  ) internal onlyInitializing {
    vestingToken = address(_vestingToken);
    vestingPaused = true;
  }

  // external functions

  function hasLocked(address _user) external view virtual returns (bool) {
    return _lockedByLocker[_user] > 0;
  }

  function getLocked(address _user) external view virtual returns (uint256) {
    return _lockedByLocker[_user];
  }

  function getTotalLocked() external view virtual override returns (uint256) {
    return _totalLocked;
  }

  // internal functions

  function _pauseVesting() internal virtual {
    vestingPaused = true;
    emit PauseVestingEvent(vestingPaused);
  }

  function _unpauseVesting() internal virtual {
    vestingPaused = false;
    emit PauseVestingEvent(vestingPaused);
  }

  function _lock(address locker, uint256 amount) internal {
    _updateVest(locker, amount.toInt256());
    ERC20Upgradeable(this).transferFromFixed(locker, address(this), amount);
    emit LockEvent(locker, locker, amount);
  }

  function _unlock(address locker, uint256 amount) internal {
    _require(_lockedByLocker[locker] >= amount, Errors.INVALID_AMOUNT);
    _updateVest(locker, -amount.toInt256());
    ERC20Upgradeable(this).transferFixed(locker, amount);
    emit UnlockEvent(locker, amount);
  }

  function _vest(address locker) internal virtual {
    _updateVest(locker, 0);
    uint256 vested = _accruedVestedByLocker[locker];
    delete _accruedVestedByLocker[locker];
    if (vested > 0) IMintableBurnable(vestingToken).mint(locker, vested);
    emit VestEvent(locker, vested);
  }

  function _convert(address user, uint256 amount) internal {
    IMintableBurnable _vestingToken = IMintableBurnable(vestingToken);
    _require(_vestingToken.balanceOf(user) >= amount, Errors.INVALID_AMOUNT);
    _vestingToken.burnFrom(user, amount);
    _mint(user, amount);

    emit ConvertEvent(user, amount);
  }

  function _setVestingToken(IMintableBurnable _vestingToken) internal {
    vestingToken = address(_vestingToken);
    emit SetVestingTokenEvent(address(vestingToken));
  }

  function _setVestingSpeed(uint256 _vestingSpeed) internal {
    vestingSpeed = _vestingSpeed;
    emit SetVestingSpeedEvent(vestingSpeed);
  }

  function _setVestingRate(uint256 _vestingRate) internal {
    vestingRate = _vestingRate;
    emit SetVestingRateEvent(vestingRate);
  }

  function _updateVest(address locker, int256 lockedDelta) internal {
    if (lastVestedByLocker[locker] == 0) {
      lastVestedByLocker[locker] = block.number;
    }

    uint256 vested = _getVested(locker);

    _accruedVestedByLocker[locker] = _accruedVestedByLocker[locker].add(
      vested.mulDown(vestingRate)
    );

    uint256 _locked = _lockedByLocker[locker];

    _totalLocked = _totalLocked.sub(_locked);

    _locked = _locked.sub(vested);
    _locked = _locked.add(lockedDelta).max(int256(0)).toUint256();

    _lockedByLocker[locker] = _locked;
    _totalLocked = _totalLocked.add(_locked);

    _burn(address(this), vested);

    lastVestedByLocker[locker] = block.number;
  }

  function _getVested(address locker) internal view returns (uint256) {
    return
      (_lockedByLocker[locker].mulDown(vestingSpeed) *
        (block.number.sub(lastVestedByLocker[locker]))).min(
          _lockedByLocker[locker]
        );
  }
}


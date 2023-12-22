// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import { IErrors } from "./Interfaces.sol";

interface ILockedToken {
  function lock(address fundingAccount, address account, uint256 amount) external;

  function withdrawExpiredLocksOnBehalf(address account, address to) external returns (uint224 amount);

  function processExpiredLocksOnBehalf(address account) external returns (uint224 amount);

  function isAutoextendDisabled(address account) external view returns (bool isAutoextendDisabled);

  function lockedBalanceOfExclPending(address account) external view returns (uint256 amount);

  function toggleAutoExtendOnBehalf(address _account) external;

  struct LockedBalance {
    uint224 amount;
    uint32 unlockTime;
  }

  enum Relock {
    False,
    AddToCurrent,
    AddToPending
  }

  struct Balance {
    uint224 locked;
    uint32 nextUnlockIndex;
    LockedBalance[] lockedBalances;
  }

  event Shutdown();
  event Locked(address indexed account, uint256 indexed epoch, uint256 amount, Relock relockType);
  event Withdrawn(address indexed account, uint256 amount, Relock relockType);
  event AutoExtendToggled(address indexed account, bool isAutoextendDisabled);

  error ZeroAddress();
  error ZeroAmount();
  error IsShutdown();
  error InvalidNumber(uint256 value);
}

contract LockedToken is ILockedToken, IErrors, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  string public name;
  string public symbol;
  IERC20Upgradeable public tokenToLock;
  uint8 public constant decimals = 18;

  uint32 public constant EPOCH_DURATION = 1 weeks; // 1 epoch = 1 week
  uint256 public constant LOCK_DURATION = 16 * EPOCH_DURATION; // Full lock duration = 16 epochs

  uint256 public lockedSupply;
  mapping(address => Balance) public balances;
  bool public isShutdown;
  mapping(address => bool) public isHandler;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    string memory _name,
    string memory _symbol,
    IERC20Upgradeable _tokenToLock
  ) public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
    __ReentrancyGuard_init();

    name = _name;
    symbol = _symbol;
    tokenToLock = _tokenToLock;
  }

  mapping(address => bool) public isAutoextendDisabled;

  function toggleAutoExtendOnBehalf(address _account) external nonReentrant {
    _validateHandler();

    bool _isAutoextendDisabled = isAutoextendDisabled[_account];

    if (balances[_account].locked > 0) {
      if (_isAutoextendDisabled) {
        _processExpiredLocks(_account, Relock.AddToPending, _account);
      } else {
        _processExpiredLocks(_account, Relock.AddToCurrent, _account);
      }
    }

    isAutoextendDisabled[_account] = !_isAutoextendDisabled;
    emit AutoExtendToggled(_account, !_isAutoextendDisabled);
  }

  function shutdown() external onlyOwner {
    if (isShutdown) revert IsShutdown();

    isShutdown = true;

    emit Shutdown();
  }

  function lockedBalanceOf(address account) external view returns (uint256 amount) {
    return balances[account].locked;
  }

  function lockedBalanceOfExclPending(address account) public view returns (uint256 amount) {
    amount = balances[account].locked;

    LockedBalance[] storage locks = balances[account].lockedBalances;
    uint256 locksLength = locks.length;

    if (locksLength > 0 && uint256(locks[locksLength - 1].unlockTime) - LOCK_DURATION > getCurrentEpoch()) {
      amount -= locks[locksLength - 1].amount;
    }

    return amount;
  }

  function activeBalanceOf(address account) external view returns (uint256 amount) {
    if (isAutoextendDisabled[account] == false) {
      return lockedBalanceOfExclPending(account);
    } else {
      return balanceOf(account);
    }
  }

  function balanceOf(address account) public view returns (uint256 amount) {
    Balance storage userBalance = balances[account];
    LockedBalance[] storage locks = userBalance.lockedBalances;
    uint256 nextUnlockIndex = userBalance.nextUnlockIndex;

    amount = balances[account].locked;
    uint256 locksLength = locks.length;

    for (uint256 i = nextUnlockIndex; i < locksLength; ++i) {
      if (locks[i].unlockTime <= block.timestamp) {
        amount -= locks[i].amount;
      } else {
        break;
      }
    }

    if (locksLength > 0 && uint256(locks[locksLength - 1].unlockTime) - LOCK_DURATION > getCurrentEpoch()) {
      amount -= locks[locksLength - 1].amount;
    }

    return amount;
  }

  function pendingLockOf(address account) external view returns (uint256 amount) {
    LockedBalance[] storage locks = balances[account].lockedBalances;

    uint256 locksLength = locks.length;

    if (locksLength > 0 && uint256(locks[locksLength - 1].unlockTime) - LOCK_DURATION > getCurrentEpoch()) {
      return locks[locksLength - 1].amount;
    }

    return 0;
  }

  function lockedBalances(
    address account
  ) external view returns (uint256 total, uint256 unlockable, uint256 locked, LockedBalance[] memory lockData) {
    Balance storage userBalance = balances[account];
    LockedBalance[] storage locks = userBalance.lockedBalances;
    uint256 nextUnlockIndex = userBalance.nextUnlockIndex;
    uint256 idx;

    for (uint256 i = nextUnlockIndex; i < locks.length; ++i) {
      if (locks[i].unlockTime > block.timestamp) {
        if (idx == 0) {
          lockData = new LockedBalance[](locks.length - i);
        }

        lockData[idx] = locks[i];
        locked += lockData[idx].amount;
        ++idx;
      } else {
        unlockable += locks[i].amount;
      }
    }

    return (userBalance.locked, unlockable, locked, lockData);
  }

  function getCurrentEpoch() public view returns (uint256) {
    return (block.timestamp / EPOCH_DURATION) * EPOCH_DURATION;
  }

  function lock(address fundingAccount, address account, uint256 amount) external {
    if (account == address(0)) revert ZeroAddress();
    if (amount == 0) revert ZeroAmount();
    _validateHandler();

    tokenToLock.safeTransferFrom(fundingAccount, address(this), amount);

    _lock(account, amount, Relock.AddToPending);
  }

  function _lock(address account, uint256 amount, Relock relockType) internal {
    if (isShutdown) revert IsShutdown();

    Balance storage balance = balances[account];
    uint224 lockAmount = _toUint224(amount);
    uint256 lockEpoch;
    uint256 unlockTime;

    unchecked {
      balance.locked += lockAmount;
      lockedSupply += lockAmount;
      lockEpoch = getCurrentEpoch() + (relockType == Relock.AddToPending ? EPOCH_DURATION : 0);
      unlockTime = lockEpoch + LOCK_DURATION;

      LockedBalance[] storage locks = balance.lockedBalances;
      uint256 idx = locks.length;

      if (relockType == Relock.AddToPending) {
        if (idx == 0 || locks[idx - 1].unlockTime < unlockTime) {
          locks.push(LockedBalance({ amount: lockAmount, unlockTime: _toUint32(unlockTime) }));
        } else {
          locks[idx - 1].amount += lockAmount;
        }
      } else {
        locks.push(LockedBalance({ amount: lockAmount, unlockTime: _toUint32(unlockTime) }));
      }
    }

    emit Locked(account, lockEpoch, amount, relockType);
  }

  function _processExpiredLocks(
    address account,
    Relock relockType,
    address withdrawTo
  ) internal returns (uint224 locked) {
    Balance storage userBalance = balances[account];
    LockedBalance[] storage locks = userBalance.lockedBalances;

    uint256 length = locks.length;

    if (length == 0) return locked;

    if (isShutdown || locks[length - 1].unlockTime <= block.timestamp) {
      locked = userBalance.locked;
      userBalance.nextUnlockIndex = _toUint32(length);
    } else {
      // Using nextUnlockIndex to reduce the number of loops
      uint32 nextUnlockIndex = userBalance.nextUnlockIndex;

      for (uint256 i = nextUnlockIndex; i < length; ++i) {
        // Unlock time must be less or equal to time
        if (locks[i].unlockTime > block.timestamp) break;

        // Add to cumulative amounts
        locked += locks[i].amount;
        ++nextUnlockIndex;
      }

      // Update the account's next unlock index
      userBalance.nextUnlockIndex = nextUnlockIndex;
    }

    if (locked == 0) return locked;

    // Update user balances and total supplies
    userBalance.locked -= locked;
    lockedSupply -= locked;

    emit Withdrawn(account, locked, relockType);

    // Relock or return to user
    if (relockType != Relock.False) {
      _lock(withdrawTo, locked, relockType);
    } else {
      tokenToLock.safeTransfer(withdrawTo, locked);
    }
  }

  function withdrawExpiredLocksOnBehalf(address account, address to) external nonReentrant returns (uint224 amount) {
    _validateHandler();

    if (to == address(0)) revert ZeroAddress();

    return _processExpiredLocks(account, Relock.False, to);
  }

  function processExpiredLocksOnBehalf(address account) external nonReentrant returns (uint224 amount) {
    _validateHandler();

    if (isAutoextendDisabled[account] == false) {
      return _processExpiredLocks(account, Relock.AddToCurrent, account);
    }

    return 0;
  }

  function _toUint224(uint256 value) internal pure returns (uint224) {
    if (value > type(uint224).max) revert InvalidNumber(value);

    return uint224(value);
  }

  function _toUint32(uint256 value) internal pure returns (uint32) {
    if (value > type(uint32).max) revert InvalidNumber(value);

    return uint32(value);
  }

  function _validateHandler() internal view {
    if (!isHandler[msg.sender]) revert UNAUTHORIZED(string.concat(symbol, ': ', '!handler'));
  }

  function setHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}


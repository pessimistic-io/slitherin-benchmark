// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

/**
 * @title LevelChest
 * @notice Open the LevelChest to get stamina potion. Trader can deposit their LVL token here to receive fee discount token. These token can be used to pay leverage trading fee instead of collateral. LVL deposited here will be locked to the end of the epoch. And whenever LVL released, the unused discount token will be burned as well.
 */
contract LevelChest is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct EpochInfo {
        uint64 startTime;
        /// @dev epoch duration in seconds
        uint32 duration;
        /// @notice fixed conversion rate from LVL to fee credit
        /// @dev 12 digits precision
        uint64 baseFeeCreditPerLvl;
        /// @notice extra fee credit reward to early deposit user, reduce gradually
        uint64 feeCreditPerLvl;
    }

    uint256 public constant RATE_PRECISION = 1e12;
    uint256 public constant MAX_EPOCH_DURATION = 30 days;
    uint256 public constant MAX_FEE_CREDIT_PER_LVL = 1e12;

    IERC20 public levelToken;

    /// @notice balance of Fee credit
    mapping(uint256 epochId => mapping(address user => uint256 amount)) public epochBalanceOf;
    mapping(address user => uint256 amount) public deposited;
    mapping(address user => uint256 lockedEpoch) public lastLockedEpoch;
    mapping(address user => bool disabled) public autoRenewDisabled;
    /// @notice only this address can spent fee credit
    address public tradingPool;
    /// @notice epoch id, start from 1
    uint256 public currentEpoch;
    mapping(uint256 epoch => EpochInfo) public epochInfos;

    /// @notice settings will be applied to the next epoch
    uint64 public baseFeeCreditPerLvl;
    uint64 public feeCreditPerLvl;
    uint32 public epochDuration;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _tradingPool,
        address _levelToken,
        uint64 _startTime,
        uint64 _baseFeeCreditPerLvl,
        uint64 _feeCreditPerLvl,
        uint32 _epochDuration
    ) external initializer {
        if (_levelToken == address(0)) revert InvalidAddress();
        if (_tradingPool == address(0)) revert InvalidAddress();

        __Ownable_init();
        __ReentrancyGuard_init();

        tradingPool = _tradingPool;
        levelToken = IERC20(_levelToken);

        _configEpoch(_baseFeeCreditPerLvl, _feeCreditPerLvl, _epochDuration);

        currentEpoch = 1;
        epochInfos[1] = EpochInfo({
            startTime: _startTime,
            baseFeeCreditPerLvl: _baseFeeCreditPerLvl,
            feeCreditPerLvl: _feeCreditPerLvl,
            duration: _epochDuration
        });

        emit EpochStarted(1, _startTime);
    }

    // ===== View functions =====

    function getCurrentEpoch() external view returns (uint256, EpochInfo memory) {
        return (currentEpoch, epochInfos[currentEpoch]);
    }

    function balanceOf(address _user) external view returns (uint256) {
        if (lastLockedEpoch[_user] == currentEpoch) {
            // fee credit balance synced
            return epochBalanceOf[currentEpoch][_user];
        }
        uint256 currentEpochStartTime = epochInfos[currentEpoch].startTime;
        if (currentEpochStartTime > block.timestamp || autoRenewDisabled[_user]) {
            return 0;
        }
        return _calcFeeCredit(currentEpochStartTime, deposited[_user]);
    }

    /// @notice return unlocked LVL, all or nothing
    function getUnlocked(address _user) public view returns (uint256) {
        return lastLockedEpoch[_user] < currentEpoch && autoRenewDisabled[_user] ? deposited[_user] : 0;
    }

    // ===== Mutative functions =====

    /// @notice deposit LVL to get fee discount token. The unlocked LVL from previous epochs will be auto renew as well
    function deposit(uint256 _amount) external nonReentrant {
        address user = msg.sender;
        bool isRenewed = _tryRenew(user);

        if (!isRenewed && _amount == 0) revert EmptyDeposit();

        uint256 feeCreditAmount = _calcFeeCredit(block.timestamp, _amount);
        lastLockedEpoch[user] = currentEpoch;
        deposited[user] += _amount;
        epochBalanceOf[currentEpoch][user] += feeCreditAmount;

        // since LVL is not inflationary token, we skip check actual amount received
        if (_amount > 0) {
            levelToken.safeTransferFrom(user, address(this), _amount);
        }
        emit Deposited(currentEpoch, user, _amount, feeCreditAmount);
    }

    function withdraw(address _to) external nonReentrant {
        address user = msg.sender;
        uint256 unlocked = getUnlocked(user);
        if (unlocked == 0) revert NothingToWithdraw();

        deposited[user] -= unlocked;
        autoRenewDisabled[user] = false;
        levelToken.safeTransfer(_to, unlocked);
        emit Withdrawn(currentEpoch, user, unlocked);
    }

    function setAutoRenew(bool enabled) external {
        address user = msg.sender;
        if (autoRenewDisabled[user] == !enabled) {
            return;
        }

        _tryRenew(user);
        autoRenewDisabled[user] = !enabled;
        emit AutoRenewSet(user, enabled);
    }

    /// @notice tradingPool try to get fee discount, returns the remaining amount
    function tryDiscount(address _user, uint256 _amount) external returns (uint256 remaining) {
        if (msg.sender != tradingPool) revert OnlyTradingPool();
        if (!autoRenewDisabled[_user]) {
            _tryRenew(_user);
        }
        uint256 balance = epochBalanceOf[currentEpoch][_user];

        uint256 discountAmount = balance > _amount ? _amount : balance;
        remaining = _amount - discountAmount;
        if (discountAmount > 0) {
            epochBalanceOf[currentEpoch][_user] = balance - discountAmount;
            emit FeeDiscounted(_user, discountAmount);
        }
    }

    function nextEpoch() external {
        // save SLOAD
        uint256 _currentEpoch = currentEpoch;
        EpochInfo memory epoch = epochInfos[_currentEpoch];
        if (epoch.startTime + epoch.duration > block.timestamp) revert EpochNotEnded();

        // just in case a number of epoch past without triggering
        uint256 startTime = epoch.startTime + (block.timestamp - epoch.startTime) / epoch.duration * epoch.duration;
        uint256 nextEpochId = _currentEpoch + 1;

        currentEpoch = nextEpochId;
        epochInfos[nextEpochId] = EpochInfo({
            startTime: uint64(startTime),
            duration: epochDuration,
            feeCreditPerLvl: feeCreditPerLvl,
            baseFeeCreditPerLvl: baseFeeCreditPerLvl
        });

        // this block.timestamp seem redundant, but we need it to track the first epoch, which not start at the time of initial
        emit EpochStarted(currentEpoch, block.timestamp);
    }

    function configEpoch(uint64 _feeCreditPerLvl, uint16 _extraRate, uint32 _epochDuration) external onlyOwner {
        _configEpoch(_feeCreditPerLvl, _extraRate, _epochDuration);
    }

    function _tryRenew(address _user) internal returns (bool renewed) {
        if (deposited[_user] == 0 || lastLockedEpoch[_user] == currentEpoch) {
            return false;
        }

        uint256 renewTime = autoRenewDisabled[_user] ? block.timestamp : epochInfos[currentEpoch].startTime;
        uint256 renewAmount = deposited[_user];
        uint256 feeCreditAmount = _calcFeeCredit(renewTime, renewAmount);
        lastLockedEpoch[_user] = currentEpoch;
        epochBalanceOf[currentEpoch][_user] += feeCreditAmount;
        emit Renewed(currentEpoch, _user, renewAmount, feeCreditAmount);
        return true;
    }

    function _calcFeeCredit(uint256 _lockTime, uint256 _lockAmount) internal view returns (uint256) {
        EpochInfo memory epoch = epochInfos[currentEpoch];
        // let it throw when epoch not started yet
        uint256 epochEnd = epoch.startTime + epoch.duration;
        uint256 timeUntilEnd = _lockTime > epochEnd ? 0 : epochEnd - _lockTime;

        // base_fee_credit_per_LVL * lvl_amount + fee_credit_per_lvl * lvl_amount * time_until_end / duration
        return (
            epoch.baseFeeCreditPerLvl * _lockAmount * RATE_PRECISION
                + epoch.feeCreditPerLvl * _lockAmount * timeUntilEnd * RATE_PRECISION / epoch.duration
        ) / RATE_PRECISION;
    }

    function _configEpoch(uint64 _baseFeeCreditPerLvl, uint64 _feeCreditPerLvl, uint32 _epochDuration) internal {
        if (_epochDuration == 0 || _epochDuration > MAX_EPOCH_DURATION) revert InvalidEpochConfig();
        if (_feeCreditPerLvl > MAX_FEE_CREDIT_PER_LVL) revert InvalidEpochConfig();
        if (_baseFeeCreditPerLvl > MAX_FEE_CREDIT_PER_LVL) revert InvalidEpochConfig();

        epochDuration = _epochDuration;
        baseFeeCreditPerLvl = _baseFeeCreditPerLvl;
        feeCreditPerLvl = _feeCreditPerLvl;

        emit EpochConfigured(_baseFeeCreditPerLvl, _feeCreditPerLvl, _epochDuration);
    }

    // ===== Errors =====

    error EpochNotEnded();
    error NothingToWithdraw();
    error OnlyTradingPool();
    error InvalidAddress();
    error EmptyDeposit();
    error InvalidEpochConfig();

    // ===== Events =====

    event EpochStarted(uint256 indexed epoch, uint256 startTime);
    event Deposited(uint256 indexed epoch, address indexed user, uint256 lockAmount, uint256 feeCreditAmount);
    event Withdrawn(uint256 indexed epoch, address indexed user, uint256 amount);
    event Renewed(uint256 indexed epoch, address indexed user, uint256 renewAmount, uint256 feeCreditAmount);
    event FeeDiscounted(address indexed user, uint256 amount);
    event AutoRenewSet(address indexed user, bool isEnabled);
    event EpochConfigured(uint64 baseFeeCreditPerLvl, uint64 feeCreditPerLvl, uint32 epochDuration);
}


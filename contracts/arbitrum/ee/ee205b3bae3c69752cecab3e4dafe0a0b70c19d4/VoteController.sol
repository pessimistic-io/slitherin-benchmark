// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";

import "./IVoteController.sol";
import "./ILocker.sol";

import "./SafeDecimalMath.sol";

contract VoteController is IVoteController, OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 public constant LOCK_UNIT_MAX = 2 * 365 days; // 2 years
    uint256 public constant LOCK_UNIT_BASE = 7 days;

    /* ========== STATE VARIABLES ========== */

    ILocker public locker;

    address[65535] private _pools;
    uint256 public poolSize;
    uint256 public disabledPoolSize;

    // Locked balance of an account, which is synchronized with locker
    mapping(address => IVoteController.LockedBalance) public userLockedBalances;

    // mapping of account => pool => fraction of the user's veGRV voted to the pool
    mapping(address => mapping(address => uint256)) public override userWeights;

    // mapping of pool => unlockTime => GRV amount voted to the pool that will be unlock at unlockTime
    mapping(address => mapping(uint256 => uint256)) public poolScheduledUnlock;

    // mapping of pool index => status of the pool
    mapping(uint256 => bool) public disabledPools;

    /* ========== INITIALIZER ========== */

    function initialize(address _locker) external initializer {
        __Ownable_init();
        locker = ILocker(_locker);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function addPool(address newPool) external override onlyOwner {
        uint256 size = poolSize;
        _pools[size] = newPool;
        poolSize = size + 1;
        emit PoolAdded(newPool);
    }

    function togglePool(uint256 index) external override onlyOwner {
        require(index < poolSize, "Invalid index");
        if (disabledPools[index]) {
            disabledPools[index] = false;
            disabledPoolSize--;
        } else {
            disabledPools[index] = true;
            disabledPoolSize++;
        }
        emit PoolToggled(_pools[index], disabledPools[index]);
    }

    /* ========== VIEWS ========== */

    function getPools() external view override returns (address[] memory) {
        uint256 size = poolSize;
        address[] memory pools = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            pools[i] = _pools[i];
        }
        return pools;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balanceOfAtTimestamp(account, block.timestamp);
    }

    function balanceOfAtTimestamp(address account, uint256 timestamp) public view returns (uint256) {
        require(timestamp >= block.timestamp, "Must be current or future time");
        IVoteController.LockedBalance memory locked = userLockedBalances[account];
        if (timestamp >= locked.unlockTime) {
            return 0;
        }
        return locked.amount.mul(locked.unlockTime - timestamp) / LOCK_UNIT_MAX;
    }

    function totalSupply() external view override returns (uint256) {
        return totalSupplyAtTimestamp(block.timestamp);
    }

    function totalSupplyAtTimestamp(uint256 timestamp) public view returns (uint256) {
        uint256 size = poolSize;
        uint256 total = 0;
        for (uint256 i = 0; i < size; i++) {
            total = total.add(sumAtTimestamp(_pools[i], timestamp));
        }
        return total;
    }

    function sumAtTimestamp(address pool, uint256 timestamp) public view override returns (uint256) {
        uint256 sum = 0;
        for (
            uint256 weekCursor = _truncateExpiry(timestamp);
            weekCursor <= timestamp + LOCK_UNIT_MAX;
            weekCursor += 1 weeks
        ) {
            sum = sum.add(poolScheduledUnlock[pool][weekCursor].mul(weekCursor - timestamp) / LOCK_UNIT_MAX);
        }
        return sum;
    }

    function count(
        uint256 timestamp
    ) external view override returns (uint256[] memory weights, address[] memory pools) {
        uint256 poolSize_ = poolSize;
        uint256 size = poolSize_ - disabledPoolSize;
        pools = new address[](size);
        uint256 j = 0;
        for (uint256 i = 0; i < poolSize_ && j < size; i++) {
            address pool = _pools[i];
            if (!disabledPools[i]) pools[j++] = pool;
        }

        uint256[] memory sums = new uint256[](size);
        uint256 total = 0;
        for (uint256 i = 0; i < size; i++) {
            uint256 sum = sumAtTimestamp(pools[i], timestamp);
            sums[i] = sum;
            total = total.add(sum);
        }

        weights = new uint256[](size);
        if (total == 0) {
            for (uint256 i = 0; i < size; i++) {
                weights[i] = 1e18 / size;
            }
        } else {
            for (uint256 i = 0; i < size; i++) {
                weights[i] = sums[i].divideDecimal(total);
            }
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function cast(uint256[] memory weights) external override {
        uint256 size = poolSize;
        require(weights.length == size, "Invalid number of weights");
        uint256 totalWeight;
        for (uint256 i = 0; i < size; i++) {
            totalWeight = totalWeight.add(weights[i]);
        }
        require(totalWeight == 1e18, "Invalid weights");

        uint256[] memory oldWeights = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            oldWeights[i] = userWeights[msg.sender][_pools[i]];
        }

        IVoteController.LockedBalance memory oldLockedBalance = userLockedBalances[msg.sender];

        uint256 lockedAmount = locker.balanceOf(msg.sender);
        uint256 unlockTime = locker.expiryOf(msg.sender);

        IVoteController.LockedBalance memory lockedBalance = IVoteController.LockedBalance({
            amount: lockedAmount,
            unlockTime: unlockTime
        });

        require(lockedBalance.amount > 0 && lockedBalance.unlockTime > block.timestamp, "No veGRV");

        _updateVoteStatus(msg.sender, size, oldWeights, weights, oldLockedBalance, lockedBalance);
    }

    function syncWithLocker(address account) external override {
        IVoteController.LockedBalance memory oldLockedBalance = userLockedBalances[account];
        if (oldLockedBalance.amount == 0) {
            return; // The account did not voted before
        }

        uint256 lockedAmount = locker.balanceOf(msg.sender);
        uint256 unlockTime = locker.expiryOf(msg.sender);

        IVoteController.LockedBalance memory lockedBalance = IVoteController.LockedBalance({
            amount: lockedAmount,
            unlockTime: unlockTime
        });

        uint256 size = poolSize;
        uint256[] memory weights = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            weights[i] = userWeights[account][_pools[i]];
        }

        _updateVoteStatus(account, size, weights, weights, oldLockedBalance, lockedBalance);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _updateVoteStatus(
        address account,
        uint256 size,
        uint256[] memory oldWeights,
        uint256[] memory weights,
        IVoteController.LockedBalance memory oldLockedBalance,
        IVoteController.LockedBalance memory lockedBalance
    ) private {
        for (uint256 i = 0; i < size; i++) {
            address pool = _pools[i];
            poolScheduledUnlock[pool][oldLockedBalance.unlockTime] = poolScheduledUnlock[pool][
                oldLockedBalance.unlockTime
            ].sub(oldLockedBalance.amount.multiplyDecimal(oldWeights[i]));

            poolScheduledUnlock[pool][lockedBalance.unlockTime] = poolScheduledUnlock[pool][lockedBalance.unlockTime]
                .add(lockedBalance.amount.multiplyDecimal(weights[i]));
            userWeights[account][pool] = weights[i];
        }
        userLockedBalances[account] = lockedBalance;
        emit Voted(
            account,
            oldLockedBalance.amount,
            oldLockedBalance.unlockTime,
            oldWeights,
            lockedBalance.amount,
            lockedBalance.unlockTime,
            weights
        );
    }

    function _truncateExpiry(uint256 time) private view returns (uint256) {
        if (time > block.timestamp.add(LOCK_UNIT_MAX)) {
            time = block.timestamp.add(LOCK_UNIT_MAX);
        }
        return (time.div(LOCK_UNIT_BASE).mul(LOCK_UNIT_BASE)).add(LOCK_UNIT_BASE);
    }
}


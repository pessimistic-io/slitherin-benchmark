// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20.sol";
import "./IRewardPool.sol";

struct Point {
    int128 bias;
    int128 slope;
    uint256 ts;
    uint256 blk; // block
}

struct LockedBalance {
    int128 amount;
    uint256 end;
}

/**
 * @dev Allows FOREX holders to lock tokens for veFOREX and gain Handle DAO
 *      voting power.
 *      FOREX may be locked for up to 1 year.
 *      The user's veFOREX balance decays linearly during the locked period
 *      until FOREX is fully unlocked.
 *      A locked position may be added to or have its duration extended at
 *      any time for an increase in veFOREX voting power.
 */
contract GovernanceLock is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    int128 public constant MAX_TIME = 365 * 86400; // 1 year
    bytes32 public constant REWARD_POOL_ALIAS = keccak256("governancelock-blp");

    /** @dev The token to be locked. e.g. FOREX */
    address public token;
    /** @dev The supply of token's locked */
    uint256 public supply;
    /** @dev Mapping from account address to locked balance position */
    mapping(address => LockedBalance) public locked;
    /** @dev The current system epoch */
    uint256 public epoch;
    /** @dev Mapping from epoch to point history */
    mapping(uint256 => Point) public pointHistory;
    /** @dev Mapping from account address to epoch to point history */
    mapping(address => mapping(uint256 => Point)) public userPointHistory;
    /** @dev Mapping from account address to current user epoch */
    mapping(address => uint256) public userPointEpoch;
    /** @dev Mapping from slope changes @ "week time" to slope value */
    mapping(uint256 => int128) public slopeChanges;
    /** @dev Mapping from contract address to its whitelisted status */
    mapping(address => bool) public whitelistedContracts;
    /** @dev Whether the whitelist is enabled for contract access */
    bool public isWhitelistEnabled;
    /** @dev The Handle reward pool for rewarding locking */
    IRewardPool public rewardPool;

    uint256 public constant WEEK = 7 * 86400;
    uint256 public constant MULTIPLIER = 1 ether;

    /** @dev Whether the contract has been retired and token refunds are on */
    bool public retiredContract;

    enum DepositType {
        DepositFor,
        CreateLock,
        IncreaseLockAmount,
        IncreaseUnlockTime
    }

    event Deposit(
        address indexed depositor,
        uint256 value,
        uint256 indexed locktime,
        DepositType depositType,
        uint256 ts
    );
    event Withdraw(address indexed depositor, uint256 value, uint256 ts);
    event Supply(uint256 previousSupply, uint256 supply);

    /**
     * @dev Reverts the tranasction if the sender is a contract and not
     *      whitelisted.
     */
    modifier onlyAllowedLocker() {
        require(
            !isWhitelistEnabled ||
                !isContract(msg.sender) ||
                whitelistedContracts[msg.sender],
            "Contract not allowed"
        );
        _;
    }

    /** @dev Proxy initialisation function */
    function initialize(address tokenAddress, address rewardPoolAddress)
        public
        initializer
        onlyProxy
    {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        token = tokenAddress;
        rewardPool = IRewardPool(rewardPoolAddress);
        isWhitelistEnabled = true;
        pointHistory[0].blk = block.number;
        pointHistory[0].ts = block.timestamp;
    }

    /**
     * @dev "Retires" the contract by allowing refunds and preventing new deposits.
     * @param isRetired Whether to retire the contract.
     */
    function retireContract(bool isRetired) external onlyOwner {
        retiredContract = isRetired;
    }

    /**
     * @dev Adds or removes a contract access from the whitelist.
     */
    function setContractWhitelist(address contractAddress, bool isWhitelisted)
        external
        onlyOwner
    {
        whitelistedContracts[contractAddress] = isWhitelisted;
    }

    /**
     * @dev Enables or disables the contract access whitelist.
     */
    function setWhitelistEnabled(bool isEnabled) external onlyOwner {
        isWhitelistEnabled = isEnabled;
    }

    /**
     * @dev Returns user slope at last user epoch.
     */
    function getLastUserSlope(address account) external view returns (int128) {
        uint256 userEpoch = userPointEpoch[account];
        return userPointHistory[account][userEpoch].slope;
    }

    /**
     * @dev Getter for user point history at point idx
     */
    function userPointHistoryTs(address account, uint256 idx)
        external
        view
        returns (uint256)
    {
        return userPointHistory[account][idx].ts;
    }

    /**
     * @dev Getter for account's locked position end time.
     */
    function lockedEnd(address account) external view returns (uint256) {
        return locked[account].end;
    }

    /**
     * @dev Updates the system state and optionally for a given account.
     */
    function _checkpoint(
        address account,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) private {
        Point memory uOld = EMPTY_POINT_FACTORY();
        Point memory uNew = EMPTY_POINT_FACTORY();
        int128 oldDslope;
        int128 newDslope;
        uint256 _epoch = epoch;

        if (account != address(0)) {
            // Calculate slopes and biases
            // kept at zero when they have to
            if (oldLocked.end > block.timestamp && oldLocked.amount > 0) {
                uOld.slope = oldLocked.amount / MAX_TIME;
                uOld.bias =
                    uOld.slope *
                    int128(int256(oldLocked.end) - int256(block.timestamp));
            }
            if (newLocked.end > block.timestamp && newLocked.amount > 0) {
                uNew.slope = newLocked.amount / MAX_TIME;
                uNew.bias =
                    uNew.slope *
                    int128(int256(newLocked.end) - int256(block.timestamp));
            }
            // Read values of schedules changes in the slope
            // oldLocked.end can be in the past and in the future
            // newLocked.end can ONLY be in the FUTURE unless everything
            // expired: then zeros
            oldDslope = slopeChanges[oldLocked.end];
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[newLocked.end];
                }
            }
        }

        Point memory lastPoint =
            Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});

        if (epoch > 0) lastPoint = pointHistory[_epoch];
        uint256 lastCheckpoint = lastPoint.ts;

        // Used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as it cannot be figured out exactly from inside the contract
        Point memory initialLastPoint = lastPoint;
        uint256 blockSlope;
        if (block.timestamp > lastPoint.ts)
            blockSlope =
                (MULTIPLIER * (block.number - lastPoint.blk)) /
                (block.timestamp - lastPoint.ts);

        // Round to nearest week.
        // Go over weeks to fill history and calculate what the current point
        // is.
        {
            uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
            for (uint256 i = 0; i < 255; i++) {
                // If this does not get used in 5 years, users will be able to
                // withdraw but vote weight will be broken.
                t_i += WEEK;
                int128 dSlope;
                if (t_i > block.timestamp) {
                    t_i = block.timestamp;
                } else {
                    dSlope = slopeChanges[t_i];
                }
                lastPoint.bias -=
                    lastPoint.slope *
                    int128(int256(t_i) - int256(lastCheckpoint));
                lastPoint.slope += dSlope;
                // This can happen.
                if (lastPoint.bias < 0) {
                    lastPoint.bias = 0;
                }
                // In theory this cannot happen.
                if (lastPoint.slope < 0) {
                    lastPoint.slope = 0;
                }
                lastCheckpoint = t_i;
                lastPoint.ts = t_i;
                lastPoint.blk =
                    initialLastPoint.blk +
                    (blockSlope * (t_i - initialLastPoint.ts)) /
                    MULTIPLIER;
                _epoch += 1;
                if (t_i == block.timestamp) {
                    lastPoint.blk = block.number;
                    break;
                } else {
                    pointHistory[_epoch] = lastPoint;
                }
            }
        }
        epoch = _epoch;
        // pointHistory is now up to date with current block
        if (account != address(0)) {
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) lastPoint.slope = 0;
            if (lastPoint.bias < 0) lastPoint.bias = 0;
        }
        // Record the changed point into history
        pointHistory[_epoch] = lastPoint;
        if (account != address(0)) {
            // Schedule the slope changes (slope is going down)
            // Subtract new slope from [newLocked.end]
            // Add old slope to [oldLocked.epoch]
            if (oldLocked.end > block.timestamp) {
                oldDslope += uOld.slope;
                if (newLocked.end == oldLocked.end) oldDslope -= uNew.slope; // new deposit, not extension
                slopeChanges[oldLocked.end] = oldDslope;
            }
            if (newLocked.end > block.timestamp) {
                if (newLocked.end > oldLocked.end) {
                    newDslope -= uNew.slope;
                    slopeChanges[newLocked.end] = newDslope;
                }
                // else: has already been recorded in oldDslope
            }
            // Handle user history
            uint256 userEpoch = userPointEpoch[account] + 1;
            userPointEpoch[account] = userEpoch;
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            userPointHistory[account][userEpoch] = Point({
                bias: uNew.bias,
                slope: uNew.slope,
                ts: block.timestamp,
                blk: block.number
            });
        }
    }

    /**
     * @dev Internal function to handle FOREX deposits and/or locktime increase.
     */
    function _depositFor(
        address account,
        uint256 value,
        uint256 unlockTime,
        LockedBalance memory lockedBalance,
        DepositType depositType
    ) private {
        require(!retiredContract, "Contract retired");
        LockedBalance memory _locked = lockedBalance;
        uint256 supplyBefore = supply;
        supply = supplyBefore + value;
        LockedBalance memory oldLocked =
            LockedBalance({amount: _locked.amount, end: _locked.end});
        // Adding to existing lock, or if expired create a new one
        _locked.amount += int128(int256(value));
        if (unlockTime != 0) _locked.end = unlockTime;
        locked[account] = _locked;
        // Possibilities:
        // both oldLocked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(account, oldLocked, _locked);
        if (value != 0)
            IERC20(token).safeTransferFrom(account, address(this), value);
        // Stake into reward pool.
        uint256 stakeAmount =
            _locked.amount > 0 ? uint256(uint128(_locked.amount)) : 0;
        setUserRewardStakeAmount(account, stakeAmount);
        emit Deposit(account, value, _locked.end, depositType, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + value);
    }

    /**
     * @dev Sets the staked value in the veFOREX reward pool for an account.
     */
    function setUserRewardStakeAmount(address account, uint256 value) private {
        if (retiredContract) return;
        (bool foundRewardPool, uint256 rewardPoolId) =
            rewardPool.getPoolIdByAlias(REWARD_POOL_ALIAS);
        if (!foundRewardPool) return;
        // Unstake current amount from pool.
        // TODO: check that the error return value is nonzero.
        rewardPool.unstake(account, 2**256 - 1, rewardPoolId);
        if (value > 0) {
            // Stake value.
            // TODO: check that the error return value is nonzero.
            rewardPool.stake(account, value, rewardPoolId);
        }
    }

    /**
     * @dev Updates the system state without affecting any
     *      specific account directly.
     */
    function checkpoint() external {
        LockedBalance memory empty;
        _checkpoint(
            address(0),
            EMPTY_LOCKED_BALANCE_FACTORY(),
            EMPTY_LOCKED_BALANCE_FACTORY()
        );
    }

    /**
     * @dev Increases the locked FOREX amount for an account by depositing more.
     */
    function depositFor(address account, uint256 value) external {
        LockedBalance storage _locked = locked[account];
        assert(value > 0);
        assert(_locked.amount > 0);
        assert(_locked.end > block.timestamp);
        _depositFor(account, value, 0, locked[account], DepositType.DepositFor);
    }

    /**
     * @dev Opens a new locked FOREX position for the message sender.
     */
    function createLock(uint256 value, uint256 unlockTime)
        external
        onlyAllowedLocker
    {
        // Round unlockTime to weeks.
        unlockTime = (unlockTime / WEEK) * WEEK;
        LockedBalance memory _locked = locked[msg.sender];
        assert(value > 0);
        require(_locked.amount == 0, "Withdraw old tokens first");
        require(unlockTime > block.timestamp, "Must unlock in the future");
        require(
            unlockTime <= block.timestamp + uint256(uint128(MAX_TIME)),
            "Lock must not be > 1 year"
        );
        _depositFor(
            msg.sender,
            value,
            unlockTime,
            _locked,
            DepositType.CreateLock
        );
    }

    /**
     * @dev Increases FOREX lock amount.
     */
    function increaseAmount(uint256 value) external onlyAllowedLocker {
        LockedBalance storage _locked = locked[msg.sender];
        assert(value > 0);
        require(_locked.amount > 0, "No existing lock");
        require(_locked.end > block.timestamp, "Lock has expired");
        _depositFor(
            msg.sender,
            value,
            0,
            _locked,
            DepositType.IncreaseLockAmount
        );
    }

    /**
     * @dev Increases FOREX lock time.
     */
    function increaseUnlockTime(uint256 unlockTime) external onlyAllowedLocker {
        LockedBalance storage _locked = locked[msg.sender];
        // Round unlockTime to weeks.
        unlockTime = (unlockTime / WEEK) * WEEK;
        require(_locked.end > block.timestamp, "Lock has expired");
        require(_locked.amount > 0, "Nothing is locked");
        require(unlockTime > _locked.end, "Cannot decrease lock duration");
        require(
            unlockTime <= block.timestamp + uint256(uint128(MAX_TIME)),
            "Lock must not be > 1 year"
        );
        _depositFor(
            msg.sender,
            0,
            unlockTime,
            _locked,
            DepositType.IncreaseUnlockTime
        );
    }

    /**
     * @dev Withdraws fully unlocked FOREX from contract as well as rewards.
     */
    function withdraw() external {
        LockedBalance storage _locked = locked[msg.sender];
        require(
            retiredContract || block.timestamp >= _locked.end,
            "The lock didn't expire"
        );
        require(_locked.amount > 0, "Nothing to withdraw");
        uint256 value = uint256(uint128(_locked.amount));
        LockedBalance memory oldLocked =
            LockedBalance({amount: _locked.amount, end: _locked.end});
        _locked.end = 0;
        _locked.amount = 0;
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;
        if (!retiredContract) _checkpoint(msg.sender, oldLocked, _locked);
        IERC20(token).safeTransfer(msg.sender, value);
        // Unstake from reward pool.
        setUserRewardStakeAmount(msg.sender, 0);
        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore - value);
    }

    /**
     * @dev Finds epoch from block number and max epoch search range.
     */
    function findBlockEpoch(uint256 blockNumber, uint256 maxEpoch)
        private
        view
        returns (uint256 minEpoch)
    {
        minEpoch = 0;
        // Binary search for 128 bit value
        for (uint256 i = 0; i < 128; i++) {
            if (minEpoch >= maxEpoch) break;
            uint256 midEpoch = (minEpoch + maxEpoch + 1) / 2;
            if (pointHistory[midEpoch].blk <= blockNumber) {
                minEpoch = midEpoch;
            } else {
                maxEpoch = midEpoch - 1;
            }
        }
    }

    /**
     * @dev Returns an account's veFOREX balance.
     */
    function balanceOf(address account) public view returns (uint256) {
        uint256 epoch = userPointEpoch[account];
        if (epoch == 0) return 0;
        Point memory lastPoint = userPointHistory[account][epoch];
        lastPoint.bias -=
            lastPoint.slope *
            int128(int256(block.timestamp - lastPoint.ts));
        if (lastPoint.bias < 0) lastPoint.bias = 0;
        return uint256(uint128(lastPoint.bias));
    }

    /**
     * @dev Returns the veFOREX supply at time t.
     */
    function supplyAt(Point memory point, uint256 t)
        private
        view
        returns (uint256)
    {
        uint256 t_i = (point.ts / WEEK) * WEEK;
        for (uint256 i = 0; i < 255; i++) {
            t_i += WEEK;
            int128 dSlope;
            if (t_i > t) {
                t_i = t;
            } else {
                dSlope = slopeChanges[t_i];
            }
            point.bias -= point.slope * int128(int256(t_i) - int256(point.ts));
            if (t_i == t) break;
            point.slope += dSlope;
            point.ts = t_i;
        }
        if (point.bias < 0) point.bias = 0;
        return uint256(uint128(point.bias));
    }

    /**
     * @dev Returns the total veFOREX supply.
     */
    function totalSupply() external view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory lastPoint = pointHistory[epoch];
        return supplyAt(lastPoint, block.timestamp);
    }

    /**
     * @dev Returns the total veFOREX supply at a block.
     * @param blockNumber The block to calculate the supply at.
     */
    function totalSupplyAt(uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        require(blockNumber <= block.number);
        uint256 _epoch = epoch;
        uint256 targetEpoch = findBlockEpoch(blockNumber, _epoch);

        Point memory point = pointHistory[targetEpoch];
        uint256 dt = 0;

        if (targetEpoch < _epoch) {
            Point memory pointNext = pointHistory[targetEpoch + 1];
            if (point.blk != pointNext.blk) {
                dt =
                    ((blockNumber - point.blk) * (pointNext.ts - point.ts)) /
                    (pointNext.blk - point.blk);
            }
        } else if (point.blk != block.number) {
            dt =
                ((blockNumber - point.blk) * (block.timestamp - point.ts)) /
                (block.number - point.blk);
        }

        // Now, dt contains info on how far the current block is beyond "point".
        return supplyAt(point, point.ts + dt);
    }

    /**
     * @dev Measure balance of `account` at block height `blockNumber`
     * @param account Account to check balance from
     * @param blockNumber Block to calculate the balance at
     */
    function balanceOfAt(address account, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        require(blockNumber <= block.number);

        // Binary search
        uint256 _min = 0;
        uint256 _max = userPointEpoch[account];

        // Will be always enough for 128-bit numbers
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[account][_mid].blk <= blockNumber) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }

        Point memory upoint = userPointHistory[account][_min];
        uint256 max_epoch = epoch;
        uint256 _epoch = findBlockEpoch(blockNumber, max_epoch);
        Point memory point_0 = pointHistory[_epoch];
        uint256 d_block = 0;
        uint256 d_t = 0;

        if (_epoch < max_epoch) {
            Point memory point_1 = pointHistory[_epoch + 1];
            d_block = point_1.blk - point_0.blk;
            d_t = point_1.ts - point_0.ts;
        } else {
            d_block = block.number - point_0.blk;
            d_t = block.timestamp - point_0.ts;
        }

        uint256 block_time = point_0.ts;
        if (d_block != 0) {
            block_time += (d_t * (blockNumber - point_0.blk)) / d_block;
        }
        upoint.bias -=
            upoint.slope *
            (int128(uint128(block_time)) - int128(uint128(upoint.ts)));

        return upoint.bias >= 0 ? uint256(int256(upoint.bias)) : 0;
    }

    /**
     * @dev Returns whether addr is a contract (except for constructor).
     */
    function isContract(address addr) private returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function EMPTY_POINT_FACTORY() private view returns (Point memory) {
        return Point({bias: 0, slope: 0, ts: 0, blk: 0});
    }

    function EMPTY_LOCKED_BALANCE_FACTORY()
        private
        view
        returns (LockedBalance memory)
    {
        return LockedBalance({amount: 0, end: 0});
    }

    /** @dev Protected UUPS upgrade authorization fuction */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

